open Core
open Types

module Order_book = struct
  (* ── Capacities (init-time only) ─────────────────────────── *)
  let max_orders      = 131072
  let max_levels      = 4096
  let max_trades      = 1024
  let tbl_size        = 262144
  let tbl_mask        = tbl_size - 1
  let price_tbl_size  = 16384
  let price_tbl_mask  = price_tbl_size - 1

  type t = {
    (* legacy maps kept for Bonsai UI — never touched on hot path *)
    mutable bids            : int Int.Map.t;
    mutable asks            : int Int.Map.t;
    mutable volume_at_price : int Int.Map.t;
    orders                  : Order.t Hashtbl.M(Int).t;

    (* ── flat order pool ── *)
    orders_id        : int array;
    orders_price     : int array;
    orders_qty       : int array;
    orders_side      : int array;
    orders_level_idx : int array;
    orders_next      : int array;   (* doubly linked list inside level / free-list *)
    orders_prev      : int array;
    mutable free_head : int;

    (* ── open-addressed hash table: order_id -> slot index ── *)
    tbl_keys : int array;
    tbl_vals : int array;

    (* ── open-addressed hash tables: price -> level_idx (split by side) ── *)
    price_tbl_keys_bid : int array;
    price_tbl_vals_bid : int array;
    price_tbl_keys_ask : int array;
    price_tbl_vals_ask : int array;

    (* ── level pool ── *)
    level_price      : int array;
    level_qty        : int array;
    level_head       : int array;
    level_tail       : int array;
    level_prev       : int array;   (* doubly-linked active price levels *)
    level_next       : int array;
    level_side       : int array;
    mutable level_free_head : int;

    mutable best_bid_head : int;
    mutable best_ask_head : int;
    mutable bids_count    : int;
    mutable asks_count    : int;

    (* ── volume-at-price tracker ── *)
    vol_price : int array;
    vol_qty   : int array;
    mutable vol_count : int;

    (* ── pre-allocated trade ring buffer ── *)
    trades_price : int array;
    trades_qty   : int array;
    trades_side  : int array;
    trades_time  : float array;
    mutable trades_count : int;
  }

  (* ── Helpers ── *)
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

    let level_next = mk_int_arr max_levels in
    for i = 0 to max_levels - 2 do us level_next i (i + 1) done;
    us level_next (max_levels - 1) (-1);

    let tbl_keys = Array.create ~len:tbl_size (-1) in
    let tbl_vals = Array.create ~len:tbl_size (-1) in

    let price_tbl_keys_bid = Array.create ~len:price_tbl_size (-1) in
    let price_tbl_vals_bid = Array.create ~len:price_tbl_size (-1) in
    let price_tbl_keys_ask = Array.create ~len:price_tbl_size (-1) in
    let price_tbl_vals_ask = Array.create ~len:price_tbl_size (-1) in

    { bids = Int.Map.empty; asks = Int.Map.empty;
      volume_at_price = Int.Map.empty;
      orders = Hashtbl.create (module Int);
      orders_id        = mk_int_arr max_orders;
      orders_price     = mk_int_arr max_orders;
      orders_qty       = mk_int_arr max_orders;
      orders_side      = mk_int_arr max_orders;
      orders_level_idx = Array.create ~len:max_orders (-1);
      orders_next;
      orders_prev      = Array.create ~len:max_orders (-1);
      free_head        = 0;
      tbl_keys; tbl_vals;
      price_tbl_keys_bid; price_tbl_vals_bid;
      price_tbl_keys_ask; price_tbl_vals_ask;
      level_price      = mk_int_arr max_levels;
      level_qty        = mk_int_arr max_levels;
      level_head       = Array.create ~len:max_levels (-1);
      level_tail       = Array.create ~len:max_levels (-1);
      level_prev       = Array.create ~len:max_levels (-1);
      level_next;
      level_side       = mk_int_arr max_levels;
      level_free_head  = 0;
      best_bid_head    = -1;
      best_ask_head    = -1;
      bids_count       = 0;
      asks_count       = 0;
      vol_price        = mk_int_arr max_levels;
      vol_qty          = mk_int_arr max_levels;
      vol_count        = 0;
      trades_price     = mk_int_arr max_trades;
      trades_qty       = mk_int_arr max_trades;
      trades_side      = mk_int_arr max_trades;
      trades_time      = mk_flt_arr max_trades;
      trades_count     = 0; }

  let reset t =
    t.bids <- Int.Map.empty; t.asks <- Int.Map.empty;
    t.volume_at_price <- Int.Map.empty;
    Hashtbl.clear t.orders;
    t.free_head <- 0;
    for i = 0 to max_orders - 2 do us t.orders_next i (i + 1) done;
    us t.orders_next (max_orders - 1) (-1);

    t.level_free_head <- 0;
    for i = 0 to max_levels - 2 do us t.level_next i (i + 1) done;
    us t.level_next (max_levels - 1) (-1);

    for i = 0 to tbl_size - 1 do
      us t.tbl_keys i (-1); us t.tbl_vals i (-1)
    done;

    for i = 0 to price_tbl_size - 1 do
      us t.price_tbl_keys_bid i (-1); us t.price_tbl_vals_bid i (-1);
      us t.price_tbl_keys_ask i (-1); us t.price_tbl_vals_ask i (-1)
    done;

    t.best_bid_head <- -1;
    t.best_ask_head <- -1;
    t.bids_count    <- 0;
    t.asks_count    <- 0;
    t.vol_count     <- 0;
    t.trades_count  <- 0

  (* ── Slot pools ────────────────────────────────────────────── *)
  let[@zero_alloc] alloc_slot t =
    let i = t.free_head in
    if i >= 0 then t.free_head <- ug t.orders_next i;
    i

  let[@zero_alloc] free_slot t i =
    us t.orders_next i t.free_head;
    t.free_head <- i

  let[@zero_alloc] alloc_level t =
    let i = t.level_free_head in
    if i >= 0 then t.level_free_head <- ug t.level_next i;
    i

  let[@zero_alloc] free_level t i =
    us t.level_next i t.level_free_head;
    t.level_free_head <- i

  (* ── Hash Tables ───────────────────────────────────────────── *)
  (* Order table: order_id -> slot *)
  let[@zero_alloc] rec tbl_probe_loop keys id i =
    let k = ug keys i in
    if k = id || k = -1 then i
    else tbl_probe_loop keys id ((i + 1) land tbl_mask)

  let[@zero_alloc] tbl_probe keys id =
    tbl_probe_loop keys id ((id * 26544357) land tbl_mask)

  let[@zero_alloc] tbl_put t id slot =
    let i = tbl_probe t.tbl_keys id in
    us t.tbl_keys i id;
    us t.tbl_vals i slot

  let[@zero_alloc] rec tbl_del_rehash keys vals j =
    let k = ug keys j in
    if k <> -1 then begin
      let v = ug vals j in
      us keys j (-1);
      us vals j (-1);
      let ni = tbl_probe keys k in
      us keys ni k;
      us vals ni v;
      tbl_del_rehash keys vals ((j + 1) land tbl_mask)
    end

  let[@zero_alloc] tbl_del t id =
    let i = tbl_probe t.tbl_keys id in
    if ug t.tbl_keys i = id then begin
      us t.tbl_keys i (-1);
      us t.tbl_vals i (-1);
      tbl_del_rehash t.tbl_keys t.tbl_vals ((i + 1) land tbl_mask)
    end

  (* Price table: (side, price) -> level_idx *)
  let[@zero_alloc] rec price_tbl_probe_loop keys price i =
    let k = ug keys i in
    if k = price || k = -1 then i
    else price_tbl_probe_loop keys price ((price * 26544357) land price_tbl_mask)

  let[@zero_alloc] price_tbl_probe keys price =
    price_tbl_probe_loop keys price ((price * 26544357) land price_tbl_mask)

  let[@zero_alloc] price_tbl_find t side price =
    let keys = if side = 1 then t.price_tbl_keys_bid else t.price_tbl_keys_ask in
    let vals = if side = 1 then t.price_tbl_vals_bid else t.price_tbl_vals_ask in
    let i = price_tbl_probe keys price in
    if ug keys i = price then ug vals i else -1

  let[@zero_alloc] price_tbl_put t side price level_idx =
    let keys = if side = 1 then t.price_tbl_keys_bid else t.price_tbl_keys_ask in
    let vals = if side = 1 then t.price_tbl_vals_bid else t.price_tbl_vals_ask in
    let i = price_tbl_probe keys price in
    us keys i price;
    us vals i level_idx

  let[@zero_alloc] rec price_tbl_del_rehash keys vals j =
    let k = ug keys j in
    if k <> -1 then begin
      let v = ug vals j in
      us keys j (-1);
      us vals j (-1);
      let ni = price_tbl_probe keys k in
      us keys ni k;
      us vals ni v;
      price_tbl_del_rehash keys vals ((j + 1) land price_tbl_mask)
    end

  let[@zero_alloc] price_tbl_del t side price =
    let keys = if side = 1 then t.price_tbl_keys_bid else t.price_tbl_keys_ask in
    let vals = if side = 1 then t.price_tbl_vals_bid else t.price_tbl_vals_ask in
    let i = price_tbl_probe keys price in
    if ug keys i = price then begin
      us keys i (-1);
      us vals i (-1);
      price_tbl_del_rehash keys vals ((i + 1) land price_tbl_mask)
    end

  (* ── Active Price Level Doubly Linked List Maintenance ─────── *)
  let[@zero_alloc] rec find_bid_pos level_next level_price curr price =
    let nxt = ug level_next curr in
    if nxt = -1 || price > ug level_price nxt then curr
    else find_bid_pos level_next level_price nxt price

  let[@zero_alloc] rec find_ask_pos level_next level_price curr price =
    let nxt = ug level_next curr in
    if nxt = -1 || price < ug level_price nxt then curr
    else find_ask_pos level_next level_price nxt price

  let[@zero_alloc] link_level t side level_idx price =
    us t.level_price level_idx price;
    us t.level_side  level_idx side;
    if side = 1 then begin
      (* Bids: highest price first (best_bid_head) *)
      let head = t.best_bid_head in
      if head = -1 then begin
        t.best_bid_head <- level_idx;
        us t.level_prev level_idx (-1);
        us t.level_next level_idx (-1);
        t.bids_count <- 1
      end else if price > ug t.level_price head then begin
        (* New best bid *)
        us t.level_prev head level_idx;
        us t.level_next level_idx head;
        us t.level_prev level_idx (-1);
        t.best_bid_head <- level_idx;
        t.bids_count <- t.bids_count + 1
      end else begin
        let pos = find_bid_pos t.level_next t.level_price head price in
        let nxt = ug t.level_next pos in
        us t.level_next pos level_idx;
        us t.level_prev level_idx pos;
        us t.level_next level_idx nxt;
        if nxt <> -1 then us t.level_prev nxt level_idx;
        t.bids_count <- t.bids_count + 1
      end
    end else begin
      (* Asks: lowest price first (best_ask_head) *)
      let head = t.best_ask_head in
      if head = -1 then begin
        t.best_ask_head <- level_idx;
        us t.level_prev level_idx (-1);
        us t.level_next level_idx (-1);
        t.asks_count <- 1
      end else if price < ug t.level_price head then begin
        (* New best ask *)
        us t.level_prev head level_idx;
        us t.level_next level_idx head;
        us t.level_prev level_idx (-1);
        t.best_ask_head <- level_idx;
        t.asks_count <- t.asks_count + 1
      end else begin
        let pos = find_ask_pos t.level_next t.level_price head price in
        let nxt = ug t.level_next pos in
        us t.level_next pos level_idx;
        us t.level_prev level_idx pos;
        us t.level_next level_idx nxt;
        if nxt <> -1 then us t.level_prev nxt level_idx;
        t.asks_count <- t.asks_count + 1
      end
    end

  let[@zero_alloc] unlink_level t side level_idx =
    let prev = ug t.level_prev level_idx in
    let next = ug t.level_next level_idx in
    if prev <> -1 then us t.level_next prev next
    else if side = 1 then t.best_bid_head <- next
    else                  t.best_ask_head <- next;
    if next <> -1 then us t.level_prev next prev;
    if side = 1 then t.bids_count <- t.bids_count - 1
    else             t.asks_count <- t.asks_count - 1;
    price_tbl_del t side (ug t.level_price level_idx);
    free_level t level_idx

  (* ── Order Queue Link / Unlink ─────────────────────────────── *)
  let[@zero_alloc] link_order_to_level t level_idx order_slot qty =
    us t.orders_level_idx order_slot level_idx;
    let tail = ug t.level_tail level_idx in
    if tail = -1 then begin
      us t.level_head level_idx order_slot;
      us t.level_tail level_idx order_slot;
      us t.orders_prev order_slot (-1);
      us t.orders_next order_slot (-1)
    end else begin
      us t.orders_next tail order_slot;
      us t.orders_prev order_slot tail;
      us t.orders_next order_slot (-1);
      us t.level_tail  level_idx order_slot
    end;
    us t.level_qty level_idx (ug t.level_qty level_idx + qty)

  let[@zero_alloc] unlink_order_from_level t level_idx order_slot qty =
    let prev = ug t.orders_prev order_slot in
    let next = ug t.orders_next order_slot in
    if prev <> -1 then us t.orders_next prev next
    else us t.level_head level_idx next;
    if next <> -1 then us t.orders_prev next prev
    else us t.level_tail level_idx prev;
    let new_qty = ug t.level_qty level_idx - qty in
    us t.level_qty level_idx new_qty;
    if new_qty <= 0 || ug t.level_head level_idx = -1 then begin
      unlink_level t (ug t.orders_side order_slot) level_idx
    end

  (* ── Volume tracker ────────────────────────────────────────── *)
  let[@zero_alloc] rec find_vol vol_price count price i =
    if i >= count then -1
    else if ug vol_price i = price then i
    else find_vol vol_price count price (i + 1)

  let[@zero_alloc] record_vol t price qty =
    let count = t.vol_count in
    let idx = find_vol t.vol_price count price 0 in
    if idx >= 0 then
      us t.vol_qty idx (ug t.vol_qty idx + qty)
    else if count < max_levels then begin
      us t.vol_price count price;
      us t.vol_qty   count qty;
      t.vol_count <- count + 1
    end

  (* ── Core matching loop ────────────────────────────────────── *)
  let[@zero_alloc] rec match_loop t (msg : Message.t) remaining =
    if remaining <= 0 then 0
    else begin
      let side = msg.side in
      let price = msg.price in
      let opp_head = if side = 1 then t.best_ask_head else t.best_bid_head in
      if opp_head = -1 then remaining
      else begin
        let opp_px = ug t.level_price opp_head in
        let can    = if side = 1 then price >= opp_px else price <= opp_px in
        if not can then remaining
        else begin
          let slot    = ug t.level_head opp_head in
          let opp_qty = ug t.orders_qty slot in
          let mq      = if remaining < opp_qty then remaining else opp_qty in

          (* record trade into pre-allocated ring buffer *)
          let ti = t.trades_count in
          if ti < max_trades then begin
            us t.trades_price ti opp_px;
            us t.trades_qty   ti mq;
            us t.trades_side  ti side;
            ufs t.trades_time ti msg.time;
            t.trades_count <- ti + 1
          end;

          record_vol t opp_px mq;

          if opp_qty = mq then begin
            unlink_order_from_level t opp_head slot mq;
            tbl_del t (ug t.orders_id slot);
            free_slot t slot
          end else begin
            us t.orders_qty slot (opp_qty - mq);
            us t.level_qty  opp_head (ug t.level_qty opp_head - mq)
          end;
          match_loop t msg (remaining - mq)
        end
      end
    end

  (* ── add — the hot-path entry point ─────────────────────────── *)
  let[@zero_alloc] add t (msg : Message.t) =
    let t0    = t.trades_count in
    let left  = match_loop t msg msg.size in
    if left > 0 then begin
      let slot = alloc_slot t in
      if slot >= 0 then begin
        let side  = msg.side in
        let price = msg.price in
        us t.orders_id    slot msg.id;
        us t.orders_price slot price;
        us t.orders_qty   slot left;
        us t.orders_side  slot side;
        tbl_put t msg.id slot;
        let level_idx = price_tbl_find t side price in
        if level_idx >= 0 then begin
          link_order_to_level t level_idx slot left
        end else begin
          let new_level = alloc_level t in
          if new_level >= 0 then begin
            us t.level_head new_level (-1);
            us t.level_tail new_level (-1);
            us t.level_qty  new_level 0;
            link_level t side new_level price;
            price_tbl_put t side price new_level;
            link_order_to_level t new_level slot left
          end
        end
      end
    end;
    t.trades_count - t0

  (* ── remove — also O(1) zero-alloc ─────────────────────────── *)
  let[@zero_alloc] remove t id =
    let ti = tbl_probe t.tbl_keys id in
    let slot = ug t.tbl_vals ti in
    if slot >= 0 then begin
      let level_idx = ug t.orders_level_idx slot in
      let qty       = ug t.orders_qty slot in
      unlink_order_from_level t level_idx slot qty;
      tbl_del t id;
      free_slot t slot
    end

  (* ── Cold-path helpers: sync maps for UI ──────────────────── *)
  let sync_maps t =
    let bids = ref Int.Map.empty in
    let rec go_bids curr =
      if curr >= 0 then begin
        bids := Map.set !bids ~key:(ug t.level_price curr) ~data:(ug t.level_qty curr);
        go_bids (ug t.level_next curr)
      end
    in go_bids t.best_bid_head;
    t.bids <- !bids;
    let asks = ref Int.Map.empty in
    let rec go_asks curr =
      if curr >= 0 then begin
        asks := Map.set !asks ~key:(ug t.level_price curr) ~data:(ug t.level_qty curr);
        go_asks (ug t.level_next curr)
      end
    in go_asks t.best_ask_head;
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

  (* ── Zero-alloc unboxed query functions (sentinel -1 when absent) ── *)
  let[@zero_alloc] get_spread_unboxed t =
    if t.best_bid_head >= 0 && t.best_ask_head >= 0
    then ug t.level_price t.best_ask_head - ug t.level_price t.best_bid_head
    else -1

  let[@zero_alloc] get_mid_price_unboxed t =
    if t.best_bid_head >= 0 && t.best_ask_head >= 0
    then (ug t.level_price t.best_ask_head + ug t.level_price t.best_bid_head) / 2
    else -1

  let[@zero_alloc] get_best_bid_price t =
    if t.best_bid_head >= 0 then ug t.level_price t.best_bid_head else -1

  let[@zero_alloc] get_best_bid_qty t =
    if t.best_bid_head >= 0 then ug t.level_qty t.best_bid_head else 0

  let[@zero_alloc] get_best_ask_price t =
    if t.best_ask_head >= 0 then ug t.level_price t.best_ask_head else -1

  let[@zero_alloc] get_best_ask_qty t =
    if t.best_ask_head >= 0 then ug t.level_qty t.best_ask_head else 0

  (* ── Cold-path query helpers with Option / Tuple (UI / Bonsai) ── *)
  let get_spread t =
    let s = get_spread_unboxed t in
    if s >= 0 then Some s else None

  let get_mid_price t =
    let m = get_mid_price_unboxed t in
    if m >= 0 then Some m else None

  let[@zero_alloc] get_total_bid_volume t =
    let v = ref 0 in
    let rec go curr =
      if curr >= 0 then begin
        v := !v + ug t.level_qty curr;
        go (ug t.level_next curr)
      end
    in go t.best_bid_head; !v

  let[@zero_alloc] get_total_ask_volume t =
    let v = ref 0 in
    let rec go curr =
      if curr >= 0 then begin
        v := !v + ug t.level_qty curr;
        go (ug t.level_next curr)
      end
    in go t.best_ask_head; !v

  let get_best_bid_ask t =
    let bid_px = get_best_bid_price t in
    let bid = if bid_px >= 0 then Some (bid_px, get_best_bid_qty t) else None in
    let ask_px = get_best_ask_price t in
    let ask = if ask_px >= 0 then Some (ask_px, get_best_ask_qty t) else None in
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
    not (t.best_bid_head >= 0 && t.best_ask_head >= 0
         && ug t.level_price t.best_bid_head >= ug t.level_price t.best_ask_head)

  let get_depth_snapshot t ~num_levels =
    let collect head =
      let rec go curr count acc =
        if curr >= 0 && count < num_levels then
          go (ug t.level_next curr) (count + 1) ((ug t.level_price curr, ug t.level_qty curr) :: acc)
        else List.rev acc
      in go head 0 []
    in
    (collect t.best_ask_head, collect t.best_bid_head)
end
