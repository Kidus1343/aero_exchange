open Core
open Types

module Order_book = struct
  type t = {
    orders : Order.t Hashtbl.M(Int).t;
    mutable bids : int Int.Map.t;
    mutable asks : int Int.Map.t;
    (* Track total volume executed at each price level *)
    mutable volume_at_price : int Int.Map.t; 
  }

  let create () = {
    orders = Hashtbl.create (module Int);
    bids = Int.Map.empty;
    asks = Int.Map.empty;
    volume_at_price = Int.Map.empty;
  }
  (* ADD THIS NEW FUNCTION RIGHT HERE *)
  let reset t =
    Hashtbl.clear t.orders;
    t.bids <- Int.Map.empty;
    t.asks <- Int.Map.empty;
    t.volume_at_price <- Int.Map.empty

  let update_price_map map price delta =
    let current_qty = Map.find map price |> Option.value ~default:0 in
    let new_qty = current_qty + delta in
    if new_qty <= 0 then Map.remove map price
    else Map.set map ~key:price ~data:new_qty

  let add t (msg : Message.t) =
    let side = if msg.side = 1 then `Buy else `Sell in
    let trades = ref [] in

    let rec match_order remaining_qty =
      if remaining_qty <= 0 then 0
      else
        let opposite_map = match side with `Buy -> t.asks | `Sell -> t.bids in
        let best_opp = match side with 
          | `Buy -> Map.min_elt opposite_map 
          | `Sell -> Map.max_elt opposite_map 
        in
        match best_opp with
        | Some (opp_price, opp_qty) when (match side with 
            | `Buy -> msg.price >= opp_price | `Sell -> msg.price <= opp_price) ->
            
            let match_qty = Int.min remaining_qty opp_qty in
            
            (* Optional: Uncomment for debugging, but leave commented for HFT benchmarking *)
            (* Printf.printf "TRADE: Price %d | Qty %d\n" opp_price match_qty; *)
            
            (* Update the Volume-at-Price tracker *)
            t.volume_at_price <- Map.update t.volume_at_price opp_price ~f:(function
              | None -> match_qty
              | Some v -> v + match_qty);

            (* Record the trade *)
            let trade = { Trade.time = msg.time; price = opp_price; qty = match_qty; side } in
            trades := trade :: !trades;

            (* Reduce qty in the active price map *)
            (match side with
            | `Buy -> t.asks <- update_price_map t.asks opp_price (-match_qty)
            | `Sell -> t.bids <- update_price_map t.bids opp_price (-match_qty));
            
            match_order (remaining_qty - match_qty)
        | _ -> remaining_qty 
    in

    let leftover_qty = match_order msg.size in
    
    (* Add whatever is left to the book *)
    if leftover_qty > 0 then begin
      let order = { Order.id = msg.id; price = msg.price; qty = leftover_qty; side } in
      Hashtbl.set t.orders ~key:msg.id ~data:order;
      match side with
      | `Buy  -> t.bids <- update_price_map t.bids msg.price leftover_qty
      | `Sell -> t.asks <- update_price_map t.asks msg.price leftover_qty
    end
    ;
    List.rev !trades

  let remove t id =
    match Hashtbl.find t.orders id with
    | None -> ()
    | Some order ->
      Hashtbl.remove t.orders id;
      match order.side with
      | `Buy  -> t.bids <- update_price_map t.bids order.price (-order.qty)
      | `Sell -> t.asks <- update_price_map t.asks order.price (-order.qty)

  let get_spread t =
    match Map.max_elt t.bids, Map.min_elt t.asks with
    | Some (b, _), Some (a, _) -> Some (a - b)
    | _ -> None

  let get_mid_price t =
    match Map.max_elt t.bids, Map.min_elt t.asks with
    | Some (b, _), Some (a, _) -> Some ((a + b) / 2)
    | _ -> None

  let get_total_bid_volume t =
    Map.fold t.bids ~init:0 ~f:(fun ~key:_ ~data acc -> acc + data)

  let get_total_ask_volume t =
    Map.fold t.asks ~init:0 ~f:(fun ~key:_ ~data acc -> acc + data)

  let get_best_bid_ask t =
    (Map.max_elt t.bids, Map.min_elt t.asks)

  let get_imbalance_ratio t =
    let bid_vol = get_total_bid_volume t in
    let ask_vol = get_total_ask_volume t in
    if ask_vol = 0 then 0.0
    else Float.of_int bid_vol /. Float.of_int ask_vol

  let get_vwap t =
    (* Volume-weighted average price *)
    let total_volume = Map.fold t.volume_at_price ~init:0 ~f:(fun ~key:_ ~data acc -> acc + data) in
    if total_volume = 0 then 0
    else
      let weighted_sum = Map.fold t.volume_at_price ~init:0 
        ~f:(fun ~key:price ~data:volume acc -> acc + (price * volume)) in
      weighted_sum / total_volume

  let validate t =
    (* Ensure no order appears in both bids and asks at same price *)
    let bid_prices = Map.key_set t.bids in
    let ask_prices = Map.key_set t.asks in
    Set.is_empty (Set.inter bid_prices ask_prices)

  let get_depth_snapshot t ~num_levels =
  let asks_al =
    List.take (Map.to_alist t.asks) num_levels
  in

  let bids_al =
    List.take (Map.to_alist t.bids) num_levels
    |> List.rev
  in

  (asks_al, bids_al)

end
