# Aero-Exchange Advanced Features

## Order Types

### Market Orders
Executed immediately at the best available price in the order book.

```ocaml
let order = Order.create ~price:0 ~qty:100 ~side:`Buy
let adv_order = Advanced_Order.create 
  ~id:1 
  ~order_type:Order_Type.Market 
  ~order 
  ~threshold:None
  ~visible_qty:100
  created_at
```

### Limit Orders
Executed only at the specified price or better.

```ocaml
let order = Order.create ~price:50000 ~qty:100 ~side:`Buy
let adv_order = Advanced_Order.create 
  ~id:2 
  ~order_type:Order_Type.Limit 
  ~order 
  ~threshold:None
  ~visible_qty:100
  created_at
```

### Stop-Loss Orders
Triggered when the market price reaches the specified threshold.

```ocaml
let order = Order.create ~price:49900 ~qty:100 ~side:`Sell
let adv_order = Advanced_Order.create 
  ~id:3 
  ~order_type:Order_Type.Stop_Loss 
  ~order 
  ~threshold:(Some 49950)
  ~visible_qty:100
  created_at
```

### Iceberg Orders
Large orders partially visible, with hidden quantity released as the visible portion fills.

```ocaml
let order = Order.create ~price:50000 ~qty:1000 ~side:`Buy
let adv_order = Advanced_Order.create 
  ~id:4 
  ~order_type:Order_Type.Iceberg 
  ~order 
  ~threshold:None
  ~visible_qty:100  (* Show 100, hide 900 *)
  created_at
```

## Position Tracking

Track open positions in your portfolio with entry prices and unrealized P&L.

```ocaml
(* Create a position *)
let position = Position.create
  ~symbol:"EUR/USD"
  ~quantity:1000000
  ~entry_price:1.0850
  ~current_price:1.0850
  ~side:`Long
  ~timestamp:(Time_float.now () |> Time_float.to_span_since_epoch |> Time_float.Span.to_sec)

(* Calculate unrealized P&L *)
let pnl = Position.unrealized_pnl position
(* Result: 0.0 (no movement yet) *)

(* Update market price *)
let updated_position = Position.mark_price_update position 1.0860
let new_pnl = Position.unrealized_pnl updated_position
(* Result: 10000.0 (positive P&L) *)
```

## Portfolio Management

Maintain a complete portfolio with positions, cash balance, and P&L tracking.

```ocaml
(* Initialize portfolio *)
let portfolio = Portfolio.create ~cash:1000000.0

(* Add position *)
let portfolio = Portfolio.add_position portfolio position

(* Get total P&L *)
let total = Portfolio.total_pnl portfolio
let unrealized = Portfolio.total_unrealized_pnl portfolio
let realized = portfolio.realized_pnl

(* Update cash after trade *)
let portfolio = Portfolio.update_cash portfolio 100 50000.0
```

## CSV Export/Import

Export trading data, positions, and performance summaries.

```ocaml
(* Export executed trades *)
CSV_Handler.export_trades model.trades "trades.csv"
(* Output: time,price,qty,side *)

(* Export open positions *)
CSV_Handler.export_positions portfolio "positions.csv"
(* Output: symbol,qty,entry_price,current_price,side,unrealized_pnl *)

(* Export performance summary *)
CSV_Handler.export_summary portfolio "summary.csv"
(* Output: Total P&L, Realized P&L, Unrealized P&L, Cash, Trades *)
```

## Performance Analytics

Analyze trading performance metrics.

```ocaml
(* Calculate Sharpe ratio-like returns *)
let return = Analytics.calculate_sharpe_returns portfolio

(* Calculate win rate *)
let wr = Analytics.win_rate model.trades

(* Get average trade size *)
let avg = Analytics.average_trade_size model.trades
```

## Integration with Main UI

Advanced features are implemented as separate modules that integrate with the core order book:

1. **Order_Type**: Extend order processing logic
2. **Position**: Track P&L for each security
3. **Portfolio**: Aggregate portfolio metrics
4. **Advanced_Order**: New order workflows
5. **CSV_Handler**: Data persistence
6. **Analytics**: Performance measurement

### Adding Advanced Order Support to app.ml

```ocaml
(* In effects.ml *)
let place_advanced_order ~order_type ~threshold ~visible_qty =
  let order = { Order.id; price; qty; side } in
  let adv_order = Advanced_Order.create 
    ~id ~order_type ~order ~threshold ~visible_qty created_at in
  (* Process advanced_order *)

(* In state.ml *)
type t = {
  (* ... existing fields ... *)
  portfolio : Portfolio.t;
  positions : Position.t list;
  advanced_orders : Advanced_Order.t list;
}

type action =
  | (* ... existing actions ... *)
  | Place_Advanced_Order of Advanced_Order.t
  | Update_Position of string * float
  | Export_Data of string
```

## Example Trading Scenario

```ocaml
(* Initialize *)
let book = Order_book.create ()
let portfolio = Portfolio.create ~cash:100000.0

(* Place limit buy order *)
let buy_msg = Message.of_string "100.5,1,1,500,50000,1" in
let trades = Order_book.add book buy_msg in

(* Create position tracking *)
let position = Position.create
  ~symbol:"SPY"
  ~quantity:500
  ~entry_price:50000.0
  ~current_price:50000.0
  ~side:`Long
  ~timestamp:100.5 in
let portfolio = Portfolio.add_position portfolio position in

(* Price moves up *)
let updated_pos = Position.mark_price_update position 50050.0 in
let pnl = Position.unrealized_pnl updated_pos (* 25000.0 *)in

(* Place stop-loss order *)
let stop_msg = Message.of_string "100.6,1,2,500,49900,2" in
let stop_order = Advanced_Order.create
  ~id:2
  ~order_type:Stop_Loss
  ~order:{ id=2; price=49900; qty=500; side=`Sell }
  ~threshold:(Some 49950)
  ~visible_qty:500
  100.6 in

(* Export report *)
let () = CSV_Handler.export_summary portfolio "trading_report.csv" in
()
```

## Future Enhancements

- Bracket orders (primary + OCO orders)
- Algorithmic execution (TWAP, VWAP)
- Risk controls and position limits
- Margin and leverage management
- Multi-leg strategies
- Real-time P&L streaming
- Market replay and backtesting
- Machine learning integration

---

For more information, see the main README.md and API documentation in engine.mli.
