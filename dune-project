(lang dune 3.22)

(name aero_exchange)

(version 0.2.0)

(generate_opam_files true)

(source
 (github aero-exchange/aero-exchange))

(authors "Jane Street Trading System")

(maintainers "aero-exchange@jane-street.com")

(license MIT)

(documentation https://github.com/aero-exchange/aero-exchange)

(package
 (name aero_exchange)
 (synopsis "Professional L2 order book and trading system")
 (description "Aero-Exchange is a high-performance trading platform featuring order book visualization, market depth analysis, and real-time order management.")
 (depends 
  (ocaml (>= 4.14))
  core
  bonsai
  (bonsai.web :with-test)
  js_of_ocaml
  (js_of_ocaml-ppx :with-test)
  ppx_jane)
 (tags
  ("trading" "finance" "order-book" "market-depth" "bonsai" "ui")))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/reference/dune-project/index.html
