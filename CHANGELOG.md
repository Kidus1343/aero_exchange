# Changelog

All notable changes to Aero-Exchange are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Advanced order types (Market, Limit, Stop-Loss, Iceberg)
- Position tracking and P&L calculation
- Portfolio management system
- CSV export/import functionality
- Performance analytics (Sharpe ratio, win rate, etc.)
- Comprehensive test suite (14+ tests)
- Development guide (DEVELOPMENT.md)
- Contributing guidelines (CONTRIBUTING.md)
- API documentation (engine.mli)

### Changed
- Refactored web/app.ml into modular components (state.ml, effects.ml, ui.ml)
- Enhanced market analytics functions in engine.ml
- Improved HTML/CSS styling with professional theme
- Updated project configuration in dune-project

### Fixed
- Improved order matching algorithm stability
- Fixed edge cases in spread calculation
- Better handling of zero-size orders

### Improved
- Accessibility: ARIA labels, semantic HTML
- Responsive design for mobile devices
- Performance: Optimized depth visualization
- Code organization: Clear module responsibilities

## [0.1.0] - 2024-05-17

### Initial Release

#### Core Features
- Order book implementation with bid/ask levels
- Order matching engine (add, cancel, modify)
- Trade recording and history
- Market analytics (spread, mid-price, volumes)

#### User Interface
- L2 depth visualization with color-coded bid/ask
- Real-time market statistics display
- Sparkline price history chart
- Trade tape with execution details
- Order entry with manual input
- Speed and volatility controls

#### Simulation
- Synthetic market data generator
- Configurable simulation speed (10ms - 1000ms+)
- Price volatility control
- Random order generation

#### Technical
- Built with OCaml and Bonsai framework
- Efficient order book using Int.Map and Hashtbl
- GitHub-dark themed UI
- Responsive layout

#### Testing
- Basic order book tests
- Message parsing tests

#### Documentation
- README with quick start
- Project structure documentation

---

## Detailed Changes

### Version 0.2.0 (Planned)
- Multi-symbol support
- WebSocket data feed
- Real-time P&L dashboard
- Risk monitoring
- Backtesting engine

### Version 0.3.0 (Planned)
- Machine learning models
- Algorithmic execution (TWAP, VWAP)
- Market microstructure analysis
- Advanced charting

---

## Upgrade Guide

### 0.1.0 → Unreleased

No breaking changes. Existing projects should continue to work.

**Optional**: To use new advanced features:
1. Update import: `open Aero_lib.Advanced_features`
2. Use new order types: `Order_Type.Iceberg`, `Order_Type.Stop_Loss`
3. Track positions: `Portfolio.t` and `Position.t`

---

## Known Issues

- Browser console shows Js_of_ocaml warnings (non-critical)
- Large order books (10k+ levels) may experience UI lag
- CSV export limited to 100 most recent trades

## Roadmap

### Q2 2024
- [ ] Multi-symbol support
- [ ] Order book replay from files
- [ ] Performance benchmarks

### Q3 2024
- [ ] WebSocket integration
- [ ] Real-time risk monitoring
- [ ] Advanced charting library

### Q4 2024
- [ ] Backtesting framework
- [ ] Machine learning features
- [ ] Cloud deployment support

---

For more information, see:
- [README.md](README.md) - User guide
- [DEVELOPMENT.md](DEVELOPMENT.md) - Development guide
- [ADVANCED_FEATURES.md](ADVANCED_FEATURES.md) - Feature documentation
