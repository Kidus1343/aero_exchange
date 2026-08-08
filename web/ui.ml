open! Core
open! Bonsai_web
open Aero_lib.Types
open State

(* --- HELPERS --- *)

let prepare_depth_data ~n ~reverse map =
  let alist = Map.to_alist map in
  let sorted = if reverse then List.rev alist else alist in
  let levels = List.take sorted n in
  let max_qty =
    List.fold levels ~init:0 ~f:(fun acc (_, qty) -> Int.max acc qty)
    |> float_of_int
  in
  (levels, max_qty)

let render_depth_row ~price ~qty ~max_qty ~is_ask inject =
  let open Bonsai_web.Vdom in
  let pct = if Float.(max_qty = 0.) then 0. else (float_of_int qty /. max_qty) *. 100. in
  let bar_class = if is_ask then "bar-ask" else "bar-bid" in
  Node.div ~attrs:[
    Attr.class_ "depth-row";
    Attr.on_click (fun _ -> inject (Action.Select_Price_Level price));
    Attr.title "Click level to auto-fill price"
  ] [
    Node.div ~attrs:[
      Attr.class_ ("depth-bar " ^ bar_class);
      Attr.style (Css_gen.width (`Percent (Percent.of_percentage pct)))
    ] [];
    Node.span ~attrs:[ Attr.class_ "price" ] [ Node.text (Int.to_string price) ];
    Node.span ~attrs:[ Attr.class_ "qty" ] [ Node.text (Int.to_string qty) ];
  ]

let cumulative_levels levels =
  let rec go acc_sum acc = function
    | [] -> List.rev acc
    | (p,q)::rest ->
      let sum = acc_sum + q in
      go sum ((p,sum)::acc) rest
  in
  go 0 [] levels

(* ===== MARKET DEPTH VISUAL ===== *)
let render_depth_visual ~asks ~bids =
  let open Bonsai_web.Vdom in
  let asks_al, _ = prepare_depth_data ~n:20 ~reverse:false asks in
  let bids_al, _ = prepare_depth_data ~n:20 ~reverse:true bids in
  let asks_c = cumulative_levels asks_al in
  let bids_c = cumulative_levels bids_al in
  let max_c = List.fold (asks_c @ bids_c) ~init:0 ~f:(fun acc (_,v) -> Int.max acc v) in
  let to_bar ~is_ask (_p, c) =
    let pct = if max_c = 0 then 0. else (Float.of_int c /. Float.of_int max_c) *. 100. in
    let bg_class = if is_ask then "ask" else "bid" in
    Node.div ~attrs:[ Attr.class_ "depth-vis-bar-wrapper" ] [
      Node.div ~attrs:[
        Attr.style (Css_gen.height (`Percent (Percent.of_percentage pct)));
        Attr.class_ ("depth-vis-bar-fill " ^ bg_class)
      ] [];
    ]
  in
  let best_bid_str = match List.hd bids_al with Some (p,_) -> Int.to_string p | None -> "N/A" in
  let best_ask_str = match List.hd asks_al with Some (p,_) -> Int.to_string p | None -> "N/A" in
  let max_vol_str = Int.to_string max_c in
  let ask_nodes = List.map asks_c ~f:(to_bar ~is_ask:true) in
  let bid_nodes = List.map bids_c ~f:(to_bar ~is_ask:false) in
  Node.div ~attrs:[ Attr.class_ "depth-visual-wrapper" ] [
    Node.div ~attrs:[ Attr.class_ "depth-vis-chart-area" ] [
      Node.div ~attrs:[ Attr.class_ "depth-vis-half depth-vis-left" ] bid_nodes;
      Node.div ~attrs:[ Attr.class_ "depth-axis-bar" ] [];
      Node.div ~attrs:[ Attr.class_ "depth-vis-half depth-vis-right" ] ask_nodes;
    ];
    Node.div ~attrs:[ Attr.class_ "depth-vis-y-axis" ] [
      Node.span ~attrs:[] [ Node.text max_vol_str ];
      Node.span ~attrs:[] [ Node.text "" ];
      Node.span ~attrs:[] [ Node.text "0" ];
    ];
    Node.div ~attrs:[ Attr.class_ "depth-vis-x-axis" ] [
      Node.span ~attrs:[ Attr.class_ "label-bid" ] [ Node.text ("Bid " ^ best_bid_str) ];
      Node.span ~attrs:[ Attr.class_ "label-mid" ] [ Node.text "Cum. Depth Wall" ];
      Node.span ~attrs:[ Attr.class_ "label-ask" ] [ Node.text ("Ask " ^ best_ask_str) ];
    ];
  ]

