open Core
open Types

(** Order Book Module - Core trading engine *)
module Order_book : sig
  type t = {
    orders : Order.t Hashtbl.M(Int).t;
    mutable bids : int Int.Map.t;
    mutable asks : int Int.Map.t;
    mutable volume_at_price : int Int.Map.t;
  }

  (** Create a new empty order book *)
  val create : unit -> t

  (** Reset order book to empty state *)
  val reset : t -> unit

  (** Add an order to the book, returns list of executed trades *)
  val add : t -> Message.t -> Trade.t list

  (** Remove an order from the book *)
  val remove : t -> int -> unit

  (** Get bid-ask spread *)
  val get_spread : t -> int option

  (** Get mid-price (average of best bid and ask) *)
  val get_mid_price : t -> int option

  (** Get total bid volume *)
  val get_total_bid_volume : t -> int

  (** Get total ask volume *)
  val get_total_ask_volume : t -> int

  (** Get best bid and ask prices *)
  val get_best_bid_ask : t -> (int * int) option * (int * int) option

  (** Get imbalance ratio (bid_volume / ask_volume) *)
  val get_imbalance_ratio : t -> float

  (** Get volume-weighted average price *)
  val get_vwap : t -> int

  (** Validate that no orders exist on both sides at the same price *)
  val validate : t -> bool

  (** Get depth snapshot with specified number of levels *)
  val get_depth_snapshot : t -> num_levels:int -> (int * int) list * (int * int) list
end
