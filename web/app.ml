open! Core
open! Bonsai_web
open! Js_of_ocaml
open Aero_lib.Types
open Aero_lib.Engine
open State
open Effects
open Ui

(* --- STATE REDUCER --- *)
let apply_action _context (model : Model.t) book_ref = function
  | Action.Reset ->
      Order_book.reset book_ref;
      Model.empty

  | Action.Process_Message msg ->
      let trades = (match msg.kind with
        | 1 -> Order_book.add book_ref msg
        | 2 | 3 | 4 | 5 -> Order_book.remove book_ref msg.id; []
        | _ -> [])
      in
      { model with
        bids = book_ref.bids;
        asks = book_ref.asks;
        trades = List.rev trades @ model.trades
      }

  | Action.Place_Order msg ->
      let trades = Order_book.add book_ref msg in
      { model with
        bids = book_ref.bids;
        asks = book_ref.asks;
        trades = List.rev trades @ model.trades
      }

  | Action.Toggle_Running -> { model with running = not model.running }
  | Action.Set_Speed n -> { model with speed = n }
  | Action.Set_Volatility v -> { model with volatility = v }
  | Action.Update_Base_Mid m ->
      let history = m :: model.price_history in
      let history = if List.length history > 600 then List.take history 600 else history in
      { model with base_mid = m; price_history = history }
  | Action.Set_Cmd_Input s -> { model with cmd_input = s }
  | Action.Submit_Cmd ->
      let cmd = String.strip model.cmd_input |> String.uppercase in
      let parts = String.split ~on:' ' cmd |> List.filter ~f:(fun s -> String.length s > 0) in
      let new_log, msg_opt =
        try
          match parts with
          | ["B"; qty; price] ->
              let q = Int.of_string qty in
              let p = Int.of_string price in
              let msg = { Message.time = now_seconds (); kind = 1; id = Random.int_incl 100000 999999; size = q; price = p; side = 1 } in
              ("✓ BUY " ^ qty ^ " @ " ^ price, Some msg)
          | ["S"; qty; price] ->
              let q = Int.of_string qty in
              let p = Int.of_string price in
              let msg = { Message.time = now_seconds (); kind = 1; id = Random.int_incl 100000 999999; size = q; price = p; side = 2 } in
              ("✓ SELL " ^ qty ^ " @ " ^ price, Some msg)
          | ["C"; id] ->
              let i = Int.of_string id in
              let msg = { Message.time = now_seconds (); kind = 2; id = i; size = 0; price = 0; side = 0 } in
              ("✓ CX " ^ id, Some msg)
          | _ -> ("✗ ERR: use B/S <qty> <px> or C <id>", None)
        with _ -> ("✗ ERR: parse failed", None)
      in
      let trades = match msg_opt with
        | Some m ->
            if m.kind = 1 then Order_book.add book_ref m
            else (Order_book.remove book_ref m.id; [])
        | None -> []
      in
      let log = List.take (new_log :: model.cmd_log) 8 in
      { model with
        cmd_input = "";
        cmd_log = log;
        bids = book_ref.bids;
        asks = book_ref.asks;
        trades = List.rev trades @ model.trades
      }

(* --- CONTROLS PANEL --- *)
let render_controls (model : Model.t) inject =
  let open Bonsai_web.Vdom in
  let pause_label = if model.running then "⏸ Pause" else "▶ Resume" in
  let pause_class = if model.running then "btn-pause" else "" in
  Node.div ~attrs:[ Attr.class_ "panel controls" ] [
    Node.div ~attrs:[ Attr.class_ "panel-header" ] [
      Node.text "Controls";
      Node.span ~attrs:[ Attr.class_ "ph-badge" ] [
        Node.text (Printf.sprintf "spd:%dms vol:%d" model.speed model.volatility)
      ];
    ];
    Node.div ~attrs:[ Attr.class_ "controls-grid" ] [
      Node.button ~attrs:[
        Attr.class_ pause_class;
        Attr.on_click (fun _ -> Ui_effect.of_sync_fun (fun () -> toggle_running inject model) ())
      ] [ Node.text pause_label ];

      Node.button ~attrs:[
        Attr.on_click (fun _ -> Ui_effect.of_sync_fun (fun () ->
          Dom_html.window##alert (Js.string ("Exported " ^ Int.to_string (List.length model.trades) ^ " trades"));
          ignore (Ui_effect.Expert.handle (inject Action.Reset))
        ) ())
      ] [ Node.text "Reset" ];

      Node.button ~attrs:[
        Attr.on_click (fun _ -> Ui_effect.of_sync_fun (fun () -> adjust_speed inject (-50)) ())
      ] [ Node.text "Speed -" ];

      Node.button ~attrs:[
        Attr.on_click (fun _ -> Ui_effect.of_sync_fun (fun () -> adjust_speed inject 50) ())
      ] [ Node.text "Speed +" ];

      Node.button ~attrs:[
        Attr.on_click (fun _ -> Ui_effect.of_sync_fun (fun () ->
          volatility_ref := Int.max 1 (!volatility_ref - 1);
          ignore (Ui_effect.Expert.handle (inject (Action.Set_Volatility !volatility_ref)))
        ) ())
      ] [ Node.text "Vol -" ];

      Node.button ~attrs:[
        Attr.on_click (fun _ -> Ui_effect.of_sync_fun (fun () ->
          volatility_ref := !volatility_ref + 1;
          ignore (Ui_effect.Expert.handle (inject (Action.Set_Volatility !volatility_ref)))
        ) ())
      ] [ Node.text "Vol +" ];
    ]
  ]

