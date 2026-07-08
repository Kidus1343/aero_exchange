open Core
open Types

module Order_book : sig
  type t = {
    mutable bids            : int Int.Map.t;
    mutable asks            : int Int.Map.t;
    mutable volume_at_price : int Int.Map.t;
    orders                  : Order.t Hashtbl.M(Int).t;

    (* unboxed flat arrays — OxCaml int#/float# *)
    orders_id    : int# array;
    orders_price : int# array;
    orders_qty   : int# array;
    orders_side  : int# array;
    orders_next  : int# array;
    orders_prev  : int# array;
    mutable free_head : int;

    tbl_keys : int# array;
    tbl_vals : int# array;

    bids_price : int# array; bids_qty : int# array;
    bids_head  : int# array; bids_tail : int# array;
    mutable bids_count : int;

    asks_price : int# array; asks_qty : int# array;
    asks_head  : int# array; asks_tail : int# array;
    mutable asks_count : int;

    vol_price : int# array; vol_qty : int# array;
    mutable vol_count : int;

    trades_price : int# array;
    trades_qty   : int# array;
    trades_side  : int# array;
    trades_time  : float# array;
    mutable trades_count : int;
  }

  val create   : unit -> t
  val reset    : t -> unit

  (** Hot path — zero allocation, OxCaml [@zero_alloc] verified *)
  val add    : t -> Message.t -> int   (* returns # new trades *)
  val remove : t -> int -> unit

  (** Cold path — may allocate; rebuilds legacy Map fields for UI *)
  val add_legacy      : t -> Message.t -> Trade.t list
  val sync_maps       : t -> unit
  val pop_new_trades  : t -> Trade.t list

  val get_spread          : t -> int option
  val get_mid_price       : t -> int option
  val get_total_bid_volume : t -> int
  val get_total_ask_volume : t -> int
  val get_best_bid_ask    : t -> (int * int) option * (int * int) option
  val get_imbalance_ratio : t -> float
  val get_vwap            : t -> int
  val validate            : t -> bool
  val get_depth_snapshot  : t -> num_levels:int -> (int * int) list * (int * int) list
end
