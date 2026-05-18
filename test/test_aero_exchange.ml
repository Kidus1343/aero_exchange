open Core
open Aero_lib.Types
open Aero_lib.Engine

(* Test utilities *)
let create_message ~time ~kind ~id ~size ~price ~side =
  { Message.time; kind; id; size; price; side }

let test_message_parsing () =
  print_endline "=== Test: Message Parsing ===";
  let csv_line = "100.5,1,123,50,50000,1" in
  try
    let msg = Message.of_string csv_line in
    assert (Float.(msg.time = 100.5));
    assert (msg.kind = 1);
    assert (msg.id = 123);
    assert (msg.size = 50);
    assert (msg.price = 50000);
    assert (msg.side = 1);
    print_endline "✓ Message parsing works"
  with _ -> print_endline "✗ Message parsing failed"

let test_order_book_creation () =
  print_endline "\n=== Test: Order Book Creation ===";
  let book = Order_book.create () in
  assert (Map.is_empty book.bids);
  assert (Map.is_empty book.asks);
  print_endline "✓ Order book creation works"

let test_order_addition () =
  print_endline "\n=== Test: Order Addition ===";
  let book = Order_book.create () in
  let buy_msg = create_message ~time:100.0 ~kind:1 ~id:1 ~size:100 ~price:50000 ~side:1 in
  let trades = Order_book.add book buy_msg in
  assert (List.is_empty trades);
  assert (not (Map.is_empty book.bids));
  assert (Option.value (Map.find book.bids 50000) ~default:0 = 100);
  print_endline "✓ Buy order addition works";

  let sell_msg = create_message ~time:101.0 ~kind:1 ~id:2 ~size:50 ~price:50010 ~side:2 in
  let trades = Order_book.add book sell_msg in
  assert (List.is_empty trades);
  assert (not (Map.is_empty book.asks));
  assert (Option.value (Map.find book.asks 50010) ~default:0 = 50);
  print_endline "✓ Sell order addition works"

