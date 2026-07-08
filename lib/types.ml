open Core

(* ── Hot-path message — all fields unboxed (OxCaml int#/float#) ── *)
module Message = struct
  type t = {
    time  : float#;
    kind  : int#;
    id    : int#;
    size  : int#;
    price : int#;
    side  : int#;
  }

  let create ~time ~kind ~id ~size ~price ~side =
    { time  = Float#.of_float time;
      kind  = Int#.of_int kind;
      id    = Int#.of_int id;
      size  = Int#.of_int size;
      price = Int#.of_int price;
      side  = Int#.of_int side; }

  let get_time  m = Float#.to_float m.time
  let get_kind  m = Int#.to_int m.kind
  let get_id    m = Int#.to_int m.id
  let get_size  m = Int#.to_int m.size
  let get_price m = Int#.to_int m.price
  let get_side  m = Int#.to_int m.side

  let of_string line =
    match String.split line ~on:',' with
    | [t; k; id; s; p; sd] ->
      { time  = Float#.of_float (Float.of_string t);
        kind  = Int#.of_int    (Int.of_string k);
        id    = Int#.of_int    (Int.of_string id);
        size  = Int#.of_int    (Int.of_string s);
        price = Int#.of_int    (Int.of_string p);
        side  = Int#.of_int    (Int.of_string sd); }
    | _ -> failwith "Malformed CSV"

  let sexp_of_t m =
    Sexplib.Sexp.List [
      Sexplib.Sexp.Atom (Float.to_string (Float#.to_float m.time));
      Sexplib.Sexp.Atom (Int.to_string   (Int#.to_int    m.kind));
      Sexplib.Sexp.Atom (Int.to_string   (Int#.to_int    m.id));
      Sexplib.Sexp.Atom (Int.to_string   (Int#.to_int    m.size));
      Sexplib.Sexp.Atom (Int.to_string   (Int#.to_int    m.price));
      Sexplib.Sexp.Atom (Int.to_string   (Int#.to_int    m.side));
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