open Petanque

(* A position in the [l<line>c<col>] format that [rocq_diagnostics] reports:
   1-based line, 0-based column. A full diagnostic range
   [l<line>c<col>-l<line>c<col>] is accepted too, and its start is used, so
   a range can be pasted verbatim from a diagnostic. *)
type position =
  { line : int  (** 1-based *)
  ; col : int  (** 0-based *)
  }

let position_to_string { line; col } = Printf.sprintf "l%dc%d" line col

let parse_position s =
  let s = String.trim s in
  let scan fmt k = try Some (Scanf.sscanf s fmt k) with _ -> None in
  let parsed =
    match scan "l%uc%u-l%uc%u%!" (fun line col _ _ -> (line, col)) with
    | Some p -> Some p
    | None -> scan "l%uc%u%!" (fun line col -> (line, col))
  in
  match parsed with
  | Some (line, col) when line >= 1 -> Ok { line; col }
  | _ ->
    Error
      (Printf.sprintf
         "Invalid position '%s': expected l<line>c<column> (1-based line, \
          0-based column, as reported by rocq_diagnostics), e.g. \"l12c4\""
         s)

let report ~token ~file_path ~session_id ~theorem_name ~origin
    (rr : Agent.State.t Agent.Run_result.t) =
  let goals_text =
    match Agent.goals ~token ~st:rr.Agent.Run_result.st () with
    | Ok g -> Goal.format g
    | Error _ -> "(goals unavailable)"
  in
  Session.create session_id ~file_path ~theorem_name rr.Agent.Run_result.st;
  Printf.sprintf
    "Started proof of '%s' in %s%s\n\
     Session: %s\n\
     Proof finished: %b\n\
     State: 0\n\
     %s"
    theorem_name file_path origin session_id rr.Agent.Run_result.proof_finished
    goals_text

let run_by_name ~token ~doc ~file_path ~theorem_name ~session_id ?pre_commands
    () =
  let result = Agent.start ~token ~doc ?pre_commands ~thm:theorem_name () in
  match Tools_helpers.unwrap_agent "start" result with
  | Error e -> Error (e ^ Tools_helpers.format_doc_errors doc)
  | Ok rr ->
    Ok (report ~token ~file_path ~session_id ~theorem_name ~origin:"" rr)

(* Petanque positions are LSP ones: 0-based line and column. The node found
   is the sentence containing the point, or the last sentence before it when
   the point falls between sentences; its state is the one after that
   sentence ran (or, when the sentence failed, the recovered state just
   before it). *)
let run_at_position ~token ~doc ~file_path ~position ~session_id () =
  let point = (position.line - 1, position.col) in
  let pos = position_to_string position in
  match
    Tools_helpers.unwrap_agent "start"
      (Agent.get_state_at_pos ~doc ~point ())
  with
  | Error e -> Error (Printf.sprintf "%s (at %s)" e pos)
  | Ok rr ->
    (match Agent.State.lemmas rr.Agent.Run_result.st with
     | None ->
       Error
         (Printf.sprintf
            "No proof is open at %s in %s. Point inside a proof, e.g. at a \
             tactic between `Proof.` and `Qed.`."
            pos file_path)
     | Some _ ->
       let theorem_name =
         match Agent.proof_info_at_pos ~token ~doc ~point () with
         | Ok (Some info) -> info.Agent.Proof_info.name
         | Ok None | Error _ -> Printf.sprintf "<proof at %s>" pos
       in
       Ok
         (report ~token ~file_path ~session_id ~theorem_name
            ~origin:(Printf.sprintf " at %s" pos) rr))

let run ~token ~file_path ?theorem_name ?position ~session_id ?pre_commands ()
    =
  match theorem_name, position, pre_commands with
  | None, None, _ ->
    Error "Provide either theorem_name or position."
  | Some _, Some _, _ ->
    Error "Provide either theorem_name or position, not both."
  | None, Some _, Some _ ->
    Error
      "pre_commands is only supported with theorem_name, not with position."
  | Some theorem_name, None, _ ->
    (match Tools_helpers.build_doc ~token file_path with
     | Error e -> Error e
     | Ok doc ->
       run_by_name ~token ~doc ~file_path ~theorem_name ~session_id
         ?pre_commands ())
  | None, Some position, None ->
    (match Tools_helpers.build_doc ~token file_path with
     | Error e -> Error e
     | Ok doc -> run_at_position ~token ~doc ~file_path ~position ~session_id ())
