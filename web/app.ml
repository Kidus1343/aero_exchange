open! Core
open! Bonsai_web
open! Js_of_ocaml
open Aero_lib.Types
open Aero_lib.Engine
open State
open Effects
open Ui

(* --- STATE REDUCER --- *)
let apply_action ~inject:_ ~schedule_event:_ (model : Model.t) book_ref action = match action with
  | Action.Reset ->
      Order_book.reset book_ref;
      Model.empty

  | Action.Process_Message msg ->
      let trades = (match Message.get_kind msg with
        | 1 -> Order_book.add_legacy book_ref msg
        | 2 | 3 | 4 | 5 -> Order_book.remove book_ref (Message.get_id msg); []
        | _ -> [])
      in
      Order_book.sync_maps book_ref;
      let new_mid = match trades with
        | t :: _ -> t.price
        | [] -> match Map.max_elt book_ref.bids, Map.min_elt book_ref.asks with
                | Some (b,_), Some (a,_) -> (b + a) / 2
                | _ -> model.base_mid
      in
      let history = List.take (new_mid :: model.price_history) 600 in
      { model with
        base_mid = new_mid;
        price_history = history;
        bids = book_ref.bids;
        asks = book_ref.asks;
        trades = List.rev trades @ model.trades
      }

  | Action.Place_Order msg ->
      let trades = Order_book.add_legacy book_ref msg in
      Order_book.sync_maps book_ref;
      let new_mid = match trades with
        | t :: _ -> t.price
        | [] -> match Map.max_elt book_ref.bids, Map.min_elt book_ref.asks with
                | Some (b,_), Some (a,_) -> (b + a) / 2
                | _ -> model.base_mid
      in
      let history = List.take (new_mid :: model.price_history) 600 in
      { model with
        base_mid = new_mid;
        price_history = history;
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
  | Action.Set_Order_Side side -> { model with order_side = side }
  | Action.Set_Order_Type typ -> { model with order_type = typ }
  | Action.Set_Price_Input p -> { model with price_input = p }
  | Action.Set_Qty_Input q -> { model with qty_input = q }
  | Action.Set_Ticker t -> { model with active_ticker = t }
  | Action.Set_Chart_Tab tab -> { model with chart_tab = tab }
  | Action.Select_Price_Level px ->
      { model with price_input = Int.to_string px }
  | Action.Submit_Cmd ->
      let cmd = String.strip model.cmd_input |> String.uppercase in
      let parts = String.split ~on:' ' cmd |> List.filter ~f:(fun s -> String.length s > 0) in
      let new_log, msg_opt =
        try
          match parts with
          | ["B"; qty; price] ->
              let q = Int.of_string qty in
              let p = Int.of_string price in
              let msg = Message.create ~time:(now_seconds ()) ~kind:1 ~id:(Random.int_incl 100000 999999) ~size:q ~price:p ~side:1 in
              ("✓ BUY " ^ qty ^ " @ " ^ price, Some msg)
          | ["S"; qty; price] ->
              let q = Int.of_string qty in
              let p = Int.of_string price in
              let msg = Message.create ~time:(now_seconds ()) ~kind:1 ~id:(Random.int_incl 100000 999999) ~size:q ~price:p ~side:2 in
              ("✓ SELL " ^ qty ^ " @ " ^ price, Some msg)
          | ["C"; id] ->
              let i = Int.of_string id in
              let msg = Message.create ~time:(now_seconds ()) ~kind:2 ~id:i ~size:0 ~price:0 ~side:0 in
              ("✓ CX " ^ id, Some msg)
          | _ -> ("✗ ERR: use B/S <qty> <px> or C <id>", None)
        with _ -> ("✗ ERR: parse failed", None)
      in
      let trades = match msg_opt with
        | Some m ->
            if Message.get_kind m = 1 then Order_book.add_legacy book_ref m
            else (Order_book.remove book_ref (Message.get_id m); [])
        | None -> []
      in
      Order_book.sync_maps book_ref;
      let log = List.take (new_log :: model.cmd_log) 8 in
      { model with
        cmd_input = "";
        cmd_log = log;
        bids = book_ref.bids;
        asks = book_ref.asks;
        trades = List.rev trades @ model.trades
      }

  | Action.Submit_Limit_Order ->
      let p_res = Or_error.try_with (fun () -> Int.of_string model.price_input) in
      let q_res = Or_error.try_with (fun () -> Int.of_string model.qty_input) in
      (match p_res, q_res with
       | Ok p, Ok q when p > 0 && q > 0 ->
           let side_code = match model.order_side with `Buy -> 1 | `Sell -> 2 in
           let side_str = match model.order_side with `Buy -> "BUY" | `Sell -> "SELL" in
           let msg = Message.create ~time:(now_seconds ()) ~kind:1 ~id:(Random.int_incl 100000 999999) ~size:q ~price:p ~side:side_code in
           let trades = Order_book.add_legacy book_ref msg in
           Order_book.sync_maps book_ref;
           let log_msg = Printf.sprintf "✓ EXECUTED %s %d @ %d" side_str q p in
           { model with
             cmd_log = List.take (log_msg :: model.cmd_log) 8;
             bids = book_ref.bids;
             asks = book_ref.asks;
             trades = List.rev trades @ model.trades
           }
       | _ ->
           { model with cmd_log = List.take ("✗ INVALID PRICE/QTY" :: model.cmd_log) 8 })

  | Action.Clear_Book ->
      Order_book.reset book_ref;
      { model with bids = Int.Map.empty; asks = Int.Map.empty; cmd_log = List.take ("✓ ORDER BOOK CLEARED" :: model.cmd_log) 8 }

  | Action.Trigger_Flash_Crash ->
      let new_mid = Int.max 1000 (model.base_mid - 150) in
      base_mid_ref := new_mid;
      (* Inject heavy aggressive sell order *)
      let msg = Message.create ~time:(now_seconds ()) ~kind:1 ~id:(Random.int_incl 100000 999999) ~size:500 ~price:(new_mid - 20) ~side:2 in
      let trades = Order_book.add_legacy book_ref msg in
      Order_book.sync_maps book_ref;
      let history = new_mid :: model.price_history in
      { model with
        base_mid = new_mid;
        price_history = history;
        cmd_log = List.take ("⚠ FLASH CRASH EVENT TRIGGERED (-150 ticks)" :: model.cmd_log) 8;
        bids = book_ref.bids;
        asks = book_ref.asks;
        trades = List.rev trades @ model.trades
      }

(* --- ORDER ENTRY DESK --- *)
let render_order_entry_desk (model : Model.t) inject =
  let open Bonsai_web.Vdom in
  let buy_active = match model.order_side with `Buy -> "active" | _ -> "" in
  let sell_active = match model.order_side with `Sell -> "active" | _ -> "" in
  let is_buy = match model.order_side with `Buy -> true | `Sell -> false in

  let quick_qty_btn qty_add =
    Node.button ~attrs:[
      Attr.class_ "qty-pill";
      Attr.on_click (fun _ ->
        let current = Option.value (Option.try_with (fun () -> Int.of_string model.qty_input)) ~default:0 in
        inject (Action.Set_Qty_Input (Int.to_string (current + qty_add))))
    ] [ Node.text ("+" ^ Int.to_string qty_add) ]
  in

  Node.div ~attrs:[ Attr.class_ "panel order-execution-desk" ] [
    Node.div ~attrs:[ Attr.class_ "panel-header" ] [
      Node.div ~attrs:[ Attr.class_ "ph-title" ] [ Node.text "Order Execution Desk" ];
      Node.span ~attrs:[ Attr.class_ "ph-badge" ] [ Node.text "Direct Matching" ];
    ];
    Node.div ~attrs:[ Attr.class_ "desk-body" ] [
      (* Side Switcher *)
      Node.div ~attrs:[ Attr.class_ "side-switcher" ] [
        Node.button ~attrs:[
          Attr.class_ ("btn-side btn-side-buy " ^ buy_active);
          Attr.on_click (fun _ -> inject (Action.Set_Order_Side `Buy))
        ] [ Node.text "BUY / LONG" ];
        Node.button ~attrs:[
          Attr.class_ ("btn-side btn-side-sell " ^ sell_active);
          Attr.on_click (fun _ -> inject (Action.Set_Order_Side `Sell))
        ] [ Node.text "SELL / SHORT" ];
      ];
      (* Input Form *)
      Node.div ~attrs:[ Attr.class_ "form-group" ] [
        Node.label ~attrs:[] [ Node.text "Limit Price (Ticks)" ];
        Node.input ~attrs:[
          Attr.type_ "number";
          Attr.class_ "form-input";
          Attr.value model.price_input;
          Attr.on_input (fun _ s -> inject (Action.Set_Price_Input s))
        ] ();
      ];
      Node.div ~attrs:[ Attr.class_ "form-group" ] [
        Node.div ~attrs:[ Attr.class_ "form-label-row" ] [
          Node.label ~attrs:[] [ Node.text "Order Quantity (Shares)" ];
          Node.div ~attrs:[ Attr.class_ "qty-pills" ] [
            quick_qty_btn 10; quick_qty_btn 50; quick_qty_btn 100; quick_qty_btn 500;
          ]
        ];
        Node.input ~attrs:[
          Attr.type_ "number";
          Attr.class_ "form-input";
          Attr.value model.qty_input;
          Attr.on_input (fun _ s -> inject (Action.Set_Qty_Input s))
        ] ();
      ];
      (* Big Submit Button *)
      Node.button ~attrs:[
        Attr.class_ ("btn-submit " ^ (if is_buy then "btn-submit-buy" else "btn-submit-sell"));
        Attr.on_click (fun _ -> inject Action.Submit_Limit_Order)
      ] [
        Node.text ((if is_buy then "SUBMIT BUY ORDER (" else "SUBMIT SELL ORDER (") ^ model.qty_input ^ " @ " ^ model.price_input ^ ")")
      ];
    ]
  ]

(* --- SCENARIO & SPEED CONTROL DECK --- *)
let render_control_deck (model : Model.t) inject =
  let open Bonsai_web.Vdom in
  let pause_label = if model.running then "⏸ PAUSE FEED" else "▶ RESUME FEED" in
  let pause_class = if model.running then "btn-pause" else "btn-resume" in

  let speed_btn label spd =
    let active = if model.speed = spd then "active" else "" in
    Node.button ~attrs:[
      Attr.class_ ("btn-speed " ^ active);
      Attr.on_click (fun _ -> Ui_effect.of_sync_fun (fun () -> adjust_speed inject (spd - model.speed)) ())
    ] [ Node.text label ]
  in

  Node.div ~attrs:[ Attr.class_ "panel control-deck" ] [
    Node.div ~attrs:[ Attr.class_ "panel-header" ] [
      Node.div ~attrs:[ Attr.class_ "ph-title" ] [ Node.text "Engine Deck & Scenarios" ];
      Node.span ~attrs:[ Attr.class_ "ph-badge" ] [ Node.text (Printf.sprintf "%d ms Feed" model.speed) ];
    ];
    Node.div ~attrs:[ Attr.class_ "deck-body" ] [
      Node.div ~attrs:[ Attr.class_ "deck-row" ] [
        Node.button ~attrs:[
          Attr.class_ ("btn-action " ^ pause_class);
          Attr.on_click (fun _ -> Ui_effect.of_sync_fun (fun () -> toggle_running inject model) ())
        ] [ Node.text pause_label ];
        Node.button ~attrs:[
          Attr.class_ "btn-action btn-danger";
          Attr.on_click (fun _ -> inject Action.Clear_Book)
        ] [ Node.text "CLEAR BOOK" ];
      ];
      Node.div ~attrs:[ Attr.class_ "deck-row-label" ] [ Node.text "Feed Simulation Speed:" ];
      Node.div ~attrs:[ Attr.class_ "speed-btn-group" ] [
        speed_btn "1x (200ms)" 200;
        speed_btn "2x (100ms)" 100;
        speed_btn "5x (40ms)" 40;
        speed_btn "MAX (10ms)" 10;
      ];
      Node.div ~attrs:[ Attr.class_ "deck-row-label" ] [ Node.text "Stress Test Scenarios:" ];
      Node.div ~attrs:[ Attr.class_ "deck-row" ] [
        Node.button ~attrs:[
          Attr.class_ "btn-scenario btn-flash-crash";
          Attr.on_click (fun _ -> inject Action.Trigger_Flash_Crash)
        ] [ Node.text "⚡ TRIGGER FLASH CRASH" ];
      ];
    ]
  ]

(* --- CLI AUDIT LOG --- *)
let render_cli_log (model : Model.t) inject =
  let open Bonsai_web.Vdom in
  Node.div ~attrs:[ Attr.class_ "panel cli-audit-panel" ] [
    Node.div ~attrs:[ Attr.class_ "panel-header" ] [
      Node.div ~attrs:[ Attr.class_ "ph-title" ] [ Node.text "CLI Terminal Audit" ];
      Node.span ~attrs:[ Attr.class_ "ph-badge" ] [ Node.text "B/S <qty> <px> | C <id>" ];
    ];
    Node.div ~attrs:[ Attr.class_ "cli-log-terminal" ] (
      List.map model.cmd_log ~f:(fun line ->
        let line_class =
          if String.is_prefix line ~prefix:"✓" then "log-success"
          else if String.is_prefix line ~prefix:"⚠" then "log-warn"
          else if String.is_prefix line ~prefix:"✗" then "log-err"
          else "log-info"
        in
        Node.div ~attrs:[ Attr.class_ ("log-line " ^ line_class) ] [ Node.text line ])
    );
    Node.input ~attrs:[
      Attr.type_ "text";
      Attr.class_ "cli-terminal-input";
      Attr.placeholder "> Type command (e.g. B 100 50050)";
      Attr.value model.cmd_input;
      Attr.on_input (fun _ s -> inject (Action.Set_Cmd_Input s));
      Attr.on_keydown (fun ev ->
        if ev##.keyCode = 13 then inject Action.Submit_Cmd
        else Ui_effect.Ignore)
    ] ();
  ]

(* --- TIME & SALES TAPE --- *)
let render_trade_tape (model : Model.t) =
  let open Bonsai_web.Vdom in
  Node.div ~attrs:[ Attr.class_ "panel trade-tape" ] (
    [ Node.div ~attrs:[ Attr.class_ "panel-header" ] [
        Node.div ~attrs:[ Attr.class_ "ph-title" ] [ Node.text "Time & Sales (Tape)" ];
        Node.span ~attrs:[ Attr.class_ "ph-badge" ] [
          Node.text (Int.to_string (List.length model.trades) ^ " fills")
        ];
      ];
      Node.div ~attrs:[ Attr.class_ "tape-col-header" ] [
        Node.span ~attrs:[] [ Node.text "Time" ];
        Node.span ~attrs:[] [ Node.text "Price" ];
        Node.span ~attrs:[] [ Node.text "Qty" ];
        Node.span ~attrs:[] [ Node.text "Aggressor" ];
      ];
    ] @
    List.map (List.take model.trades 60) ~f:(fun t ->
      let side_str = match t.side with `Buy -> "BUY" | `Sell -> "SELL" in
      let side_class = match t.side with `Buy -> "buy" | `Sell -> "sell" in
      Node.div ~attrs:[ Attr.class_ "trade-row" ] [
        Node.span ~attrs:[ Attr.class_ "trade-time" ] [ Node.text (Printf.sprintf "%.2f" t.time) ];
        Node.span ~attrs:[ Attr.class_ ("trade-price " ^ side_class) ] [ Node.text (Int.to_string t.price) ];
        Node.span ~attrs:[ Attr.class_ "trade-qty" ] [ Node.text (Int.to_string t.qty) ];
        Node.span ~attrs:[ Attr.class_ ("trade-side " ^ side_class) ] [ Node.text side_str ];
      ]))

(* --- MAIN COMPONENT --- *)
let component =
  let open Bonsai.Let_syntax in
  let book_ref = Order_book.create () in

  let%sub model, inject =
    Bonsai.state_machine0
      (module Model)
      (module Action)
      ~default_model:Model.empty
      ~apply_action:(fun ~inject ~schedule_event model action ->
        apply_action ~inject ~schedule_event model book_ref action)
  in

  let after_display =
    Bonsai_web.Bonsai.Value.map inject ~f:(fun inject ->
      Some (Ui_effect.of_sync_fun (fun () -> run_mock_feed inject) ()))
  in

  let%sub () = Bonsai_web.Bonsai.Edge.after_display' after_display in

  let%arr model = model and inject = inject in
  let open Bonsai_web.Vdom in

  let ticker_tab name =
    let active = if String.equal model.active_ticker name then "active" else "" in
    Node.button ~attrs:[
      Attr.class_ ("ticker-tab " ^ active);
      Attr.on_click (fun _ -> inject (Action.Set_Ticker name))
    ] [ Node.text name ]
  in

  let chart_tab_btn label tab_val =
    let active = match model.chart_tab, tab_val with
      | `Line, `Line -> "active"
      | `Depth, `Depth -> "active"
      | _ -> ""
    in
    Node.button ~attrs:[
      Attr.class_ ("tab-btn " ^ active);
      Attr.on_click (fun _ -> inject (Action.Set_Chart_Tab tab_val))
    ] [ Node.text label ]
  in

  Node.div ~attrs:[ Attr.class_ "dashboard" ] [
    (* HEADER BAR *)
    Node.div ~attrs:[ Attr.class_ "dashboard-header" ] [
      Node.div ~attrs:[ Attr.class_ "brand-section" ] [
        Node.div ~attrs:[ Attr.class_ "brand-logo" ] [ Node.text "AERO-EXCHANGE" ];
        Node.div ~attrs:[ Attr.class_ "status-pill" ] [
          Node.span ~attrs:[ Attr.class_ "pulse-dot" ] [];
          Node.text "O(1) MATCHING ONLINE"
        ];
      ];
      Node.div ~attrs:[ Attr.class_ "ticker-tabs" ] [
        ticker_tab "AAPL"; ticker_tab "TSLA"; ticker_tab "NVDA"; ticker_tab "BTC/USD";
      ];
      render_market_stats model;
    ];

    (* MAIN GRID LAYOUT *)
    Node.div ~attrs:[ Attr.class_ "main-grid" ] [
      (* LEFT COLUMN *)
      Node.div ~attrs:[ Attr.class_ "left-col" ] [
        render_order_entry_desk model inject;
        render_control_deck model inject;
        render_cli_log model inject;
        render_trade_tape model;
      ];

      (* MIDDLE COLUMN *)
      Node.div ~attrs:[ Attr.class_ "mid-col" ] [
        Node.div ~attrs:[ Attr.class_ "panel chart-panel" ] [
          Node.div ~attrs:[ Attr.class_ "panel-header" ] [
            Node.div ~attrs:[ Attr.class_ "ph-title" ] [
              Node.text (model.active_ticker ^ " — Real-Time Streaming Chart");
            ];
            Node.div ~attrs:[ Attr.class_ "chart-tab-group" ] [
              chart_tab_btn "Price Trend" `Line;
              chart_tab_btn "Depth Wall" `Depth;
            ];
          ];
          (match model.chart_tab with
           | `Line -> render_svg_chart model.price_history
           | `Depth -> render_depth_visual ~asks:model.asks ~bids:model.bids);
        ];
      ];

      (* RIGHT COLUMN *)
      Node.div ~attrs:[ Attr.class_ "right-col" ] [
        render_depth_book model inject;
      ];
    ]
  ]

let () =
  Bonsai_web.Start.start component
