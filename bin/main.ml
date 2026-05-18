open Core
open Aero_lib.Types
open Aero_lib.Engine

(* Tracking performance metrics *)
let total_latency = ref Time_ns.Span.zero
let min_latency   = ref (Time_ns.Span.of_int_sec 1)
let max_latency   = ref Time_ns.Span.zero
let msg_count     = ref 0

let process_message book msg =
  let start_time = Time_ns.now () in
  
  (* The core matching engine logic *)
  (match msg.Message.kind with
  | 1 -> ignore (Order_book.add book msg)
  | 2 | 3 | 4 | 5 -> Order_book.remove book msg.id
  | _ -> ());
  
  let end_time = Time_ns.now () in
  let latency = Time_ns.diff end_time start_time in
  
  (* Safely increment latency tracking *)
  total_latency := Time_ns.Span.(!total_latency + latency);
  if Time_ns.Span.(!min_latency > latency) then min_latency := latency;
  if Time_ns.Span.(!max_latency < latency) then max_latency := latency;
  incr msg_count

let stream_file filename =
  let book = Order_book.create () in
  printf "Booting Aero-Exchange Engine...\n%!";
  printf "Benchmarking Stream: %s\n%!" filename;
  
  In_channel.with_file filename ~f:(fun channel ->
    In_channel.iter_lines channel ~f:(fun line ->
      let msg = Message.of_string line in
      process_message book msg
    ));

  (* --- LATENCY RESULTS --- *)
  let avg_latency = 
    Time_ns.Span.to_int63_ns !total_latency 
    |> Int63.to_int_exn 
    |> (fun total -> total / !msg_count)
  in

  printf "\n------------------------------------------\n";
  printf "BENCHMARK RESULTS (Processed %d messages)\n" !msg_count;
  printf "Average Latency: %d ns\n" avg_latency;
  printf "Min Latency:     %d ns\n" (Time_ns.Span.to_int63_ns !min_latency |> Int63.to_int_exn);
  printf "Max Latency:     %d ns\n" (Time_ns.Span.to_int63_ns !max_latency |> Int63.to_int_exn);
  printf "------------------------------------------\n";

  (* --- VOLUME ANALYTICS --- *)
  printf "\nTOP 5 TRADING LEVELS (Price | Volume)\n";
  let top_levels = 
    Map.to_alist book.volume_at_price  (* Simplified access *)
    |> List.sort ~compare:(fun (_, v1) (_, v2) -> Int.compare v2 v1)
    |> (fun l -> List.take l 5)
  in
  List.iter top_levels ~f:(fun (price, vol) ->
    printf "%d | %d shares\n" price vol);
  printf "------------------------------------------\n"

(* --- ENTRY POINT --- *)
let () =
  (* 1. TUNE THE GC FOR HFT PERFORMANCE *)
  let control = Gc.get () in
  Gc.set { control with 
    minor_heap_size = 1024 * 1024 * 16; (* 16MB minor heap to prevent GC thrashing *)
    space_overhead = 100;               (* Faster major GC collection trigger *)
  };

  (* 2. CHECK FILE AND INITIATE STREAM *)
  let filename = "AAPL_2012-06-21_34200000_57600000_message_5.csv" in
  if Result.is_ok (Core_unix.access filename [ `Exists ]) then
    stream_file filename
  else
    printf "File not found! Make sure %s is in the project root.\n" filename