open Core
open Aero_lib.Types
open Aero_lib.Engine

(* Tracking performance metrics — refs live outside the hot path *)
let total_latency = ref Time_ns.Span.zero
let min_latency   = ref (Time_ns.Span.of_int_sec 1)
let max_latency   = ref Time_ns.Span.zero
let msg_count     = ref 0

(* process_message — dispatches into the zero-alloc hot path.
   Fields decoded via Message accessors; unboxing is encapsulated in Types. *)
let process_message book (msg : Message.t) =
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

let stream_file filename =
  let book = Order_book.create () in
  printf "Booting Aero-Exchange Engine (OxCaml zero-alloc)...\n%!";
  printf "Benchmarking Stream: %s\n%!" filename;

  In_channel.with_file filename ~f:(fun ch ->
    In_channel.iter_lines ch ~f:(fun line ->
      process_message book (Message.of_string line)));

  (* sync_maps is cold-path — rebuilds Map views for analytics below *)
  Order_book.sync_maps book;

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

  printf "\nTOP 5 TRADING LEVELS (Price | Volume)\n";
  Map.to_alist book.volume_at_price
  |> List.sort ~compare:(fun (_, v1) (_, v2) -> Int.compare v2 v1)
  |> (fun l -> List.take l 5)
  |> List.iter ~f:(fun (price, vol) -> printf "%d | %d shares\n" price vol);
  printf "------------------------------------------\n"

(* ── Entry point ─────────────────────────────────────────────── *)
let () =
  (* GC tuning: large minor heap reduces collection frequency.
     With a zero-alloc hot path this becomes largely a no-op,
     but it still protects the cold (I/O parsing) path.       *)
  Gc.set { (Gc.get ()) with
    minor_heap_size = 1024 * 1024 * 16;
    space_overhead  = 100;
  };
  let filename = "AAPL_2012-06-21_34200000_57600000_message_5.csv" in
  if Result.is_ok (Core_unix.access filename [`Exists])
  then stream_file filename
  else printf "File not found: %s\n" filename