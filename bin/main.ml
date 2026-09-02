open Core
open Aero_lib.Types
open Aero_lib.Engine

let stream_file filename =
  printf "=======================================================================\n";
  printf "  AERO-EXCHANGE MATCHING ENGINE — BENCHMARK & GC ALLOCATION AUDIT\n";
  printf "  Runtime: Native OCaml x86_64 (ocamlopt -O3 / OxCaml zero-alloc)\n";
  printf "  Layer:   Core Matching Engine (isolated from JS/Bonsai Web UI)\n";
  printf "=======================================================================\n%!";
  printf "Dataset: %s\n%!" filename;

  printf "Pre-loading dataset into memory array...\n%!";
  let messages =
    In_channel.with_file filename ~f:(fun ch ->
      In_channel.fold_lines ch ~init:[] ~f:(fun acc line ->
        Message.of_string line :: acc))
    |> List.rev
    |> Array.of_list
  in
  let count = Array.length messages in
  printf "Pre-loaded %d messages into memory.\n\n%!" count;

  (* ── Pass 1: Pure Engine Hot Loop (Zero Timer Overhead + GC Audit) ─ *)
  printf "[Pass 1/2] Running Pure Engine Hot Execution (Zero Timer Overhead)...\n%!";
  let pure_book = Order_book.create () in
  let t0 = Time_ns.now () in
  let gc_minor_before = Gc.minor_words () in
  let gc_major_before = Gc.major_words () in
  let stat_before = Gc.quick_stat () in

  for i = 0 to count - 1 do
    let msg = Array.unsafe_get messages i in
    match Message.get_kind msg with
    | 1 -> ignore (Order_book.add pure_book msg)
    | 2 | 3 | 4 | 5 -> Order_book.remove pure_book (Message.get_id msg)
    | _ -> ()
  done;

  let gc_minor_after = Gc.minor_words () in
  let gc_major_after = Gc.major_words () in
  let stat_after = Gc.quick_stat () in
  let t1 = Time_ns.now () in

  let pure_duration_ns = Time_ns.Span.to_int63_ns (Time_ns.diff t1 t0) |> Int63.to_int_exn in
  let pure_avg_ns = pure_duration_ns / count in
  let minor_words_alloc = gc_minor_after - gc_minor_before in
  let major_words_alloc = gc_major_after - gc_major_before in
  let minor_collections = stat_after.minor_collections - stat_before.minor_collections in
  let major_collections = stat_after.major_collections - stat_before.major_collections in

  (* ── Pass 2: Per-Message Latency & Percentile Distribution ─── *)
  printf "[Pass 2/2] Running Per-Message Latency Instrumentation & Percentiles...\n%!";
  let latencies = Array.create ~len:count 0 in
  let book = Order_book.create () in
  let total_lat_ns = ref 0 in

  for i = 0 to count - 1 do
    let msg = Array.unsafe_get messages i in
    let start_time = Time_ns.now () in

    (match Message.get_kind msg with
     | 1 -> ignore (Order_book.add book msg)
     | 2 | 3 | 4 | 5 -> Order_book.remove book (Message.get_id msg)
     | _ -> ());

    let end_time = Time_ns.now () in
    let lat_ns = Time_ns.Span.to_int63_ns (Time_ns.diff end_time start_time) |> Int63.to_int_exn in
    Array.unsafe_set latencies i lat_ns;
    total_lat_ns := !total_lat_ns + lat_ns
  done;

  (* Calculate exact percentiles by sorting latency array *)
  Array.sort latencies ~compare:Int.compare;
  let p_min   = Array.unsafe_get latencies 0 in
  let p50     = Array.unsafe_get latencies (count * 50 / 100) in
  let p90     = Array.unsafe_get latencies (count * 90 / 100) in
  let p95     = Array.unsafe_get latencies (count * 95 / 100) in
  let p99     = Array.unsafe_get latencies (count * 99 / 100) in
  let p99_9   = Array.unsafe_get latencies (count * 999 / 1000) in
  let p99_99  = Array.unsafe_get latencies (count * 9999 / 10000) in
  let p_max   = Array.unsafe_get latencies (count - 1) in
  let timer_avg_ns = !total_lat_ns / count in

  (* Cold-path Map view sync for analytics reporting *)
  Order_book.sync_maps book;

  (* ── Benchmark & GC Report ─────────────────────────────────── *)
  printf "\n=======================================================================\n";
  printf "                       BENCHMARK & GC AUDIT RESULTS\n";
  printf "=======================================================================\n";
  printf " Messages Processed:           %d\n" count;
  printf " Pure Engine Throughput:        %.2f Million ops/sec\n" (1000.0 /. Float.of_int pure_avg_ns);
  printf " Pure Engine Mean Latency:      %d ns / msg\n" pure_avg_ns;
  printf " Timer-Measured Mean Latency:   %d ns / msg (includes clock_gettime)\n" timer_avg_ns;
  printf "-----------------------------------------------------------------------\n";
  printf " GC & ALLOCATION AUDIT (Pass 1 Steady-State Execution):\n";
  printf "   Minor Heap Words Allocated:  %d words (%.4f words/msg)\n"
    minor_words_alloc (Float.of_int minor_words_alloc /. Float.of_int count);
  printf "   Major Heap Words Allocated:  %d words\n" major_words_alloc;
  printf "   Minor GC Collections:        %d\n" minor_collections;
  printf "   Major GC Collections:        %d\n" major_collections;
  printf "   Zero-Allocation Verdict:     %s\n"
    (if minor_words_alloc = 0 && major_words_alloc = 0 then "PASSED (100%% ZERO ALLOC)" else "ALLOCATIONS DETECTED");
  printf "-----------------------------------------------------------------------\n";
  printf " LATENCY DISTRIBUTION (Percentiles):\n";
  printf "   Min:    %6d ns\n" p_min;
  printf "   p50:    %6d ns (median)\n" p50;
  printf "   p90:    %6d ns\n" p90;
  printf "   p95:    %6d ns\n" p95;
  printf "   p99:    %6d ns\n" p99;
  printf "   p99.9:  %6d ns\n" p99_9;
  printf "   p99.99: %6d ns\n" p99_99;
  printf "   Max:    %6d ns\n" p_max;
  printf "-----------------------------------------------------------------------\n";
  printf " ZERO-ALLOC QUERY STATUS:\n";
  printf "   Spread (unboxed):            %d ticks\n" (Order_book.get_spread_unboxed book);
  printf "   Mid-Price (unboxed):         %d ticks\n" (Order_book.get_mid_price_unboxed book);
  printf "   Best Bid:                    %d (qty: %d)\n" (Order_book.get_best_bid_price book) (Order_book.get_best_bid_qty book);
  printf "   Best Ask:                    %d (qty: %d)\n" (Order_book.get_best_ask_price book) (Order_book.get_best_ask_qty book);
  printf "   VWAP:                        %d\n" (Order_book.get_vwap book);
  printf "   Book Validated (no cross):   %b\n" (Order_book.validate book);
  printf "-----------------------------------------------------------------------\n";
  printf " TOP 5 TRADING LEVELS (Price | Volume):\n";
  Map.to_alist book.volume_at_price
  |> List.sort ~compare:(fun (_, v1) (_, v2) -> Int.compare v2 v1)
  |> (fun l -> List.take l 5)
  |> List.iter ~f:(fun (price, vol) -> printf "   %d | %d shares\n" price vol);
  printf "=======================================================================\n%!"

(* ── Entry point ─────────────────────────────────────────────── *)
let () =
  Gc.set { (Gc.get ()) with
    minor_heap_size = 1024 * 1024 * 32;
    space_overhead  = 100;
  };
  let filename = "AAPL_2012-06-21_34200000_57600000_message_5.csv" in
  if Result.is_ok (Core_unix.access filename [`Exists])
  then stream_file filename
  else printf "File not found: %s\n" filename