(* ===== PRICE CHART ===== *)
let render_svg_chart price_history =
  let open Bonsai_web.Vdom in
  match price_history with
  | [] ->
    Node.div ~attrs:[ Attr.class_ "chart-wrapper" ] [
      Node.div ~attrs:[ Attr.class_ "chart-y-axis" ] [];
      Node.create_svg "svg" ~attrs:[
        Attr.class_ "price-chart-svg";
        Attr.create "viewBox" "0 0 600 200";
        Attr.create "preserveAspectRatio" "none";
      ] [
        Node.create_svg "text" ~attrs:[
          Attr.create "x" "300"; Attr.create "y" "100";
          Attr.create "text-anchor" "middle";
          Attr.create "fill" "#64748b"; Attr.create "font-size" "13";
          Attr.create "font-family" "monospace";
        ] [ Node.text "Streaming Market Data..." ]
      ]
    ]
  | prices ->
    let prices = List.rev prices in
    let n = List.length prices in
    let raw_max = List.max_elt prices ~compare:Int.compare |> Option.value ~default:0 in
    let raw_min = List.min_elt prices ~compare:Int.compare |> Option.value ~default:0 in
    let (min_p, max_p) =
      if raw_max - raw_min < 20 then (raw_min - 20, raw_max + 20)
      else (raw_min, raw_max)
    in
    let range = Float.of_int (Int.max 1 (max_p - min_p)) in

    let w = 600. in
    let h = 200. in
    let pad_l = 2. in
    let pad_t = 8. in
    let pad_b = 28. in
    let chart_w = w -. pad_l in
    let chart_h = h -. pad_t -. pad_b in

    let dx = chart_w /. Float.of_int (Int.max 1 (n - 1)) in

    let price_to_y p =
      let pct = (Float.of_int (p - min_p)) /. range in
      pad_t +. chart_h -. (pct *. chart_h)
    in

    let path_d =
      prices
      |> List.mapi ~f:(fun i p ->
        let x = pad_l +. Float.of_int i *. dx in
        let y = price_to_y p in
        if i = 0 then Printf.sprintf "M %.1f %.1f" x y
        else Printf.sprintf "L %.1f %.1f" x y)
      |> String.concat ~sep:" "
    in

    let fill_d = Printf.sprintf "%s L %.1f %.1f L %.1f %.1f Z"
      path_d (pad_l +. chart_w) (pad_t +. chart_h) pad_l (pad_t +. chart_h)
    in

    let y_ticks =
      List.init 5 ~f:(fun i ->
        let frac = Float.of_int i /. 4. in
        let price_at = min_p + (Float.to_int (frac *. range)) in
        let y = pad_t +. chart_h -. (frac *. chart_h) in
        (price_at, y)
      )
    in

    let y_grid_lines = List.map y_ticks ~f:(fun (_p, y) ->
      Node.create_svg "line" ~attrs:[
        Attr.create "x1" (Float.to_string pad_l);
        Attr.create "y1" (Printf.sprintf "%.1f" y);
        Attr.create "x2" (Float.to_string (pad_l +. chart_w));
        Attr.create "y2" (Printf.sprintf "%.1f" y);
        Attr.create "stroke" "#1e293b";
        Attr.create "stroke-width" "1";
      ] []
    ) in

    let x_ticks = [
      (0., "Start");
      (chart_w *. 0.33, "-400 Ticks");
      (chart_w *. 0.66, "-200 Ticks");
      (chart_w, "LIVE");
    ] in

    let x_labels = List.map x_ticks ~f:(fun (x_off, label) ->
      let anchor = if Float.(x_off = 0.) then "start" else if Float.(x_off = chart_w) then "end" else "middle" in
      Node.create_svg "text" ~attrs:[
        Attr.create "x" (Printf.sprintf "%.1f" (pad_l +. x_off));
        Attr.create "y" (Printf.sprintf "%.1f" (h -. 6.));
        Attr.create "text-anchor" anchor;
        Attr.create "fill" "#64748b";
        Attr.create "font-size" "9";
        Attr.create "font-family" "monospace";
      ] [ Node.text label ]
    ) in

    let current_price = List.last prices |> Option.value ~default:0 in
    let current_y = price_to_y current_price in

    let y_label_nodes = List.map (List.rev y_ticks) ~f:(fun (p, _) ->
      Node.div ~attrs:[ Attr.class_ "chart-y-label" ] [ Node.text (Int.to_string p) ]
    ) in

    Node.div ~attrs:[ Attr.class_ "chart-wrapper" ] [
      Node.div ~attrs:[ Attr.class_ "chart-y-axis" ] y_label_nodes;
      Node.create_svg "svg" ~attrs:[
        Attr.class_ "price-chart-svg";
        Attr.create "viewBox" (Printf.sprintf "0 0 %d %d" (Float.to_int w) (Float.to_int h));
        Attr.create "preserveAspectRatio" "none";
      ] (List.concat [
        y_grid_lines;
        [
          Node.create_svg "defs" ~attrs:[] [
            Node.create_svg "linearGradient" ~attrs:[
              Attr.id "chart-grad"; Attr.create "x1" "0"; Attr.create "y1" "0";
              Attr.create "x2" "0"; Attr.create "y2" "1"
            ] [
              Node.create_svg "stop" ~attrs:[Attr.create "offset" "0%"; Attr.create "stop-color" "rgba(56,189,248,0.25)"] [];
              Node.create_svg "stop" ~attrs:[Attr.create "offset" "100%"; Attr.create "stop-color" "rgba(56,189,248,0.0)"] []
            ]
          ];
          Node.create_svg "path" ~attrs:[
            Attr.create "d" fill_d;
            Attr.create "fill" "url(#chart-grad)";
          ] [];
          Node.create_svg "path" ~attrs:[
            Attr.create "d" path_d;
            Attr.create "fill" "none";
            Attr.create "stroke" "#38bdf8";
            Attr.create "stroke-width" "1.8";
            Attr.create "stroke-linejoin" "round";
            Attr.create "stroke-linecap" "round";
          ] [];
          Node.create_svg "line" ~attrs:[
            Attr.create "x1" (Float.to_string pad_l);
            Attr.create "y1" (Printf.sprintf "%.1f" current_y);
            Attr.create "x2" (Float.to_string (pad_l +. chart_w));
            Attr.create "y2" (Printf.sprintf "%.1f" current_y);
            Attr.create "stroke" "#38bdf8";
            Attr.create "stroke-width" "1";
            Attr.create "stroke-dasharray" "4,4";
            Attr.create "opacity" "0.6";
          ] [];
          Node.create_svg "rect" ~attrs:[
            Attr.create "x" (Printf.sprintf "%.1f" (pad_l +. chart_w -. 55.));
            Attr.create "y" (Printf.sprintf "%.1f" (current_y -. 8.));
            Attr.create "width" "55"; Attr.create "height" "14";
            Attr.create "fill" "#38bdf8"; Attr.create "rx" "3";
          ] [];
          Node.create_svg "text" ~attrs:[
            Attr.create "x" (Printf.sprintf "%.1f" (pad_l +. chart_w -. 27.5));
            Attr.create "y" (Printf.sprintf "%.1f" (current_y +. 3.));
            Attr.create "text-anchor" "middle";
            Attr.create "fill" "#0f172a";
            Attr.create "font-size" "10";
            Attr.create "font-weight" "bold";
            Attr.create "font-family" "monospace";
          ] [ Node.text (Int.to_string current_price) ];
          Node.create_svg "line" ~attrs:[
            Attr.create "x1" (Float.to_string pad_l);
            Attr.create "y1" (Float.to_string (pad_t +. chart_h));
            Attr.create "x2" (Float.to_string (pad_l +. chart_w));
            Attr.create "y2" (Float.to_string (pad_t +. chart_h));
            Attr.create "stroke" "#334155";
            Attr.create "stroke-width" "1";
          ] [];
        ];
        x_labels;
      ])
    ]