(* --- ORDER ENTRY CLI --- *)
let render_order_entry (model : Model.t) inject =
  let open Bonsai_web.Vdom in
  Node.div ~attrs:[ Attr.class_ "panel order-entry-cli" ] [
    Node.div ~attrs:[ Attr.class_ "panel-header" ] [
      Node.text "Order Entry";
      Node.span ~attrs:[ Attr.class_ "ph-badge" ] [ Node.text "B qty px | S qty px | C id" ];
    ];
    Node.div ~attrs:[ Attr.class_ "cli-log" ] (
      List.map model.cmd_log ~f:(fun l -> Node.div ~attrs:[] [ Node.text l ])
    );
    Node.input ~attrs:[
      Attr.type_ "text";
      Attr.class_ "cli-input";
      Attr.placeholder "> B 100 50050";
      Attr.value model.cmd_input;
      Attr.on_input (fun _ s -> inject (Action.Set_Cmd_Input s));
      Attr.on_keydown (fun ev ->
        if ev##.keyCode = 13 then inject Action.Submit_Cmd
        else Ui_effect.Ignore)
    ] ();
  ]

(* --- TRADE TAPE --- *)
let render_trade_tape (model : Model.t) =
  let open Bonsai_web.Vdom in
  Node.div ~attrs:[ Attr.class_ "panel trade-tape" ] (
    [ Node.div ~attrs:[ Attr.class_ "panel-header" ] [
        Node.text "Time & Sales";
        Node.span ~attrs:[ Attr.class_ "ph-badge" ] [
          Node.text (Int.to_string (List.length model.trades) ^ " fills")
        ];
      ];
      Node.div ~attrs:[ Attr.class_ "tape-col-header" ] [
        Node.span ~attrs:[] [ Node.text "Time" ];
        Node.span ~attrs:[] [ Node.text "Price" ];
        Node.span ~attrs:[] [ Node.text "Qty" ];
        Node.span ~attrs:[] [ Node.text "Side" ];
      ];
    ] @
    List.map (List.take model.trades 80) ~f:(fun t ->
      let side_str = match t.side with `Buy -> "BUY" | `Sell -> "SELL" in
      let side_class = match t.side with `Buy -> "buy" | `Sell -> "sell" in
      Node.div ~attrs:[ Attr.class_ "trade-row" ] [
        Node.span ~attrs:[ Attr.class_ "trade-time" ] [ Node.text (Printf.sprintf "%.2f" t.time) ];
        Node.span ~attrs:[ Attr.class_ ("trade-price " ^ side_class) ] [ Node.text (Int.to_string t.price) ];
        Node.span ~attrs:[ Attr.class_ "trade-qty" ] [ Node.text (Int.to_string t.qty) ];
        Node.span ~attrs:[ Attr.class_ ("trade-side " ^ side_class) ] [ Node.text side_str ];
      ]))

