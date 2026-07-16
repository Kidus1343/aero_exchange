open Core
open Types

module Order_book = struct
  (* ── Capacities (init-time only) ─────────────────────────── *)
  let max_orders      = 131072
  let max_levels      = 2048
  let max_trades      = 1024
  let tbl_size        = 262144
  let tbl_mask        = tbl_size - 1

  (* ── Book state ───────────────────────────────────────────── *)
  (* Correction from an earlier revision: fields here used to be
     typed "int# array", following an invented "Int#" module that
     doesn't exist in OxCaml. Plain OCaml `int` is already an
     unboxed machine word (a tagged immediate) — there is no boxed
     representation to eliminate, so a plain `int array` already
     gives flat, zero-allocation storage and access. OxCaml's real
     unboxed-number modules (Float_u, Int32_u, Int64_u, Nativeint_u)
     exist for types that are *normally* boxed; `int` isn't one of
     them. The one field that's genuinely a candidate for OxCaml's
     float# is the trade timestamp threaded through the recursive
     matching loop below — see `match_loop`.                      *)
  type t = {
    (* legacy maps kept for Bonsai UI — never touched on hot path *)
    mutable bids          : int Int.Map.t;
    mutable asks          : int Int.Map.t;
    mutable volume_at_price : int Int.Map.t;
    orders                : Order.t Hashtbl.M(Int).t;

    (* ── flat order pool ──────────────────────────────────────
       Plain int arrays: already a flat, non-allocating layout in
       OCaml (no boxing to begin with), so every access here is a
       single load/store with no indirection and no OxCaml needed. *)
    orders_id    : int array;
    orders_price : int array;
    orders_qty   : int array;
    orders_side  : int array;
    orders_next  : int array;   (* free-list / linked-list next *)
    orders_prev  : int array;
    mutable free_head : int;     (* head of free-slot singly-linked list *)

    (* ── open-addressed hash table: id -> slot index ───────── *)
    tbl_keys : int array;
    tbl_vals : int array;

    (* ── bid / ask price levels (sorted contiguous arrays) ──── *)
    bids_price : int array;
    bids_qty   : int array;
    bids_head  : int array;
    bids_tail  : int array;
    mutable bids_count : int;

    asks_price : int array;
    asks_qty   : int array;
    asks_head  : int array;
    asks_tail  : int array;
    mutable asks_count : int;

    (* ── volume-at-price tracker ─────────────────────────────  *)
    vol_price : int array;
    vol_qty   : int array;
    mutable vol_count : int;

    (* ── pre-allocated trade ring buffer ─────────────────────  *)
    trades_price : int array;
    trades_qty   : int array;
    trades_side  : int array;
    trades_time  : float array;  (* stock OCaml already stores float
                                     arrays flat/unboxed; the OxCaml
                                     win is keeping the *scalar* ts
                                     value unboxed while it's threaded
                                     through the recursive hot loop,
                                     not the array storage itself.   *)
    mutable trades_count : int;
  }

  (* ── Helpers ──────────────────────────────────────────────── *)
  let[@inline] ug a i       = Array.unsafe_get a i
  let[@inline] us a i v     = Array.unsafe_set a i v
  let[@inline] ufg a i      = Array.unsafe_get a i
  let[@inline] ufs a i v    = Array.unsafe_set a i v
  let[@inline] mk_int_arr n = Array.create ~len:n 0
  let[@inline] mk_flt_arr n = Array.create ~len:n 0.0

  let create () =
    let orders_next = mk_int_arr max_orders in
    for i = 0 to max_orders - 2 do us orders_next i (i + 1) done;
    us orders_next (max_orders - 1) (-1);
    let tbl_keys = Array.create ~len:tbl_size (-1) in
    let tbl_vals = Array.create ~len:tbl_size (-1) in
    { bids = Int.Map.empty; asks = Int.Map.empty;
      volume_at_price = Int.Map.empty;
      orders = Hashtbl.create (module Int);
      orders_id    = mk_int_arr max_orders;
      orders_price = mk_int_arr max_orders;
      orders_qty   = mk_int_arr max_orders;
      orders_side  = mk_int_arr max_orders;
      orders_next;
      orders_prev  = Array.create ~len:max_orders (-1);
      free_head    = 0;
      tbl_keys; tbl_vals;
      bids_price = mk_int_arr max_levels; bids_qty = mk_int_arr max_levels;
      bids_head  = Array.create ~len:max_levels (-1);
      bids_tail  = Array.create ~len:max_levels (-1);
      bids_count = 0;
      asks_price = mk_int_arr max_levels; asks_qty = mk_int_arr max_levels;
      asks_head  = Array.create ~len:max_levels (-1);
      asks_tail  = Array.create ~len:max_levels (-1);
      asks_count = 0;
      vol_price  = mk_int_arr max_levels; vol_qty = mk_int_arr max_levels;
      vol_count  = 0;
      trades_price = mk_int_arr max_trades;
      trades_qty   = mk_int_arr max_trades;
      trades_side  = mk_int_arr max_trades;
      trades_time  = mk_flt_arr max_trades;
      trades_count = 0; }

  let reset t =
    t.bids <- Int.Map.empty; t.asks <- Int.Map.empty;
    t.volume_at_price <- Int.Map.empty;
    Hashtbl.clear t.orders;
    t.free_head <- 0;
    for i = 0 to max_orders - 2 do us t.orders_next i (i + 1) done;
    us t.orders_next (max_orders - 1) (-1);
    for i = 0 to tbl_size - 1 do
      us t.tbl_keys i (-1); us t.tbl_vals i (-1) done;
    t.bids_count <- 0; t.asks_count <- 0;
    t.vol_count  <- 0; t.trades_count <- 0

  (* ── Slot pool ─────────────────────────────────────────────── *)
  let[@zero_alloc] alloc_slot t =
    let i = t.free_head in
    if i >= 0 then t.free_head <- ug t.orders_next i;
    i

  let[@zero_alloc] free_slot t i =
    us t.orders_next i t.free_head;
    t.free_head <- i

  (* ── Open-addressed hash table ─────────────────────────────── *)
  let[@zero_alloc] tbl_probe keys id =
    let rec go i =
      let k = ug keys i in
      if k = id || k = -1 then i else go ((i + 1) land tbl_mask)
    in go (id land tbl_mask)

  let[@zero_alloc] tbl_put t id slot =
    let i = tbl_probe t.tbl_keys id in
    us t.tbl_keys i id; us t.tbl_vals i slot

  let[@zero_alloc] tbl_del t id =
    let i = tbl_probe t.tbl_keys id in
    if ug t.tbl_keys i = id then begin
      us t.tbl_keys i (-1); us t.tbl_vals i (-1);
      let rec rehash j =
        let k = ug t.tbl_keys j in
        if k <> -1 then begin
          let v = ug t.tbl_vals j in
          us t.tbl_keys j (-1); us t.tbl_vals j (-1);
          let ni = tbl_probe t.tbl_keys k in
          us t.tbl_keys ni k; us t.tbl_vals ni v;
          rehash ((j + 1) land tbl_mask)
        end
      in rehash ((i + 1) land tbl_mask)
    end

  (* ── Binary search on sorted level array ───────────────────── *)
  (* Returns >= 0 if found, negative insertion point otherwise.  *)
  (* Zero allocations: pure integer arithmetic.                   *)
  let[@zero_alloc] bsearch arr count price asc =
    let lo = ref 0 and hi = ref (count - 1) and res = ref (-(count + 1)) in
    while !lo <= !hi do
      let mid = (!lo + !hi) asr 1 in
      let p   = ug arr mid in
      if p = price then begin res := mid; lo := !hi + 1 end
      else if (if asc then p < price else p > price)
           then lo := mid + 1
           else begin res := -(mid + 1); hi := mid - 1 end
    done;
    !res

  (* ── Level array insert / remove (in-place shift) ─────────── *)
  let[@zero_alloc] level_insert pa qa ha ta count idx price slot qty =
    let n = count - 1 in
    let rec shift i =
      if i >= idx then begin
        us pa (i+1) (ug pa i); us qa (i+1) (ug qa i);
        us ha (i+1) (ug ha i); us ta (i+1) (ug ta i);
        shift (i - 1)
      end
    in
    shift n;
    us pa idx price; us qa idx qty; us ha idx slot; us ta idx slot

  let[@zero_alloc] level_remove pa qa ha ta count idx =
    let rec shift i =
      if i < count - 1 then begin
        us pa i (ug pa (i+1)); us qa i (ug qa (i+1));
        us ha i (ug ha (i+1)); us ta i (ug ta (i+1));
        shift (i + 1)
      end
    in
    shift idx

  (* ── Volume tracker (cold-ish, but still zero-alloc) ───────── *)
  let[@zero_alloc] record_vol t price qty =
    let idx = bsearch t.vol_price t.vol_count price true in
    if idx >= 0
    then us t.vol_qty idx (ug t.vol_qty idx + qty)
    else begin
      let ins = -(idx + 1) in
      let n   = t.vol_count - 1 in
      let rec shift i =
        if i >= ins then begin
          us t.vol_price (i+1) (ug t.vol_price i);
          us t.vol_qty   (i+1) (ug t.vol_qty   i);
          shift (i - 1) end
      in shift n;
      us t.vol_price ins price; us t.vol_qty ins qty;
      t.vol_count <- t.vol_count + 1
    end

  (* ── Core matching loop ────────────────────────────────────────
     All arguments passed explicitly — no closure capture, no alloc.
     `ts` is kept as OxCaml's unboxed `float#` for the entire
     recursive descent, so the timestamp never gets reboxed on each
     match step; it's only converted back to a boxed `float` once,
     at the point it's written into the (boxed) trades_time array.
     OxCaml's [@zero_alloc] checker verifies the whole function
     allocates nothing.                                            *)
  let[@zero_alloc] rec match_loop t side price (ts : float#) remaining =
    if remaining <= 0 then 0
    else begin
      let opp_count = if side = 1 then t.asks_count else t.bids_count in
      if opp_count = 0 then remaining
      else begin
        let opp_pa  = if side = 1 then t.asks_price else t.bids_price in
        let opp_qa  = if side = 1 then t.asks_qty   else t.bids_qty   in
        let opp_ha  = if side = 1 then t.asks_head  else t.bids_head  in
        let opp_ta  = if side = 1 then t.asks_tail  else t.bids_tail  in
        let opp_px  = ug opp_pa 0 in
        let can     = if side = 1 then price >= opp_px else price <= opp_px in
        if not can then remaining
        else begin
          let slot    = ug opp_ha 0 in
          let opp_qty = ug t.orders_qty slot in
          let mq      = if remaining < opp_qty then remaining else opp_qty in

          (* record trade into pre-allocated ring buffer *)
          let ti = t.trades_count in
          if ti < max_trades then begin
            us t.trades_price ti opp_px;
            us t.trades_qty   ti mq;
            us t.trades_side  ti side;
            ufs t.trades_time ti (Float_u.to_float ts);
            t.trades_count <- ti + 1
          end;

          record_vol t opp_px mq;

          if opp_qty = mq then begin
            (* fully matched: unlink level head *)
            let nxt = ug t.orders_next slot in
            us opp_ha 0 nxt;
            if nxt = -1 then begin
              level_remove opp_pa opp_qa opp_ha opp_ta opp_count 0;
              if side = 1 then t.asks_count <- t.asks_count - 1
              else             t.bids_count <- t.bids_count - 1
            end else begin
              us t.orders_prev nxt (-1);
              us opp_qa 0 (ug opp_qa 0 - mq)
            end;
            tbl_del t (ug t.orders_id slot);
            free_slot t slot
          end else begin
            us t.orders_qty slot (opp_qty - mq);
            us opp_qa 0 (ug opp_qa 0 - mq)
          end;
          match_loop t side price ts (remaining - mq)
        end
      end
    end

  (* ── add — the hot-path entry point ───────────────────────────
     Returns count of new trades written to the ring buffer.
     OxCaml: [@zero_alloc] is a *static* compile-time guarantee here;
     the compiler will reject this function if it finds any allocation.  *)
  let[@zero_alloc] add t (msg : Message.t) =
    let side  = msg.side  in
    let price = msg.price in
    let size  = msg.size  in
    let ts    = msg.time  in  (* already float#, no conversion needed *)
    let t0    = t.trades_count in
    let left  = match_loop t side price ts size in
    if left > 0 then begin
      let slot = alloc_slot t in
      if slot >= 0 then begin
        us t.orders_id    slot msg.id;
        us t.orders_price slot price;
        us t.orders_qty   slot left;
        us t.orders_side  slot side;
        us t.orders_next  slot (-1);
        us t.orders_prev  slot (-1);
        tbl_put t msg.id slot;
        if side = 1 then begin
          let idx = bsearch t.bids_price t.bids_count price false in
          if idx >= 0 then begin
            let tail = ug t.bids_tail idx in
            us t.orders_next tail slot;
            us t.orders_prev slot  tail;
            us t.bids_tail   idx   slot;
            us t.bids_qty    idx  (ug t.bids_qty idx + left)
          end else begin
            let ins = -(idx + 1) in
            level_insert t.bids_price t.bids_qty t.bids_head t.bids_tail
                         t.bids_count ins price slot left;
            t.bids_count <- t.bids_count + 1
          end
        end else begin
          let idx = bsearch t.asks_price t.asks_count price true in
          if idx >= 0 then begin
            let tail = ug t.asks_tail idx in
            us t.orders_next tail slot;
            us t.orders_prev slot  tail;
            us t.asks_tail   idx   slot;
            us t.asks_qty    idx  (ug t.asks_qty idx + left)
          end else begin
            let ins = -(idx + 1) in
            level_insert t.asks_price t.asks_qty t.asks_head t.asks_tail
                         t.asks_count ins price slot left;
            t.asks_count <- t.asks_count + 1
          end
        end
      end
    end;
    t.trades_count - t0

  (* ── remove — also zero-alloc ──────────────────────────────── *)
  let[@zero_alloc] remove t id =
    let ti = tbl_probe t.tbl_keys id in
    let slot = ug t.tbl_vals ti in
    if slot >= 0 then begin
      let price = ug t.orders_price slot in
      let qty   = ug t.orders_qty   slot in
      let side  = ug t.orders_side  slot in
      let pa    = if side = 1 then t.bids_price else t.asks_price in
      let qa    = if side = 1 then t.bids_qty   else t.asks_qty   in
      let ha    = if side = 1 then t.bids_head  else t.asks_head  in
      let ta    = if side = 1 then t.bids_tail  else t.asks_tail  in
      let cnt   = if side = 1 then t.bids_count else t.asks_count in
      let idx   = bsearch pa cnt price (side <> 1) in
      if idx >= 0 then begin
        let prev = ug t.orders_prev slot in
        let next = ug t.orders_next slot in
        (if prev >= 0 then us t.orders_next prev next
         else us ha idx next);
        (if next >= 0 then us t.orders_prev next prev
         else us ta idx prev);
        let nq = ug qa idx - qty in
        if nq <= 0 || (next < 0 && prev < 0) then begin
          level_remove pa qa ha ta cnt idx;
          if side = 1 then t.bids_count <- t.bids_count - 1
          else             t.asks_count <- t.asks_count - 1
        end else us qa idx nq
      end;
      tbl_del t id;
      free_slot t slot
    end

  (* ── Cold-path helpers: sync maps for UI ──────────────────── *)
  let sync_maps t =
    let bids = ref Int.Map.empty in
    for i = 0 to t.bids_count - 1 do
      bids := Map.set !bids ~key:(ug t.bids_price i) ~data:(ug t.bids_qty i)
    done;
    t.bids <- !bids;
    let asks = ref Int.Map.empty in
    for i = 0 to t.asks_count - 1 do
      asks := Map.set !asks ~key:(ug t.asks_price i) ~data:(ug t.asks_qty i)
    done;
    t.asks <- !asks;
    let vol = ref Int.Map.empty in
    for i = 0 to t.vol_count - 1 do
      vol := Map.set !vol ~key:(ug t.vol_price i) ~data:(ug t.vol_qty i)
    done;
    t.volume_at_price <- !vol;
    Hashtbl.clear t.orders;
    for i = 0 to tbl_size - 1 do
      let k = ug t.tbl_keys i in
      if k >= 0 then begin
        let s  = ug t.tbl_vals i in
        let sd = if ug t.orders_side s = 1 then `Buy else `Sell in
        Hashtbl.set t.orders ~key:k
          ~data:{ Order.id = k; price = ug t.orders_price s;
                  qty = ug t.orders_qty s; side = sd }
      end
    done

  let pop_new_trades t =
    let acc = ref [] in
    for i = t.trades_count - 1 downto 0 do
      acc := { Trade.time  = ufg t.trades_time  i;
               price = ug  t.trades_price i;
               qty   = ug  t.trades_qty   i;
               side  = (if ug t.trades_side i = 1 then `Buy else `Sell) }
             :: !acc
    done;
    t.trades_count <- 0;
    !acc

  let add_legacy t msg =
    let _n = add t msg in
    pop_new_trades t

  (* ── Query helpers (cold path) ─────────────────────────────── *)
  let get_spread t =
    if t.bids_count > 0 && t.asks_count > 0
    then Some (ug t.asks_price 0 - ug t.bids_price 0)
    else None

  let get_mid_price t =
    if t.bids_count > 0 && t.asks_count > 0
    then Some ((ug t.asks_price 0 + ug t.bids_price 0) / 2)
    else None

  let[@zero_alloc] get_total_bid_volume t =
    let v = ref 0 in
    for i = 0 to t.bids_count - 1 do v := !v + ug t.bids_qty i done; !v

  let[@zero_alloc] get_total_ask_volume t =
    let v = ref 0 in
    for i = 0 to t.asks_count - 1 do v := !v + ug t.asks_qty i done; !v

  let get_best_bid_ask t =
    let bid = if t.bids_count > 0 then Some (ug t.bids_price 0, ug t.bids_qty 0) else None in
    let ask = if t.asks_count > 0 then Some (ug t.asks_price 0, ug t.asks_qty 0) else None in
    (bid, ask)

  let[@zero_alloc] get_imbalance_ratio t =
    let bv = get_total_bid_volume t in
    let av = get_total_ask_volume t in
    if av = 0 then 0.0 else Float.of_int bv /. Float.of_int av

  let[@zero_alloc] get_vwap t =
    let tv = ref 0 and ws = ref 0 in
    for i = 0 to t.vol_count - 1 do
      let p = ug t.vol_price i and q = ug t.vol_qty i in
      tv := !tv + q; ws := !ws + p * q
    done;
    if !tv = 0 then 0 else !ws / !tv

  let[@zero_alloc] validate t =
    not (t.bids_count > 0 && t.asks_count > 0
         && ug t.bids_price 0 >= ug t.asks_price 0)

  let get_depth_snapshot t ~num_levels =
    let take pa qa cnt n =
      let lim = min n cnt in
      let acc = ref [] in
      for i = lim - 1 downto 0 do
        acc := (ug pa i, ug qa i) :: !acc
      done; !acc
    in
    (take t.asks_price t.asks_qty t.asks_count num_levels,
     take t.bids_price t.bids_qty t.bids_count num_levels)
end
