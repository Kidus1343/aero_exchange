open Core

module Message = struct
  type t = {
    time   : float;
    kind   : int; 
    id     : int;
    size   : int;
    price  : int;
    side   : int; 
  } [@@deriving sexp]

  let of_string line =
    match String.split line ~on:',' with
    | [t; k; id; s; p; side] ->
      { time = Float.of_string t; kind = Int.of_string k;
        id = Int.of_string id; size = Int.of_string s;
        price = Int.of_string p; side = Int.of_string side; }
    | _ -> failwith "Malformed CSV"
end

module Order = struct
  type t = {
    id    : int;
    price : int;
    qty   : int;
    side  : [ `Buy | `Sell ];
  } [@@deriving sexp]
end

module Trade = struct
  type t = {
    time  : float;
    price : int;
    qty   : int;
    side  : [ `Buy | `Sell ];
  } [@@deriving sexp]
end