open Core
open Aero_lib.Engine
open Aero_lib.Types

let () =
  let book = Order_book.create () in
  let msg_bid = Message.create ~time:1.0 ~kind:1 ~id:1 ~size:100 ~price:1000 ~side:1 in
  let msg_ask = Message.create ~time:2.0 ~kind:1 ~id:2 ~size:50 ~price:1000 ~side:2 in
  
  (* Warm up *)
  ignore (Order_book.add book msg_bid);
  ignore (Order_book.add book msg_ask);
  Order_book.remove book 1;
  Order_book.reset book;

  (* Pre-allocated messages *)
  let msg = Message.create ~time:3.0 ~kind:1 ~id:3 ~size:10 ~price:1000 ~side:1 in
  
  (* Measure allocation on add *)
  let gc_before = Gc.quick_stat () in
  for _i = 1 to 1000 do
    ignore (Order_book.add book msg)
  done;
  let gc_after = Gc.quick_stat () in
  let allocated_words_add = gc_after.minor_words -. gc_before.minor_words in
  
  (* Measure allocation on remove *)
  let gc_before_rem = Gc.quick_stat () in
  for _i = 1 to 1000 do
    Order_book.remove book 3
  done;
  let gc_after_rem = Gc.quick_stat () in
  let allocated_words_rem = gc_after_rem.minor_words -. gc_before_rem.minor_words in

  printf "========================================\n";
  printf "GC Telemetry Verification:\n";
  printf "Allocated words for 1000 additions: %f\n" allocated_words_add;
  printf "Allocated words for 1000 removals:  %f\n" allocated_words_rem;
  printf "========================================\n"