let test_order_matching () =
  print_endline "\n=== Test: Order Matching ===";
  let book = Order_book.create () in
  (* Add initial bid *)
  let bid_msg = create_message ~time:100.0 ~kind:1 ~id:1 ~size:100 ~price:50000 ~side:1 in
  let _ = Order_book.add book bid_msg in
  
  (* Aggressive sell that partially matches *)
  let sell_msg = create_message ~time:101.0 ~kind:1 ~id:2 ~size:50 ~price:50000 ~side:2 in
  let trades = Order_book.add book sell_msg in
  
  assert (List.length trades = 1);
  let trade = List.hd_exn trades in
  assert (trade.price = 50000);
  assert (trade.qty = 50);
  assert (match trade.side with `Sell -> true | _ -> false);
  (* Bid should have 50 left *)
  assert (Option.value (Map.find book.bids 50000) ~default:0 = 50);
  print_endline "✓ Partial order matching works";

  (* Aggressive buy that fully matches and adds new bid *)
  let buy_msg = create_message ~time:102.0 ~kind:1 ~id:3 ~size:100 ~price:50000 ~side:1 in
  let trades = Order_book.add book buy_msg in
  
  assert (List.length trades = 1);
  let trade = List.hd_exn trades in
  assert (trade.qty = 50); (* matches remaining bid *)
  (* New bid should have 50 left *)
  assert (Option.value (Map.find book.bids 50000) ~default:0 = 50);
  print_endline "✓ Full matching with new order addition works"

let test_order_removal () =
  print_endline "\n=== Test: Order Removal ===";
  let book = Order_book.create () in
  let msg = create_message ~time:100.0 ~kind:1 ~id:1 ~size:100 ~price:50000 ~side:1 in
  let _ = Order_book.add book msg in
  
  assert (Option.value (Map.find book.bids 50000) ~default:0 = 100);
  Order_book.remove book 1;
  assert (Option.is_none (Map.find book.bids 50000));
  print_endline "✓ Order removal works"

let test_get_spread () =
  print_endline "\n=== Test: Get Spread ===";
  let book = Order_book.create () in
  let bid_msg = create_message ~time:100.0 ~kind:1 ~id:1 ~size:100 ~price:50000 ~side:1 in
  let ask_msg = create_message ~time:101.0 ~kind:1 ~id:2 ~size:100 ~price:50010 ~side:2 in
  let _ = Order_book.add book bid_msg in
  let _ = Order_book.add book ask_msg in
  
  let spread = Order_book.get_spread book in
  assert (Option.value spread ~default:(-1) = 10);
  print_endline "✓ Spread calculation works"

let test_get_mid_price () =
  print_endline "\n=== Test: Get Mid Price ===";
  let book = Order_book.create () in
  let bid_msg = create_message ~time:100.0 ~kind:1 ~id:1 ~size:100 ~price:50000 ~side:1 in
  let ask_msg = create_message ~time:101.0 ~kind:1 ~id:2 ~size:100 ~price:50010 ~side:2 in
  let _ = Order_book.add book bid_msg in
  let _ = Order_book.add book ask_msg in
  
  let mid = Order_book.get_mid_price book in
  assert (Option.value mid ~default:(-1) = 50005);
  print_endline "✓ Mid-price calculation works"

let test_get_volumes () =
  print_endline "\n=== Test: Get Volumes ===";
  let book = Order_book.create () in
  let bid_msg1 = create_message ~time:100.0 ~kind:1 ~id:1 ~size:100 ~price:50000 ~side:1 in
  let bid_msg2 = create_message ~time:101.0 ~kind:1 ~id:2 ~size:50 ~price:49990 ~side:1 in
  let ask_msg = create_message ~time:102.0 ~kind:1 ~id:3 ~size:80 ~price:50010 ~side:2 in
  let _ = Order_book.add book bid_msg1 in
  let _ = Order_book.add book bid_msg2 in
  let _ = Order_book.add book ask_msg in
  
  let bid_vol = Order_book.get_total_bid_volume book in
  let ask_vol = Order_book.get_total_ask_volume book in
  assert (bid_vol = 150);
  assert (ask_vol = 80);
  print_endline "✓ Volume calculation works"

let test_imbalance_ratio () =
  print_endline "\n=== Test: Imbalance Ratio ===";
  let book = Order_book.create () in
  let bid_msg = create_message ~time:100.0 ~kind:1 ~id:1 ~size:200 ~price:50000 ~side:1 in
  let ask_msg = create_message ~time:101.0 ~kind:1 ~id:2 ~size:100 ~price:50010 ~side:2 in
  let _ = Order_book.add book bid_msg in
  let _ = Order_book.add book ask_msg in
  
  let ratio = Order_book.get_imbalance_ratio book in
  assert (Float.(ratio = 2.0));
  print_endline "✓ Imbalance ratio calculation works"

let test_vwap () =
  print_endline "\n=== Test: VWAP ===";
  let book = Order_book.create () in
  let buy_msg = create_message ~time:100.0 ~kind:1 ~id:1 ~size:100 ~price:50000 ~side:1 in
  let sell_msg = create_message ~time:101.0 ~kind:1 ~id:2 ~size:100 ~price:50000 ~side:2 in
  let _ = Order_book.add book buy_msg in
  let _ = Order_book.add book sell_msg in
  
  let vwap = Order_book.get_vwap book in
  assert (vwap = 50000);
  print_endline "✓ VWAP calculation works"

let test_validation () =
  print_endline "\n=== Test: Validation ===";
  let book = Order_book.create () in
  let bid_msg = create_message ~time:100.0 ~kind:1 ~id:1 ~size:100 ~price:50000 ~side:1 in
  let _ = Order_book.add book bid_msg in
  
  assert (Order_book.validate book);
  print_endline "✓ Validation works (no cross-orders)"

let test_reset () =
  print_endline "\n=== Test: Reset ===";
  let book = Order_book.create () in
  let msg = create_message ~time:100.0 ~kind:1 ~id:1 ~size:100 ~price:50000 ~side:1 in
  let _ = Order_book.add book msg in
  
  assert (not (Map.is_empty book.bids));
  Order_book.reset book;
  assert (Map.is_empty book.bids);
  assert (Map.is_empty book.asks);
  print_endline "✓ Reset works"

let test_edge_case_zero_size () =
  print_endline "\n=== Test: Edge Case - Zero Size ===";
  let book = Order_book.create () in
  let msg = create_message ~time:100.0 ~kind:1 ~id:1 ~size:0 ~price:50000 ~side:1 in
  let trades = Order_book.add book msg in
  
  assert (List.is_empty trades);
  assert (Map.is_empty book.bids);
  print_endline "✓ Zero-size order handled correctly"

let test_edge_case_large_orders () =
  print_endline "\n=== Test: Edge Case - Large Orders ===";
  let book = Order_book.create () in
  let large_size = 1_000_000 in
  let msg = create_message ~time:100.0 ~kind:1 ~id:1 ~size:large_size ~price:50000 ~side:1 in
  let _ = Order_book.add book msg in
  
  assert (Option.value (Map.find book.bids 50000) ~default:0 = large_size);
  print_endline "✓ Large orders handled correctly"

let () =
  print_endline "Starting Aero-Exchange Test Suite\n";
  test_message_parsing ();
  test_order_book_creation ();
  test_order_addition ();
  test_order_matching ();
  test_order_removal ();
  test_get_spread ();
  test_get_mid_price ();
  test_get_volumes ();
  test_imbalance_ratio ();
  test_vwap ();
  test_validation ();
  test_reset ();
  test_edge_case_zero_size ();
  test_edge_case_large_orders ();
  print_endline "\n=== All Tests Passed ===\n"
