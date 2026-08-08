open Core
open Aero_lib.Types
open Aero_lib.Engine

(* Tracking performance metrics — refs live outside the hot path *)
let total_latency = ref Time_ns.Span.zero
let min_latency   = ref (Time_ns.Span.of_int_sec 1)
let max_latency   = ref Time_ns.Span.zero
let msg_count     = ref 0

let stream_file filename =
  printf "Booting Aero-Exchange Engine (OxCaml zero-alloc O(1))...\n%!";
  printf "Benchmarking Stream: %s\n%!" filename;

  printf "Pre-loading dataset into memory array...\n%!";
  let messages =
    In_channel.with_file filename ~f:(fun ch ->
      In_channel.fold_lines ch ~init:[] ~f:(fun acc line ->
        Message.of_string line :: acc))
    |> List.rev
    |> Array.of_list
  in
  let count = Array.length messages in
  printf "Loaded %d messages into memory.\n\n%!" count;

  (* ── Pass 1: Pure Engine Hot Loop (Zero Timer Overhead) ────── *)
  printf "Running Pass 1: Pure Engine Hot Execution (Zero Timer Overhead)...\n%!";
  let pure_book = Order_book.create () in
  let t0 = Time_ns.now () in
  for i = 0 to count - 1 do
    let msg = Array.unsafe_get messages i in
    match Message.get_kind msg with
    | 1 -> ignore (Order_book.add pure_book msg)
    | 2 | 3 | 4 | 5 -> Order_book.remove pure_book (Message.get_id msg)
    | _ -> ()
  done;
  let t1 = Time_ns.now () in
  let pure_duration_ns = Time_ns.Span.to_int63_ns (Time_ns.diff t1 t0) |> Int63.to_int_exn in
  let pure_avg_ns = pure_duration_ns / count in

  (* ── Pass 2: Per-Message Latency Instrumentation ─────────── *)
  printf "Running Pass 2: Per-Message Timer Instrumentation...\n%!";
  let book = Order_book.create () in
  for i = 0 to count - 1 do
    let msg = Array.unsafe_get messages i in
    let start_time = Time_ns.now () in

    (match Message.get_kind msg with
     | 1 -> ignore (Order_book.add book msg)
     | 2 | 3 | 4 | 5 -> Order_book.remove book (Message.get_id msg)
     | _ -> ());

    let latency = Time_ns.diff (Time_ns.now ()) start_time in
    total_latency := Time_ns.Span.(!total_latency + latency);
    if Time_ns.Span.(!min_latency > latency) then min_latency := latency;
    if Time_ns.Span.(!max_latency < latency) then max_latency := latency;
    incr msg_count
  done;

  (* sync_maps is cold-path — rebuilds Map views for analytics below *)
  Order_book.sync_maps book;

  let per_msg_avg =
    Time_ns.Span.to_int63_ns !total_latency
    |> Int63.to_int_exn
    |> (fun total -> total / !msg_count)
  in

  printf "\n------------------------------------------\n";
  printf "BENCHMARK RESULTS (Processed %d messages)\n" !msg_count;
  printf "Pure Engine Mean Latency:  %d ns / msg (%.2f Million ops/sec)\n"
    pure_avg_ns (1000.0 /. Float.of_int pure_avg_ns);
  printf "Timer-measured Avg Latency: %d ns (includes clock_gettime overhead)\n" per_msg_avg;
  printf "Min Measured Latency:       %d ns\n" (Time_ns.Span.to_int63_ns !min_latency |> Int63.to_int_exn);
  printf "Max Measured Latency:       %d ns\n" (Time_ns.Span.to_int63_ns !max_latency |> Int63.to_int_exn);
  printf "------------------------------------------\n";

  printf "\nTOP 5 TRADING LEVELS (Price | Volume)\n";
  Map.to_alist book.volume_at_price
  |> List.sort ~compare:(fun (_, v1) (_, v2) -> Int.compare v2 v1)
  |> (fun l -> List.take l 5)
  |> List.iter ~f:(fun (price, vol) -> printf "%d | %d shares\n" price vol);
  printf "------------------------------------------\n"

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