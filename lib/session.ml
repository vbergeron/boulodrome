open Petanque

type session_state =
  { current : Agent.State.t
  ; history : Agent.State.t list
  }

(** Active sessions: map session_id -> current proof state + undo history *)
let table : (string, session_state) Hashtbl.t = Hashtbl.create 16

let get session_id =
  match Hashtbl.find_opt table session_id with
  | Some s -> Ok s.current
  | None ->
    Error
      (Printf.sprintf
         "No active session '%s'. Call rocq_start_proof first." session_id)

let set session_id st =
  let history =
    match Hashtbl.find_opt table session_id with
    | Some s -> s.current :: s.history
    | None -> []
  in
  Hashtbl.replace table session_id { current = st; history }

let undo session_id n =
  match Hashtbl.find_opt table session_id with
  | None ->
    Error (Printf.sprintf "No active session '%s'." session_id)
  | Some s ->
    let avail = List.length s.history in
    if avail = 0 then
      Error "Nothing to undo: no tactics in history."
    else
      let n = min n avail in
      let rec drop k hist =
        if k <= 0 then hist
        else match hist with
          | [] -> []
          | _ :: rest -> drop (k - 1) rest
      in
      match drop (n - 1) s.history with
      | prev :: rest ->
        Hashtbl.replace table session_id { current = prev; history = rest };
        Ok (n, prev)
      | [] ->
        Error "Nothing to undo: no tactics in history."

let remove session_id =
  if Hashtbl.mem table session_id then begin
    Hashtbl.remove table session_id;
    Ok (Printf.sprintf "Session '%s' closed." session_id)
  end
  else
    Error
      (Printf.sprintf "No active session '%s'." session_id)
