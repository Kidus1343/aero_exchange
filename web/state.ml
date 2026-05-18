open! Core
open! Bonsai_web
open Aero_lib.Types

module Model = struct
  type t = {
    bids : int Int.Map.t;
    asks : int Int.Map.t;
    trades : Trade.t list;
    running : bool;
    speed : int; (* interval ms *)
    volatility : int; (* scale of mid-price random walk *)
    base_mid : int;
    price_history : int list;
    cmd_input : string;
    cmd_log : string list;
  } [@@deriving sexp]

  let empty = {
    bids = Int.Map.empty;
    asks = Int.Map.empty;
    trades = [];
    running = true;
    speed = 100;
    volatility = 1;
    base_mid = 50000;
    price_history = [];
    cmd_input = "";
    cmd_log = [];
  }
end

module Action = struct
  type t =
    | Process_Message of Message.t
    | Reset
    | Toggle_Running
    | Set_Speed of int
    | Set_Volatility of int
    | Place_Order of Message.t
    | Update_Base_Mid of int
    | Set_Cmd_Input of string
    | Submit_Cmd
  [@@deriving sexp_of]
end
