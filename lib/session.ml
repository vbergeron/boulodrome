open Petanque

type meta =
  { file_path : string
  ; theorem_name : string
  }

type session_state =
  { current : Agent.State.t
  ; history : Agent.State.t list
  ; meta : meta
  }

type error =
  | NoSession of string
  | NoHistory of string
  | NoUndo of string

let error_to_string = function
  | NoSession session_id ->
    Printf.sprintf "No active session '%s'. Call rocq_start_proof first." session_id
  | NoHistory session_id ->
    Printf.sprintf "No history for session '%s'." session_id
  | NoUndo session_id ->
    Printf.sprintf "No undo for session '%s'." session_id

let table : (string, session_state) Hashtbl.t = Hashtbl.create 16

let get_state session_id =
  match Hashtbl.find_opt table session_id with
  | Some s -> Ok s
  | None   -> Error (NoSession session_id)

let get session_id =
  get_state session_id |> Result.map (fun s -> s.current)

let create session_id ~file_path ~theorem_name st =
  Hashtbl.replace table session_id
    { current = st; history = []; meta = { file_path; theorem_name } }

let set session_id st =
  match get_state session_id with
  | Ok s ->
    Hashtbl.replace table session_id
      { current = st; history = s.current :: s.history; meta = s.meta }
  | Error _ ->
    (* Every existing caller of [set] first calls [get]/[get_state]
       successfully, so this should not happen in practice. Fall back to
       creating the session with empty metadata rather than dropping the
       state on the floor. *)
    Hashtbl.replace table session_id
      { current = st
      ; history = []
      ; meta = { file_path = ""; theorem_name = "" }
      }

let undo session_id n =
  match get_state session_id with
  | Error e -> Error e
  | Ok s ->
    let n = min n (List.length s.history) in
    let dropped = List.to_seq s.history |> Seq.drop (n - 1) |> List.of_seq in
    match dropped with
    | [] -> Error (NoUndo session_id)
    | prev :: rest ->
      Hashtbl.replace table session_id { current = prev; history = rest; meta = s.meta };
      Ok (n, prev)

let remove session_id =
  if Hashtbl.mem table session_id then begin
    Hashtbl.remove table session_id;
    Ok (Printf.sprintf "Session '%s' closed." session_id)
  end
  else
    Error (NoSession session_id)

let list () =
  Hashtbl.fold (fun session_id s acc -> (session_id, s) :: acc) table []
  |> List.sort (fun (a, _) (b, _) -> String.compare a b)