(* --- DEPTH BOOK --- *)
let render_depth_book (model : Model.t) =
  let open Bonsai_web.Vdom in
  let asks_data, max_ask_qty = prepare_depth_data ~n:14 ~reverse:true model.asks in
  let bids_data, max_bid_qty = prepare_depth_data ~n:14 ~reverse:false model.bids in
  let global_max = Float.max max_ask_qty max_bid_qty in

  let ask_nodes =
    List.map asks_data ~f:(fun (price, qty) ->
      render_depth_row ~price ~qty ~max_qty:global_max ~is_ask:true)
    |> List.rev
  in

  let bid_nodes =
    List.map bids_data ~f:(fun (price, qty) ->
      render_depth_row ~price ~qty ~max_qty:global_max ~is_ask:false)
  in

  let (spread, spread_pct) =
    match Map.min_elt model.asks, Map.max_elt model.bids with
    | Some (ask_p, _), Some (bid_p, _) ->
        let sp = ask_p - bid_p in
        let mid = Float.of_int ((ask_p + bid_p) / 2) in
        let pct = (Float.of_int sp /. mid) *. 100. in
        (Int.to_string sp, Printf.sprintf "%.3f%%" pct)
    | _ -> ("N/A", "")
  in

  Node.div ~attrs:[ Attr.class_ "panel book-container" ] [
    Node.div ~attrs:[ Attr.class_ "panel-header" ] [
      Node.text "Limit Order Book (AAPL)";
      Node.span ~attrs:[ Attr.class_ "ph-badge" ] [ Node.text "L2" ];
    ];
    Node.div ~attrs:[ Attr.class_ "split-book-body" ] [
      Node.div ~attrs:[ Attr.class_ "bids-side" ] [
        Node.div ~attrs:[ Attr.class_ "book-col-header" ] [
          Node.span ~attrs:[ Attr.class_ "col-vol" ] [ Node.text "Volume" ];
          Node.span ~attrs:[ Attr.class_ "col-price" ] [ Node.text "Bid Price" ];
        ];
        Node.div ~attrs:[ Attr.class_ "bids-container" ] bid_nodes;
      ];
      Node.div ~attrs:[ Attr.class_ "asks-side" ] [
        Node.div ~attrs:[ Attr.class_ "book-col-header" ] [
          Node.span ~attrs:[ Attr.class_ "col-price" ] [ Node.text "Ask Price" ];
          Node.span ~attrs:[ Attr.class_ "col-vol" ] [ Node.text "Volume" ];
        ];
        Node.div ~attrs:[ Attr.class_ "asks-container" ] ask_nodes;
      ]
    ];
    Node.div ~attrs:[ Attr.class_ "spread-row" ] [
      Node.span ~attrs:[ Attr.class_ "spread-label" ] [ Node.text "Spread" ];
      Node.span ~attrs:[] [ Node.text spread ];
      Node.span ~attrs:[ Attr.class_ "spread-pct" ] [ Node.text spread_pct ];
    ];
  ]

(* --- MAIN COMPONENT --- *)
let component =
  let open Bonsai.Let_syntax in
  let book_ref = Order_book.create () in

  let%sub model, inject =
    Bonsai.state_machine0
      ~default_model:Model.empty
      ~apply_action:(fun context model action ->
        apply_action context model book_ref action)
      ()
  in

  let after_display =
    Bonsai_web.Bonsai.Value.map inject ~f:(fun inject ->
      Some (Ui_effect.of_sync_fun (fun () -> run_mock_feed inject) ()))
  in

  let%sub () = Bonsai_web.Bonsai.Edge.after_display' after_display in

  let%arr model = model and inject = inject in
  let open Bonsai_web.Vdom in

  Node.div ~attrs:[ Attr.class_ "dashboard" ] [
    Node.div ~attrs:[ Attr.class_ "dashboard-header" ] [
      Node.h1 ~attrs:[] [ Node.text "AERO-EXCHANGE: AAPL L2 ORDER BOOK" ];
      render_market_stats model;
    ];
    Node.div ~attrs:[ Attr.class_ "main-grid" ] [
      Node.div ~attrs:[ Attr.class_ "left-col" ] [
        render_controls model inject;
        render_order_entry model inject;
        render_trade_tape model;
      ];
      Node.div ~attrs:[ Attr.class_ "mid-col" ] [
        Node.div ~attrs:[ Attr.class_ "panel chart-panel" ] [
          Node.div ~attrs:[ Attr.class_ "panel-header" ] [
            Node.text "Price Chart — AAPL (Simulated)";
            Node.span ~attrs:[ Attr.class_ "ph-badge" ] [
              Node.text (Int.to_string (List.length model.price_history) ^ " ticks")
            ];
          ];
          render_svg_chart model.price_history;
        ];
        Node.div ~attrs:[ Attr.class_ "panel depth-visual-panel" ] [
          Node.div ~attrs:[ Attr.class_ "panel-header" ] [
            Node.text "Market Depth — Cumulative Volume";
            Node.span ~attrs:[ Attr.class_ "ph-badge" ] [ Node.text "Bid vs Ask" ];
          ];
          render_depth_visual ~asks:model.asks ~bids:model.bids ~width:400 ~height:200;
        ];
      ];
      Node.div ~attrs:[ Attr.class_ "right-col" ] [
        render_depth_book model;
      ];
    ]
  ]

let () =
  Bonsai_web.Start.start component
