# Aero-Exchange Development Guide

## Table of Contents
1. [Setup](#setup)
2. [Architecture](#architecture)
3. [Coding Standards](#coding-standards)
4. [Testing](#testing)
5. [Building](#building)
6. [Performance Optimization](#performance-optimization)
7. [Debugging](#debugging)
8. [Deployment](#deployment)

## Setup

### Prerequisites
- OCaml 4.14 or later
- Dune 3.22+
- OPAM (OCaml Package Manager)
- Core libraries: `opam install core bonsai bonsai.web js_of_ocaml`

### Development Environment

```bash
# Clone repository
git clone https://github.com/aero-exchange/aero-exchange.git
cd aero-exchange

# Install dependencies
opam switch create . 4.14.0 --deps-only
eval $(opam env)

# Build project
dune build

# Run tests
dune runtest

# Build web UI
dune build web/app.bc.js

# Serve locally
python -m http.server 8000
# Visit: http://localhost:8000/index.html
```

## Architecture

### Project Layout

```
aero-exchange/
├── lib/
│   ├── types.ml            # Core types
│   ├── types.mli           # Type signatures
│   ├── engine.ml           # Order matching engine
│   ├── engine.mli          # Engine public API
│   ├── advanced_features.ml # Position tracking, etc.
│   └── dune
├── web/
│   ├── app.ml              # Main component
│   ├── state.ml            # State management
│   ├── effects.ml          # Side effects
│   ├── ui.ml               # Visualizations
│   └── dune
├── test/
│   ├── test_aero_exchange.ml
│   └── dune
├── index.html              # Entry point
├── dune-project            # Project metadata
├── aero_exchange.opam      # Package definition
├── README.md               # User guide
├── ADVANCED_FEATURES.md    # Feature documentation
└── DEVELOPMENT.md          # This file
```

### Module Dependencies

```
types.ml
    ↓
engine.ml → advanced_features.ml
    ↓
web/state.ml ← web/effects.ml
    ↓         ↓
web/ui.ml ← web/app.ml
```

### Data Flow

1. **Input**: Messages from market data stream or user actions
2. **Processing**: `engine.ml` processes orders, matches, and calculates analytics
3. **State**: `state.ml` updates application state via Bonsai actions
4. **Rendering**: `ui.ml` components render based on current state
5. **Output**: HTML/CSS displayed to user

## Coding Standards

### OCaml Style Guide

**Naming Conventions**
- Module names: PascalCase (`Order_book`, `Portfolio`)
- Function names: snake_case (`get_spread`, `add_order`)
- Type names: snake_case (`message_t`, `order_t`)
- Constants: UPPER_CASE (`MAX_ORDERS`, `DEFAULT_SPREAD`)

**Function Documentation**

```ocaml
(** Get bid-ask spread.
    
    @param t order book
    @return spread in basis points, or None if no market
*)
let get_spread t =
  match Map.max_elt t.bids, Map.min_elt t.asks with
  | Some (b, _), Some (a, _) -> Some (a - b)
  | _ -> None
```

**Error Handling**

Prefer explicit error types over exceptions:

```ocaml
(* Good *)
type 'a result = Ok of 'a | Error of string

(* Avoid *)
(* let value = function | Some x -> x | None -> failwith "..." *)
```

**Pattern Matching**

Be exhaustive and use guards when appropriate:

```ocaml
(* Good *)
let process = function
  | `Buy when price < threshold -> execute_buy price
  | `Sell when price > threshold -> execute_sell price
  | `Buy | `Sell -> hold ()

(* Avoid *)
(* match side with `Buy -> ... | _ -> ... *)
```

### Code Organization

**Keep functions pure**: Avoid mutable state in core logic.

```ocaml
(* Good *)
let add_order book msg =
  let trades = match_orders book msg in
  let new_book = update_book book msg in
  (new_book, trades)

(* Avoid *)
(* let add_order book msg =
  book.orders <- msg :: book.orders;  (* mutation *)
  match_orders book
*)
```

**Single Responsibility**: Each function should do one thing well.

```ocaml
(* Good *)
let get_imbalance_ratio t =
  let bid_vol = get_total_bid_volume t in
  let ask_vol = get_total_ask_volume t in
  if ask_vol = 0 then 0.0
  else Float.of_int bid_vol /. Float.of_int ask_vol

(* Avoid *)
(* let get_all_metrics t = ... (* too much) *)
```

## Testing

### Test Structure

Tests are organized by module:

```ocaml
let test_order_matching () =
  print_endline "=== Test: Order Matching ===";
  let book = Order_book.create () in
  let bid_msg = create_message ~time:100.0 ~kind:1 ~id:1 ~size:100 ~price:50000 ~side:1 in
  let _ = Order_book.add book bid_msg in
  let sell_msg = create_message ~time:101.0 ~kind:1 ~id:2 ~size:50 ~price:50000 ~side:2 in
  let trades = Order_book.add book sell_msg in
  
  assert (List.length trades = 1);
  print_endline "✓ Partial order matching works"
```

### Running Tests

```bash
# Run all tests
dune runtest

# Run specific test file
dune runtest test/

# Run with verbose output
dune runtest --verbose
```

### Adding New Tests

1. Create test function following pattern: `let test_feature () = ...`
2. Add assertions for expected behavior
3. Print status messages for debugging
4. Call test function in `let () = ...` block

## Building

### Debug Build

```bash
dune build --verbose
```

### Release Build

```bash
dune build --release
```

### Web UI Build

```bash
dune build web/app.bc.js
# Output: _build/default/web/app.bc.js

# For production
dune build web/app.bc.js --release
```

### Build Specific Targets

```bash
# Build just the library
dune build lib/aero_lib.a

# Build just tests
dune build @runtest

# Build web app
dune build web/app.bc.js
```

## Performance Optimization

### Profiling

The order matching is O(log n) for most operations:

- **Add order**: O(log n) for map updates
- **Cancel order**: O(1) hashtable lookup + O(log n) map update
- **Get spread**: O(1) with cached min/max
- **Full matching**: O(m) where m = matched quantity

### Optimization Tips

1. **Use Int.Map instead of Hashtbl** for price levels (ordered, immutable)
2. **Cache best bid/ask** rather than recalculating
3. **Lazy evaluation** for expensive computations
4. **Profile hot paths** with benchmarks

### Benchmarking

```bash
# Add to dune file:
(executable
 (name bench_order_book)
 (libraries core core_bench aero_lib))

# Run benchmark
dune exec bench/bench_order_book.exe
```

## Debugging

### Console Logging

```ocaml
(* Add temporary debug prints *)
let () = printf "[DEBUG] order book size: %d\n" (Map.length book.bids)

(* Use sexp for structured debugging *)
let () = printf "%s\n" (Sexp.to_string (Order_book.sexp_of_t book))
```

### Testing in REPL

```bash
# Start OCaml REPL
ocaml

# Load library
#use "topfind";;
#require "core";;
#require "aero_lib";;

(* Test functions *)
open Aero_lib.Types
open Aero_lib.Engine

let book = Order_book.create ();;
let msg = { Message.time=100.0; kind=1; id=1; size=100; price=50000; side=1 };;
let trades = Order_book.add book msg;;
```

### Common Issues

**Issue**: Tests fail with "Undefined reference"
- **Solution**: Check dune file has all required libraries in `(libraries ...)`

**Issue**: Web app doesn't load
- **Solution**: Verify `dune build web/app.bc.js` completes, check script path in HTML

**Issue**: Type errors in Bonsai code
- **Solution**: Ensure preprocessing includes `bonsai.ppx_bonsai` in dune file

## Deployment

### Build Artifact

```bash
# Build web application
dune build web/app.bc.js

# Files to deploy:
_build/default/web/app.bc.js  # Compiled JavaScript
index.html                      # HTML entry point
```

### Static Server

```bash
# Simple HTTP server (development)
python -m http.server 8000

# Production server (Node.js)
npm install -g serve
serve -p 8000

# Production server (Nginx)
# Configure to serve index.html and set Cache-Control headers
```

### Environment Setup

```bash
# Production environment variables (if needed)
export AERO_ENV=production
export AERO_API_URL=https://api.example.com

dune build --release
```

## Common Development Tasks

### Adding a New Order Type

1. Add variant to `Order_Type` in `advanced_features.ml`
2. Add matching logic to `Advanced_Order.can_match`
3. Add test in `test/test_aero_exchange.ml`
4. Update UI if needed in `web/ui.ml`

### Adding a New Market Metric

1. Implement calculation in `engine.ml`
2. Add `.mli` signature in `engine.mli`
3. Add test for edge cases
4. Expose in `state.ml` if needed for UI
5. Display in `web/ui.ml`

### Adding UI Components

1. Create render function in `web/ui.ml`
2. Import and call from `web/app.ml` in component body
3. Add CSS styling to `index.html`
4. Test with different market conditions

## Continuous Integration

### GitHub Actions Example

```yaml
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        ocaml-version: ['4.14.0']
    steps:
      - uses: actions/checkout@v2
      - uses: ocaml/setup-ocaml@v2
        with:
          ocaml-version: ${{ matrix.ocaml-version }}
      - run: opam install . --deps-only
      - run: dune build
      - run: dune runtest
```

## Release Process

1. Update version in `dune-project`
2. Update CHANGELOG.md
3. Tag release: `git tag v1.0.0`
4. Push to GitHub
5. Build and test: `dune build --release`
6. Generate tarball: `git archive --format tar.gz --prefix aero-exchange-1.0.0/ v1.0.0`
7. Upload artifacts

---

For questions or contributions, see the main README.md and ADVANCED_FEATURES.md.
