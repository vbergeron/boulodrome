open Petanque

type meta =
  { file_path : string
  ; theorem_name : string
  }

(* One entry per proof state ever reached in a session, keyed by a
   monotonically increasing id. Entry 0 is the state right after
   [rocq_start_proof]; entry [id] (id > 0) is the state reached by running
   [tac] against the state of [parent_id]. Entries are never removed --
   undo only moves [current_id] to an earlier entry, so any id a caller has
   seen (e.g. from a prior `rocq_run_tactics` report) stays addressable for
   the lifetime of the session, even after further tactics have run past
   it. *)
type entry =
  { id : int
  ; parent_id : int option
  ; tac : string option
  ; state : Agent.State.t
  }

type session_state =
  { current : Agent.State.t
  ; current_id : int
  ; index : (int, entry) Hashtbl.t
  ; next_id : int
  ; meta : meta
  }

type error =
  | NoSession of string
  | NoHistory of string
  | NoUndo of string
  | NoProofState of string * int

let error_to_string = function
  | NoSession session_id ->
    Printf.sprintf "No active session '%s'. Call rocq_start_proof first." session_id
  | NoHistory session_id ->
    Printf.sprintf "No history for session '%s'." session_id
  | NoUndo session_id ->
    Printf.sprintf "No undo for session '%s'." session_id
  | NoProofState (session_id, proof_state_id) ->
    Printf.sprintf "No proof state %d in session '%s'." proof_state_id
      session_id

let table : (string, session_state) Hashtbl.t = Hashtbl.create 16

let get_state session_id =
  match Hashtbl.find_opt table session_id with
  | Some s -> Ok s
  | None   -> Error (NoSession session_id)

let get session_id =
  get_state session_id |> Result.map (fun s -> s.current)

let create session_id ~file_path ~theorem_name st =
  let index = Hashtbl.create 16 in
  Hashtbl.replace index 0 { id = 0; parent_id = None; tac = None; state = st };
  Hashtbl.replace table session_id
    { current = st
    ; current_id = 0
    ; index
    ; next_id = 1
    ; meta = { file_path; theorem_name }
    }

(* Records a new proof state reached by running [tac] against the current
   state, and returns its id. *)
let set session_id ~tac st =
  match get_state session_id with
  | Ok s ->
    let id = s.next_id in
    Hashtbl.replace s.index id
      { id; parent_id = Some s.current_id; tac = Some tac; state = st };
    Hashtbl.replace table session_id
      { s with current = st; current_id = id; next_id = id + 1 };
    id
  | Error _ ->
    (* Every existing caller of [set] first calls [get]/[get_state]
       successfully, so this should not happen in practice. Fall back to
       creating the session with empty metadata rather than dropping the
       state on the floor. *)
    let index = Hashtbl.create 16 in
    Hashtbl.replace index 0 { id = 0; parent_id = None; tac = None; state = st };
    Hashtbl.replace table session_id
      { current = st
      ; current_id = 0
      ; index
      ; next_id = 1
      ; meta = { file_path = ""; theorem_name = "" }
      };
    0

(* Undo [n] committed steps by walking [current_id]'s parent chain. Returns
   the number of steps actually undone (clamped to how far back the root
   allows), the id landed on, and its state. *)
let undo session_id n =
  match get_state session_id with
  | Error e -> Error e
  | Ok s ->
    let rec walk id steps =
      if steps >= n then (id, steps)
      else
        match (Hashtbl.find s.index id).parent_id with
        | None -> (id, steps)
        | Some parent_id -> walk parent_id (steps + 1)
    in
    let target_id, actual = walk s.current_id 0 in
    if actual = 0 then Error (NoUndo session_id)
    else
      let entry = Hashtbl.find s.index target_id in
      Hashtbl.replace table session_id
        { s with current = entry.state; current_id = target_id };
      Ok (actual, target_id, entry.state)

(* Jump directly to a previously-indexed proof state by id, regardless of
   whether it lies on the current lineage (it may be the far side of an
   earlier undo). *)
let undo_to session_id proof_state_id =
  match get_state session_id with
  | Error e -> Error e
  | Ok s ->
    (match Hashtbl.find_opt s.index proof_state_id with
     | None -> Error (NoProofState (session_id, proof_state_id))
     | Some entry ->
       Hashtbl.replace table session_id
         { s with current = entry.state; current_id = proof_state_id };
       Ok entry.state)

(* Committed tactics for a session, oldest first, in the exact form they
   were submitted -- suitable for pasting verbatim between [Proof.] and
   [Qed.]. This is the raw record of what actually ran, not a
   reconstruction, so it preserves `;`-chaining across goals that a
   hand-transcribed, one-sentence-per-tactic script would break. *)
let tactics session_id =
  get_state session_id
  |> Result.map (fun s ->
    let rec walk id acc =
      let entry = Hashtbl.find s.index id in
      let acc = match entry.tac with Some t -> t :: acc | None -> acc in
      match entry.parent_id with
      | None -> acc
      | Some parent_id -> walk parent_id acc
    in
    walk s.current_id [])

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
