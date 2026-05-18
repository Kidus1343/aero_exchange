open Core
open Engine
open Types
(* Advanced Order Types *)
module Order_Type = struct
  type t =
    | Market       (* Execute immediately at best available price *)
    | Limit        (* Execute only at specified price or better *)
    | Stop_Loss    (* Execute if price falls below threshold *)
    | Iceberg      (* Partially visible, large hidden order *)
  [@@deriving sexp]
end

(* Position Tracking *)
module Position = struct
  type t = {
    symbol : string;
    quantity : int;
    avg_entry_price : float;
    current_price : float;
    side : [ `Long | `Short ];
    timestamp : float;
  } [@@deriving sexp]

  let create ~symbol ~quantity ~entry_price ~current_price ~side ~timestamp =
    { symbol; quantity; avg_entry_price = entry_price; current_price; side; timestamp }

  let unrealized_pnl t =
    let price_diff = t.current_price -. t.avg_entry_price in
    Float.of_int t.quantity *. price_diff *. (match t.side with `Long -> 1.0 | `Short -> -1.0)

  let mark_price_update t new_price =
    { t with current_price = new_price }

  let update_quantity t new_qty =
    { t with quantity = new_qty }
end

(* Portfolio P&L Tracking *)
module Portfolio = struct
  type t = {
    positions : Position.t list;
    realized_pnl : float;
    cash : float;
    trades_executed : int;
  } [@@deriving sexp]

  let create ~cash =
    { positions = []; realized_pnl = 0.0; cash; trades_executed = 0 }

  let add_position portfolio position =
    { portfolio with positions = position :: portfolio.positions }

  let remove_position portfolio symbol =
    { portfolio with positions = List.filter portfolio.positions 
      ~f:(fun p -> not (String.equal p.symbol symbol)) }

  let update_position portfolio symbol update_fn =
    { portfolio with positions = List.map portfolio.positions 
      ~f:(fun p -> if String.equal p.symbol symbol then update_fn p else p) }

  let total_unrealized_pnl portfolio =
    List.fold portfolio.positions ~init:0.0 
      ~f:(fun acc pos -> acc +. Position.unrealized_pnl pos)

  let total_pnl portfolio =
    portfolio.realized_pnl +. total_unrealized_pnl portfolio

  let update_cash portfolio trade_qty avg_price =
    { portfolio with cash = portfolio.cash -. (Float.of_int trade_qty *. avg_price) }

  let record_trade portfolio =
    { portfolio with trades_executed = portfolio.trades_executed + 1 }
end

(* Advanced Order Management *)
module Advanced_Order = struct
  type t = {
    id : int;
    order_type : Order_Type.t;
    base_order : Order.t;
    threshold : int option; (* For stop-loss *)
    visible_qty : int; (* For iceberg *)
    total_qty : int;    (* For iceberg *)
    status : [ `Active | `Filled | `Cancelled | `Rejected ];
    created_at : float;
  } [@@deriving sexp]

  let create ~id ~order_type ~base_order:(base_order : Order.t) ~threshold ~visible_qty created_at =
    let total_qty = match order_type with
      | Order_Type.Iceberg -> visible_qty * 2 (* Hidden qty = visible qty *)
      | _ -> base_order.qty
    in
    {
      id;
      order_type;
      base_order = base_order;
      threshold;
      visible_qty;
      total_qty;
      status = `Active;
      created_at;
    }

  let should_trigger_stop stop_price ~current_price ~side =
    match side with
    | `Buy -> current_price <= stop_price
    | `Sell -> current_price >= stop_price

  let can_match order current_price =
    match order.status with
    | `Active ->
       (match order.order_type with
         | Order_Type.Stop_Loss ->
          (match order.threshold with
           | Some threshold -> should_trigger_stop threshold ~current_price ~side:order.base_order.side
           | None -> false)
         | Order_Type.Market | Order_Type.Limit | Order_Type.Iceberg -> true)
    | _ -> false

  let fill_order order filled_qty =
    if filled_qty >= order.total_qty then
      { order with status = `Filled }
    else
      order

  let cancel_order order =
    { order with status = `Cancelled }
end

(* CSV Data Export/Import *)
module CSV_Handler = struct
  let export_trades trades filename =
    let lines = List.map trades ~f:(fun (t : Trade.t) ->
      Printf.sprintf "%.2f,%d,%d,%s"
        t.time
        t.price
        t.qty
        (match t.side with `Buy -> "BUY" | `Sell -> "SELL")
    ) in
    let content = String.concat ~sep:"\n" ("time,price,qty,side" :: lines) in
    Out_channel.write_all filename ~data:content

  let export_positions (portfolio : Portfolio.t) filename =
    let lines = List.map portfolio.positions ~f:(fun (p : Position.t) ->
      Printf.sprintf "%s,%d,%.2f,%.2f,%s,%.2f"
        p.symbol
        p.quantity
        p.avg_entry_price
        p.current_price
        (match p.side with `Long -> "LONG" | `Short -> "SHORT")
        (Position.unrealized_pnl p)
    ) in
    let content = String.concat ~sep:"\n" 
      ("symbol,qty,entry_price,current_price,side,unrealized_pnl" :: lines) in
    Out_channel.write_all filename ~data:content

  let export_summary (portfolio : Portfolio.t) filename =
    let content = Printf.sprintf
      "Total P&L: %.2f\nRealized P&L: %.2f\nUnrealized P&L: %.2f\nCash: %.2f\nTrades Executed: %d"
      (Portfolio.total_pnl portfolio)
      portfolio.realized_pnl
      (Portfolio.total_unrealized_pnl portfolio)
      portfolio.cash
      portfolio.trades_executed
    in
    Out_channel.write_all filename ~data:content
end

(* Performance Analytics *)
module Analytics = struct
  let calculate_sharpe_returns portfolio =
    let pnl_history = [Portfolio.total_pnl portfolio] in
    let mean_return = List.fold pnl_history ~init:0.0 ~f:(+.) /. Float.of_int (List.length pnl_history) in
    mean_return

  let win_rate trades =
    let winning = List.filter trades ~f:(fun (t : Trade.t) -> t.qty > 0) in
    Float.of_int (List.length winning) /. Float.of_int (List.length trades)

  let average_trade_size (trades : Trade.t list) =
    if List.is_empty trades then 0.0
    else
      let total = List.fold trades ~init:0 ~f:(fun acc t -> acc + t.qty) in
      Float.of_int total /. Float.of_int (List.length trades)
end
