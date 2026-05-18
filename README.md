# Aero-Exchange: Professional L2 Order Book Trading System

A high-performance OCaml-based trading platform featuring real-time order book visualization, market depth analysis, and professional UI for Jane Street-style trading operations.

## Tech Stack

This project is built using the **Jane Street** technology stack, designed for high-performance, robust systems:

- **[Bonsai](https://github.com/janestreet/bonsai)**: Jane Street's functional reactive UI framework for building web applications in OCaml.
- **[Core](https://github.com/janestreet/core)**: Jane Street's comprehensive standard library overlay, providing industrial-strength data structures and utilities.
- **[ppx_jane](https://github.com/janestreet/ppx_jane)**: Standard Jane Street syntax extensions for OCaml.
- **[js_of_ocaml](https://github.com/ocsigen/js_of_ocaml)**: Compiler from OCaml to Javascript, enabling high-performance frontend execution.
- **[Dune](https://dune.build/)**: The standard composable build system for OCaml projects.

## Features

### Core Trading Engine
- **High-Performance Order Book**: Efficient matching engine with O(1) lookups using hashtables and maps
- **Real-Time Order Matching**: Automatic matching of aggressive orders against the book
- **Order Management**: Add, remove, and modify orders with full state tracking
- **Trade Recording**: Complete trade history with timestamps and price levels
- **Market Analytics**: Spread calculation, mid-price, volumes, imbalance ratios, VWAP

### User Interface
- **L2 Depth Visualization**: Interactive order book display with bid/ask walls
- **Market Statistics**: Real-time display of best bid/ask, spreads, and mid-price
- **Sparkline Chart**: Historical price movement visualization
- **Trade Tape**: Real-time trade execution tape
- **Responsive Design**: Mobile-friendly interface with professional styling
- **Accessibility**: ARIA labels, keyboard navigation, semantic HTML

### Simulation Features
- **Synthetic Data Generator**: Configurable market data stream generation
- **Speed Control**: Adjustable simulation speed from 10ms to 1000ms+ intervals
- **Volatility Control**: Configurable mid-price volatility for realistic scenarios
- **Live Order Entry**: Place and cancel orders through the UI with prompts

## Architecture

### Project Structure

```
aero-exchange/
├── lib/
│   ├── types.ml          # Core type definitions (Message, Order, Trade)
│   ├── engine.ml         # Order matching engine and market analytics
│   └── dune
├── web/
│   ├── app.ml            # Main UI component (refactored, modular)
│   ├── state.ml          # Application state and actions
│   ├── effects.ml        # Side effects and event handlers
│   ├── ui.ml             # UI visualization components
│   └── dune
├── test/
│   ├── test_aero_exchange.ml  # Comprehensive test suite
│   └── dune
├── index.html            # HTML entry point with professional styling
├── dune-project          # Project configuration
├── aero_exchange.opam    # OCaml package definition
└── README.md             # This file
```

### Module Organization

**types.ml**: Defines core data types
- `Message.t`: Market data messages (add, remove, modify)
- `Order.t`: Pending orders in the book
- `Trade.t`: Executed trades

**engine.ml**: The matching engine
- `Order_book.t`: Main order book structure with bids/asks
- `add`: Process incoming orders
- `remove`: Cancel orders
- `get_spread`, `get_mid_price`, `get_total_bid_volume`, etc.: Market analytics
- `validate`: Ensure book integrity

**state.ml**: Bonsai state management
- `Model.t`: Application state (bids, asks, trades, settings)
- `Action.t`: State modifications

**effects.ml**: Side effects and timers
- `now_seconds()`: High-resolution timestamps
- `start_timer()`: Continuous market data feed
- `run_mock_feed()`: Initialize synthetic orders
- `toggle_running()`, `adjust_speed()`: User interactions

**ui.ml**: Visualization components
- `render_depth_row()`: Single order book level
- `render_depth_visual()`: Aggregate depth chart
- `render_sparkline()`: Price history
- `render_market_stats()`: Key metrics display
- `render_last_trade()`: Recent trade highlight

**app.ml**: Main application
- `component`: Bonsai UI component
- `apply_action`: State reducer
- `render_*` functions: Major UI sections

## Building and Running

### Prerequisites
- OCaml 4.14+
- Dune 3.22+
- OPAM package manager
- Core, Bonsai, Bonsai.Web libraries

### Build
```bash
dune build
```

### Run Tests
```bash
dune runtest
```

### Build Web UI
```bash
dune build web/app.bc.js
```

### Serve Locally
```bash
# Option 1: Using Python
python -m http.server 8000

# Option 2: Using Node
npx http-server

# Then open: http://localhost:8000/index.html
```

## CSV Data Format

The system accepts market data in CSV format:

```
time,kind,id,size,price,side
100.5,1,123,50,50000,1
```

Where:
- **time**: Unix timestamp (float)
- **kind**: Message type (1=add, 2-5=cancel/modify)
- **id**: Order ID (int)
- **size**: Order size/quantity (int)
- **price**: Order price (int, in basis points or smallest unit)
- **side**: 1=buy, 2=sell

## API Reference

### Order Book Operations

```ocaml
(* Create new order book *)
let book = Order_book.create ()

(* Add order and get trades *)
let trades = Order_book.add book message

(* Remove order *)
Order_book.remove book order_id

(* Get market metrics *)
let spread = Order_book.get_spread book
let mid = Order_book.get_mid_price book
let bid_vol = Order_book.get_total_bid_volume book
let imbalance = Order_book.get_imbalance_ratio book
let vwap = Order_book.get_vwap book

(* Validate book integrity *)
assert (Order_book.validate book)

(* Reset book *)
Order_book.reset book
```

### State Management

```ocaml
(* Dispatch actions *)
inject (Action.Place_Order msg)
inject (Action.Toggle_Running)
inject (Action.Set_Speed 150)
inject (Action.Update_Base_Mid new_mid)
```

## Testing

The test suite covers:
- Message parsing and CSV input
- Order addition and removal
- Order matching (partial and full)
- Spread and mid-price calculation
- Volume calculations
- Imbalance ratios and VWAP
- Book validation
- Edge cases (zero size, large orders, etc.)

Run tests with:
```bash
dune runtest
```

## Performance Characteristics

- **Order Addition**: O(log n) for book updates
- **Order Matching**: O(m) where m = matched quantities
- **Order Cancellation**: O(1) hashtable lookup + O(log n) map update
- **Spread Query**: O(1) with single max/min operations
- **Memory**: Efficient use of hashtables and immutable maps

## Advanced Features

### Market Analytics
- **Spread**: Bid-ask spread calculation
- **Mid-price**: Average of best bid and ask
- **Total Volumes**: Aggregated bid/ask volume
- **Imbalance Ratio**: Bid volume / Ask volume indicator
- **VWAP**: Volume-weighted average price
- **Depth Snapshot**: Multi-level depth extraction

### UI Enhancements
- Color-coded bid (green) and ask (red) prices
- Animated depth bars showing order quantities
- Real-time sparkline price history
- Trade tape with side coloring
- Responsive layout for mobile devices
- Professional GitHub-dark theme

## Future Enhancements

- [ ] Advanced order types (stop-loss, iceberg, etc.)
- [ ] P&L calculator and position tracking
- [ ] CSV file upload and replay
- [ ] Order modification (amend price/size)
- [ ] Level 3 market data support
- [ ] Performance benchmarks and profiling
- [ ] WebSocket integration for live feeds
- [ ] Database persistence layer
- [ ] Risk management and circuit breakers
- [ ] Advanced charting library (Recharts/Plotly)

## Contributing

1. Ensure all tests pass: `dune runtest`
2. Follow OCaml style guidelines
3. Add tests for new features
4. Update documentation
5. Build with `dune build` to verify

## Performance Tips

- Use the "Speed +" button to simulate faster markets
- Adjust "Vol +" to increase price volatility
- Monitor trade tape for market microstructure patterns
- Test order matching performance with large order counts

## License

MIT License - See LICENSE file for details

## Authors

Jane Street Trading System - Professional Trading Platform

## Support

For issues, questions, or suggestions, please open an issue on the repository.

---

**Aero-Exchange** - Where precision meets performance in trading systems.
