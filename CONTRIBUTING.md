# Contributing to Aero-Exchange

Thank you for your interest in contributing to Aero-Exchange! We welcome contributions of all kinds.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/aero-exchange.git`
3. Create a feature branch: `git checkout -b feature/my-feature`
4. Make your changes
5. Push to your fork: `git push origin feature/my-feature`
6. Open a Pull Request

## Development Setup

```bash
cd aero-exchange
opam install . --deps-only
dune build
dune runtest
```

## Code Guidelines

### Style
- Follow OCaml naming conventions (PascalCase for modules, snake_case for functions)
- Keep functions pure and side-effect free where possible
- Use type annotations for public APIs
- Document public functions with `(** ... **)` comments

### Testing
- Add tests for new features in `test/test_aero_exchange.ml`
- Test both happy path and edge cases
- Run `dune runtest` before submitting

### Performance
- Profile hot paths with benchmarks
- Maintain O(log n) matching operations
- Avoid unnecessary allocations in tight loops

## Commit Message Format

```
type: Brief description (50 chars or less)

Longer description if needed, explaining the why and what.
Keep lines to 72 characters.

Fixes #123
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `perf`: Performance improvement
- `refactor`: Code restructuring
- `test`: Adding/updating tests
- `docs`: Documentation updates
- `style`: Code style changes

## Pull Request Process

1. Update documentation if adding features
2. Add tests for new functionality
3. Ensure `dune build` and `dune runtest` pass
4. Keep commits organized and descriptive
5. Respond to review comments promptly

## Areas for Contribution

### High Priority
- [ ] WebSocket support for live market data
- [ ] Database persistence layer
- [ ] Advanced charting library integration
- [ ] Risk management system
- [ ] Backtesting framework

### Medium Priority
- [ ] Improve UI performance with virtual scrolling
- [ ] Add keyboard shortcuts
- [ ] Dark/light theme toggle
- [ ] Export to more formats (JSON, Parquet)
- [ ] Mobile app wrapper

### Low Priority
- [ ] Additional market data providers
- [ ] Historical data tools
- [ ] Documentation improvements
- [ ] Example strategies
- [ ] Tutorial videos

## Reporting Bugs

When reporting bugs, include:
1. OCaml version (`ocamlc --version`)
2. Dune version (`dune --version`)
3. Steps to reproduce
4. Expected vs. actual behavior
5. Relevant logs or error messages

## Feature Requests

Feature requests should include:
1. Clear description of the feature
2. Use cases and expected benefits
3. Proposed implementation approach (if known)
4. Links to similar features in other projects

## Documentation

Documentation lives in:
- `README.md`: User guide
- `DEVELOPMENT.md`: Developer guide
- `ADVANCED_FEATURES.md`: Feature documentation
- `.ml` files: Inline code documentation
- `.mli` files: Public API signatures

When adding features, update relevant documentation.

## Code Review

All submissions require review by at least one maintainer. 

Review focuses on:
- Correctness of algorithm
- Performance implications
- Code clarity and maintainability
- Test coverage
- Documentation completeness

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

## Questions?

Feel free to open an issue or discussion for any questions!

---

Happy contributing!
