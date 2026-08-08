open Core

(* ── Hot-path message ────────────────────────────────────────────
   Correction: an earlier revision of this file used an invented
   "int#" / "Int#" unboxed integer type. That doesn't exist in
   OxCaml — plain OCaml `int` is *already* an unboxed machine word
   (a tagged immediate), so there is nothing to unbox and no
   Int_u-style module for it. OxCaml only ships unboxed-number
   modules for the numeric types that are normally boxed:
   Float_u, Int32_u, Int64_u, Nativeint_u.
   The only genuinely-boxed field here is `time` (a float), so
   that's the only field that benefits from OxCaml's float#. ── *)
module Message = struct
  type t = {
    time  : float;
    kind  : int;
    id    : int;
    size  : int;
    price : int;
    side  : int;
  }

  let create ~time ~kind ~id ~size ~price ~side =
    { time; kind; id; size; price; side }

  let get_time  m = m.time
  let get_kind  m = m.kind
  let get_id    m = m.id
  let get_size  m = m.size
  let get_price m = m.price
  let get_side  m = m.side

  let of_string line =
    match String.split line ~on:',' with
    | [t; k; id; s; p; sd] ->
      { time  = Float.of_string t;
        kind  = Int.of_string k;
        id    = Int.of_string id;
        size  = Int.of_string s;
        price = Int.of_string p;
        side  = Int.of_string sd; }
    | _ -> failwith "Malformed CSV"

  let sexp_of_t m =
    Sexplib.Sexp.List [
      Sexplib.Sexp.Atom (Float.to_string m.time);
      Sexplib.Sexp.Atom (Int.to_string m.kind);
      Sexplib.Sexp.Atom (Int.to_string m.id);
      Sexplib.Sexp.Atom (Int.to_string m.size);
      Sexplib.Sexp.Atom (Int.to_string m.price);
      Sexplib.Sexp.Atom (Int.to_string m.side);
    ]
end

(* ── Cold-path / UI types (allocating is fine) ── *)
module Order = struct
  type t = { id : int; price : int; qty : int; side : [`Buy|`Sell] }
  [@@deriving sexp]
end

module Trade = struct
  type t = { time : float; price : int; qty : int; side : [`Buy|`Sell] }
  [@@deriving sexp]
end