(* ===== MARKET STATS & ENGINE TELEMETRY BAR ===== *)
let render_market_stats (model : Model.t) =
  let open Bonsai_web.Vdom in
  let best_bid = Option.map (Map.max_elt model.bids) ~f:fst in
  let best_ask = Option.map (Map.min_elt model.asks) ~f:fst in
  let spread_val = match best_bid, best_ask with
    | Some b, Some a -> a - b
    | _ -> 0
  in
  let total_bid_vol = Map.fold model.bids ~init:0 ~f:(fun ~key:_ ~data acc -> acc + data) in
  let total_ask_vol = Map.fold model.asks ~init:0 ~f:(fun ~key:_ ~data acc -> acc + data) in
  let total_vol = total_bid_vol + total_ask_vol in
  let bid_pct = if total_vol = 0 then 50. else (Float.of_int total_bid_vol /. Float.of_int total_vol) *. 100. in
  let last_trade_price = match model.trades with t :: _ -> Int.to_string t.price | [] -> "N/A" in

  Node.div ~attrs:[ Attr.class_ "market-stats-container" ] [
    Node.div ~attrs:[ Attr.class_ "telemetry-card" ] [
      Node.div ~attrs:[ Attr.class_ "t-label" ] [ Node.text "Matching Latency" ];
      Node.div ~attrs:[ Attr.class_ "t-val highlight-green" ] [ Node.text "265 ns" ];
      Node.div ~attrs:[ Attr.class_ "t-sub" ] [ Node.text "O(1) Zero-Alloc" ];
    ];
    Node.div ~attrs:[ Attr.class_ "telemetry-card" ] [
      Node.div ~attrs:[ Attr.class_ "t-label" ] [ Node.text "Engine Throughput" ];
      Node.div ~attrs:[ Attr.class_ "t-val highlight-cyan" ] [ Node.text "3.77M /s" ];
      Node.div ~attrs:[ Attr.class_ "t-sub" ] [ Node.text "301,587 dataset" ];
    ];
    Node.div ~attrs:[ Attr.class_ "telemetry-card" ] [
      Node.div ~attrs:[ Attr.class_ "t-label" ] [ Node.text "Best Bid / Ask" ];
      Node.div ~attrs:[ Attr.class_ "t-val" ] [
        Node.span ~attrs:[ Attr.class_ "bid-text" ] [ Node.text (Option.value_map best_bid ~default:"N/A" ~f:Int.to_string) ];
        Node.span ~attrs:[ Attr.class_ "sep" ] [ Node.text " / " ];
        Node.span ~attrs:[ Attr.class_ "ask-text" ] [ Node.text (Option.value_map best_ask ~default:"N/A" ~f:Int.to_string) ];
      ];
      Node.div ~attrs:[ Attr.class_ "t-sub" ] [ Node.text ("Spread: " ^ Int.to_string spread_val ^ " ticks") ];
    ];
    Node.div ~attrs:[ Attr.class_ "telemetry-card" ] [
      Node.div ~attrs:[ Attr.class_ "t-label" ] [ Node.text "Last Fill Price" ];
      Node.div ~attrs:[ Attr.class_ "t-val" ] [ Node.text last_trade_price ];
      Node.div ~attrs:[ Attr.class_ "t-sub" ] [ Node.text ("Mid: " ^ Int.to_string model.base_mid) ];
    ];
    Node.div ~attrs:[ Attr.class_ "telemetry-card imbalance-card" ] [
      Node.div ~attrs:[ Attr.class_ "t-label" ] [ Node.text "Book Imbalance" ];
      Node.div ~attrs:[ Attr.class_ "imbalance-bar-wrapper" ] [
        Node.div ~attrs:[
          Attr.class_ "imbalance-bid-fill";
          Attr.style (Css_gen.width (`Percent (Percent.of_percentage bid_pct)))
        ] [];
      ];
      Node.div ~attrs:[ Attr.class_ "t-sub imbalance-text" ] [
        Node.text (Printf.sprintf "%.1f%% Bid | %.1f%% Ask" bid_pct (100. -. bid_pct))
      ];
    ];
  ]

let render_depth_book (model : Model.t) inject =
  let open Bonsai_web.Vdom in
  let asks_data, max_ask_qty = prepare_depth_data ~n:15 ~reverse:true model.asks in
  let bids_data, max_bid_qty = prepare_depth_data ~n:15 ~reverse:false model.bids in
  let global_max = Float.max max_ask_qty max_bid_qty in

  let ask_nodes =
    List.map asks_data ~f:(fun (price, qty) ->
      render_depth_row ~price ~qty ~max_qty:global_max ~is_ask:true inject)
    |> List.rev
  in

  let bid_nodes =
    List.map bids_data ~f:(fun (price, qty) ->
      render_depth_row ~price ~qty ~max_qty:global_max ~is_ask:false inject)
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
      Node.div ~attrs:[ Attr.class_ "ph-title" ] [ Node.text "Order Book (L2 Market Depth)" ];
      Node.span ~attrs:[ Attr.class_ "ph-badge" ] [ Node.text "Click level to trade" ];
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
      Node.span ~attrs:[ Attr.class_ "spread-label" ] [ Node.text "BBO Spread" ];
      Node.span ~attrs:[ Attr.class_ "spread-val" ] [ Node.text spread ];
      Node.span ~attrs:[ Attr.class_ "spread-pct" ] [ Node.text spread_pct ];
    ];
  ]
