open! Core
open! Bonsai_web
open! Js_of_ocaml
open Aero_lib.Types
open State

(* High-resolution timestamp helper *)
let now_seconds () : float =
  try
    let perf = Js.Unsafe.get Js.Unsafe.global (Js.string "performance") in
    let v = Js.Unsafe.meth_call perf "now" [||] in
    (Obj.magic v : float) /. 1000.
  with _ ->
    let date = Js.Unsafe.get Js.Unsafe.global (Js.string "Date") in
    let v = Js.Unsafe.meth_call date "now" [||] in
    (Obj.magic v : float) /. 1000.

(* Mutable simulation state *)
let running_ref = ref true
let speed_ref = ref 100
let volatility_ref = ref 1
let interval_id_ref : Js_of_ocaml.Js.number option ref = ref None
let base_mid_ref = ref 50000

(* Start the continuous market data feed *)
let start_timer inject =
  (* clear existing interval if present *)
  (match !interval_id_ref with
   | Some id -> ignore (Js.Unsafe.meth_call Dom_html.window "clearInterval" [| Js.Unsafe.inject id |])
   | None -> ());

  let cb = Js.wrap_callback (fun () ->
    if !running_ref then begin
      (* occasional drift based on volatility_ref *)
      if Random.int_incl 1 10 <= !volatility_ref then 
        base_mid_ref := !base_mid_ref + (Random.int_incl (-5) 5);
      let is_ask = Random.bool () in
      let target_id = Random.int_incl 1 20000 in
      let operation = Random.int_incl 1 2 in
      let offset = (Random.int_incl 1 10) * 10 in
      let price = if is_ask then !base_mid_ref + offset else !base_mid_ref - offset in
      let size = if operation = 1 then Random.int_incl 1 40 else 0 in
      let now = now_seconds () in
      let msg : Message.t = { time = now; kind = 1; id = target_id;
          size; price; side = (if is_ask then 2 else 1) }
      in
      ignore (Ui_effect.Expert.handle (inject (Action.Process_Message msg)));
      (* update base_mid in the Bonsai model occasionally for UI visibility *)
      if Random.int_incl 1 5 = 1 then ignore (Ui_effect.Expert.handle (inject (Action.Update_Base_Mid !base_mid_ref)));
    end;
    Js._false)
  in
  let id = Js.Unsafe.meth_call Dom_html.window "setInterval"
             [| Js.Unsafe.inject cb; Js.Unsafe.inject (Js.number_of_float (Float.of_int !speed_ref)) |]
  in
  interval_id_ref := Some id

let run_mock_feed inject =
  (* seed book with initial orders *)
  base_mid_ref := 50000 + (Random.int 101 - 50);
  List.iter (List.range 1 15) ~f:(fun i ->
    let now = now_seconds () in
    let bid_msg : Message.t = { time = now; kind = 1; id = i; size = Random.int_incl 5 50;
      price = !base_mid_ref - (i * 10); side = 1 }
    in
    let ask_msg : Message.t = {
        time = now; kind = 1; id = i + 100; size = Random.int_incl 5 50;
        price = !base_mid_ref + (i * 10); side = 2 }
    in
    ignore (Ui_effect.Expert.handle (inject (Action.Process_Message bid_msg)));
    ignore (Ui_effect.Expert.handle (inject (Action.Process_Message ask_msg)))) ;

  start_timer inject;
  ()

let toggle_running inject (_model : Model.t) =
  let new_running = not !running_ref in
  running_ref := new_running;
  if new_running then start_timer inject else (
    match !interval_id_ref with
    | Some id -> ignore (Js.Unsafe.meth_call Dom_html.window "clearInterval" [| Js.Unsafe.inject id |]); 
                 interval_id_ref := None
    | None -> ());
  ignore (Ui_effect.Expert.handle (inject Action.Toggle_Running))

let adjust_speed inject delta =
  let new_speed = Int.max 10 (!speed_ref + delta) in
  speed_ref := new_speed;
  ignore (start_timer inject);
  ignore (Ui_effect.Expert.handle (inject (Action.Set_Speed new_speed)))
