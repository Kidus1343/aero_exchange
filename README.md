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

## CSV Data Format & Message Structure

The engine parses raw LOBSTER (Limit Order Book System - The Efficient Reconstructor) market data in CSV format line-by-line:

```csv
time,kind,id,size,price,side
100.5,1,123,50,50000,1
```

### The Message Field Breakdown

| Column | Name | Description | OCaml Type |
| :--- | :--- | :--- | :--- |
| **1** | **Time** | Seconds since midnight (e.g., `34200.017`) | `float` |
| **2** | **Type** | **1**: Add, **2/3**: Cancel, **4/5**: Execute | `int` |
| **3** | **Order ID** | Unique ID for the order | `int` |
| **4** | **Size** | Number of shares / quantity | `int` |
| **5** | **Price** | Price (integer format) | `int` |
| **6** | **Direction** | **1** for Buy (Bid), **-1** for Sell (Ask) | `int` |

> ⚠️ **Jane Street Design Principle: NEVER Use Floats for Money (Price)**
> Floating-point numbers (`float` / `double`) suffer from binary representation errors (e.g., `0.1 + 0.2 = 0.30000000000000004`). In financial systems, a sub-penny error can accumulate into millions of dollars or cause incorrect order matching. 
> To prevent this, **Aero-Exchange** represents all prices as integers (multiplied by 10,000 to avoid decimals, i.e., in basis points or hundredths of a cent), keeping calculations 100% precise and highly efficient.

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

## ⚡ High-Frequency Trading (HFT) Performance & GC Tuning

In High-Frequency Trading (HFT), latency is measured in microseconds ($\mu\text{s}$) or nanoseconds ($\text{ns}$). A key metric is **Tick-to-Trade Latency**: the time elapsed from when a market message is parsed to when the matching engine completes processing/matching it.

### 1️⃣ The Mail Sorting Analogy
Think of the engine as a mailroom:
1. A letter **arrives** at the sorting desk (the parser reads a line from disk).
2. A worker **checks the letter** and decides where it goes (parsing complete).
3. The letter **gets placed into the correct mailbox** (the matching engine matches or adds the order).

**Tick-to-Trade latency** is the time elapsed from step 2 to step 3.

---

### 2️⃣ Why the Latency Spike Happens
During testing, we observed a maximum latency spike of **~51 ms**. In HFT, a 51 ms pause is catastrophic. This spike is caused by OCaml's **Garbage Collector (GC)**:
- OCaml organizes memory into a **Minor Heap** (for short-lived objects like parsed `Message.t` and `Order.t` records) and a **Major Heap** (for long-lived objects).
- When the minor heap fills up, the **Minor GC** runs to collect short-lived objects. Usually, this is fast.
- However, if the minor heap fills up too frequently or triggers promotion of heavy objects, it leads to a **Stop-the-World Major GC** pause. The program halts completely while the major heap is reorganized.

---

### 3️⃣ How Jane Street Tunes the GC
Jane Street systems tune the OCaml GC parameters to minimize tail latency rather than rewriting code in lower-level languages. In **Aero-Exchange**, I programmatically adjust GC settings inside the entry point ([bin/main.ml](file:///home/kidus/aero_exchange-main/bin/main.ml)):

```ocaml
let () =
  let control = Gc.get () in
  Gc.set { control with 
    minor_heap_size = 1024 * 1024 * 16; (* 16MB minor heap to prevent GC thrashing *)
    space_overhead = 100;               (* Collect major heap faster *)
  };
```

#### The GC Tuning Trade-Off (Max vs. Average Latency)
By increasing the **Minor Heap size** (e.g., from default to 16MB), we:
1. **Reduce Max Latency (Tail Pauses):** A larger minor heap creates a larger cushion. Short-lived objects are created and destroyed entirely in the minor heap without triggering minor heap overflows and heavy promotions. This reduces the maximum latency spikes **from ~51 ms to ~28 ms**.
2. **Increase Average Latency Slightly:** A larger minor heap means that when a collection *does* run, the GC has more memory to scan, making each individual cleanup slightly heavier. This shifts average latency from **~663 ns to ~1.5 μs**.

#### Why This Matters in HFT
In high-frequency trading:
- **Min Latency** represents the "fast path" (simple book updates when the GC is idle).
- **Max Latency (Tail Risk)** is the occasional long pause. A single 50 ms pause could miss critical price movements and cost millions.
- HFT engineers **willingly trade a slightly higher average latency for a significantly lower max tail latency**.

---

### 4️⃣ Latency Benchmarks in Perspective

| Metric | Latency | What it Represents |
| :--- | :--- | :--- |
| **Min Latency** | **20 ns** | Fast path (hash table lookup, direct memory write). |
| **Average Latency** | **1.5 μs** | ~666k messages/sec throughput. Highly efficient. |
| **Max Latency** | **28 ms** | Reduced tail pause (tuned minor heap). |

> ⚠️ **A Note on Jitter & VirtualBox**
> Host-OS scheduling jitter is inevitable when running OCaml inside VirtualBox or containers, as the engine competes with host processes for CPU cycles. For true production HFT latency, the engine is deployed on **bare-metal Linux** with **CPU pinning** and **real-time scheduling policies**.

---

### 🚀 Resume Talking Point: Passive Viewer to Matching Engine
- **Passive Order Book Viewer**: Many toy projects simply display an order book where bid/ask prices can overlap (negative spreads), which doesn't reflect real market dynamics.
- **Active Matching Engine**: **Aero-Exchange** actively implements **Price Improvement** (matching incoming buy orders at the lowest available sell price, or vice-versa) and real-time execution. Moving the platform to a true matching engine with tuned HFT GC parameter optimization makes this a highly advanced and conversational portfolio project.

## Complexity & Performance Characteristics

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

Kidus Messele Gebregziabher

## Support

For issues, questions, or suggestions, please open an issue on the repository.

---

**Aero-Exchange** - Where precision meets performance in trading systems.
