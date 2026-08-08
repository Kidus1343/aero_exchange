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

    (* Interactive UI state *)
    order_side : [`Buy | `Sell];
    order_type : [`Limit | `Market];
    price_input : string;
    qty_input : string;
    active_ticker : string;
    chart_tab : [`Line | `Depth];
    book_view : [`Split | `Vertical];
  } [@@deriving sexp]

  let equal = phys_equal

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
    cmd_log = ["✓ O(1) MATCHING ENGINE INITIALIZED (265ns Latency)"];
    order_side = `Buy;
    order_type = `Limit;
    price_input = "50000";
    qty_input = "100";
    active_ticker = "AAPL";
    chart_tab = `Line;
    book_view = `Split;
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
    | Set_Order_Side of [`Buy | `Sell]
    | Set_Order_Type of [`Limit | `Market]
    | Set_Price_Input of string
    | Set_Qty_Input of string
    | Set_Ticker of string
    | Set_Chart_Tab of [`Line | `Depth]
    | Select_Price_Level of int
    | Submit_Limit_Order
    | Clear_Book
    | Trigger_Flash_Crash
  [@@deriving sexp_of]
end
