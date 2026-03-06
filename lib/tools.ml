open Petanque

(* ------------------------------------------------------------------ *)
(* Helpers                                                             *)
(* ------------------------------------------------------------------ *)

let unwrap_agent label = function
  | Ok v -> Ok v
  | Error e ->
    Error (Printf.sprintf "%s: %s" label (Agent.Error.to_string e.Request.Error.payload))

let uri_of_path path =
  let uri_str = Printf.sprintf "file://%s" path in
  let uri = Lang.LUri.of_string uri_str in
  match Lang.LUri.File.of_uri uri with
  | Ok f -> Ok f
  | Error msg -> Error (Printf.sprintf "Invalid path %s: %s" path msg)

let build_doc ~token path =
  match uri_of_path path with
  | Error e -> Error e
  | Ok uri ->
    (match Coq_init.build_doc ~token ~uri with
     | Ok doc -> Ok doc
     | Error e ->
       Error
         (Printf.sprintf "Failed to load %s: %s" path
            (Agent.Error.to_string e.Request.Error.payload)))

(* Format a goals value into a human-readable string. *)
let format_goals (goals_opt : (string, string) Coq.Goals.reified option) =
  match goals_opt with
  | None -> "No goals — proof may already be complete."
  | Some goals ->
    let open Coq.Goals in
    if goals.goals = [] && goals.shelf = [] && goals.given_up = [] then
      "No remaining goals — proof complete!"
    else begin
      let buf = Buffer.create 256 in
      List.iteri
        (fun i g ->
          Buffer.add_string buf (Printf.sprintf "Goal %d:\n" (i + 1));
          List.iter
            (fun (h : string Reified_goal.hyp) ->
              let names = String.concat ", " h.names in
              (match h.def with
               | None ->
                 Buffer.add_string buf (Printf.sprintf "  %s : %s\n" names h.ty)
               | Some d ->
                 Buffer.add_string buf
                   (Printf.sprintf "  %s := %s : %s\n" names d h.ty)))
            g.Reified_goal.hyps;
          Buffer.add_string buf "  ⊢ ";
          Buffer.add_string buf g.Reified_goal.ty;
          Buffer.add_char buf '\n')
        goals.goals;
      if goals.shelf <> [] then
        Buffer.add_string buf
          (Printf.sprintf "Shelved: %d goal(s)\n" (List.length goals.shelf));
      if goals.given_up <> [] then
        Buffer.add_string buf
          (Printf.sprintf "Given up: %d goal(s)\n" (List.length goals.given_up));
      Buffer.contents buf
    end

let format_run_result (rr : Agent.State.t Agent.Run_result.t) session_id token
    =
  let open Agent.Run_result in
  Session.set session_id rr.st;
  let feedback_lines =
    List.map (fun (lvl, msg) -> Printf.sprintf "[level %d] %s" lvl msg) rr.feedback
  in
  let feedback_text =
    if feedback_lines = [] then ""
    else "\nFeedback:\n" ^ String.concat "\n" feedback_lines
  in
  let goals_text =
    match Agent.goals ~token ~st:rr.st () with
    | Ok g -> "\n" ^ format_goals g
    | Error e ->
      Printf.sprintf "\n(goals unavailable: %s)"
        (Agent.Error.to_string e.Request.Error.payload)
  in
  let proof_status =
    if rr.proof_finished then "Proof complete!" else "Proof in progress."
  in
  proof_status ^ feedback_text ^ goals_text

(* ------------------------------------------------------------------ *)
(* Tool implementations                                                *)
(* ------------------------------------------------------------------ *)

(** Format document-level errors as a diagnostic appendix.  Returns an empty
    string when there are no errors. *)
let format_doc_errors doc =
  match Coq_init.doc_errors doc with
  | [] -> ""
  | errs ->
    let unique = List.sort_uniq String.compare errs in
    let shown = List.filteri (fun i _ -> i < 10) unique in
    let suffix =
      let n = List.length unique - List.length shown in
      if n > 0 then [ Printf.sprintf "  ... and %d more" n ] else []
    in
    "\n\nDocument errors (may be the root cause):\n"
    ^ String.concat "\n" (List.map (fun e -> "  - " ^ e) shown @ suffix)

(** Start a proof session for [thm] in [file_path]. *)
let start_proof ~token ~file_path ~theorem_name ~session_id ?pre_commands () =
  match build_doc ~token file_path with
  | Error e -> Error e
  | Ok doc ->
    let result =
      Agent.start ~token ~doc ?pre_commands ~thm:theorem_name ()
    in
    (match unwrap_agent "start" result with
     | Error e -> Error (e ^ format_doc_errors doc)
     | Ok rr ->
       let goals_text =
         match Agent.goals ~token ~st:rr.Agent.Run_result.st () with
         | Ok g -> format_goals g
         | Error _ -> "(goals unavailable)"
       in
       Session.set session_id rr.Agent.Run_result.st;
       let msg =
         Printf.sprintf
           "Started proof of '%s' in %s\nSession: %s\nProof finished: %b\n%s"
           theorem_name file_path session_id rr.Agent.Run_result.proof_finished
           goals_text
       in
       Ok msg)

(** Run a tactic on the current session state. *)
let run_tactic ~token ~session_id ~tac ?timeout:_ () =
  match Session.get session_id with
  | Error e -> Error e
  | Ok st ->
    (match Agent.run ~token ~st ~tac () with
     | Error e ->
       Error
         (Printf.sprintf "Tactic failed: %s"
            (Agent.Error.to_string e.Request.Error.payload))
     | Ok rr ->
       let text = format_run_result rr session_id token in
       Ok (Printf.sprintf "Executed: %s\n%s" tac text))

(** Get current proof goals for a session. *)
let get_goals ~token ~session_id () =
  match Session.get session_id with
  | Error e -> Error e
  | Ok st ->
    (match Agent.goals ~token ~st () with
     | Error e ->
       Error
         (Printf.sprintf "Goals error: %s"
            (Agent.Error.to_string e.Request.Error.payload))
     | Ok g -> Ok (format_goals g))

(** List available premises for the current proof state. *)
let get_premises ~token ~session_id () =
  match Session.get session_id with
  | Error e -> Error e
  | Ok st ->
    (match Agent.premises ~token ~st with
     | Error e ->
       Error
         (Printf.sprintf "Premises error: %s"
            (Agent.Error.to_string e.Request.Error.payload))
     | Ok premises ->
       let n = List.length premises in
       let shown = List.filteri (fun i _ -> i < 20) premises in
       let lines =
         List.mapi
           (fun i p ->
             Printf.sprintf "%d. %s (in %s)" (i + 1) p.Agent.Premise.full_name
               p.Agent.Premise.file)
           shown
       in
       let suffix =
         if n > 20 then
           [ Printf.sprintf "... and %d more premises" (n - 20) ]
         else []
       in
       Ok
         (Printf.sprintf "Available premises (%d total):\n%s" n
            (String.concat "\n" (lines @ suffix))))

(** Get the table of contents for a Coq/Rocq file. *)
let get_file_toc ~token ~file_path () =
  match build_doc ~token file_path with
  | Error e -> Error e
  | Ok doc ->
    (match Coq_init.get_toc ~token ~doc with
     | Error e ->
       Error
         (Printf.sprintf "TOC error: %s"
            (Agent.Error.to_string e.Request.Error.payload))
     | Ok entries ->
       let lines =
         List.map
           (fun (name, info_opt) ->
             match info_opt with
             | None -> Printf.sprintf "- %s" name
             | Some infos ->
               let details =
                 List.filter_map (fun (i : Lang.Ast.Info.t) -> i.detail) infos
               in
               (match details with
                | [] -> Printf.sprintf "- %s" name
                | d :: _ -> Printf.sprintf "- %s : %s" name d))
           entries
       in
       Ok
         (Printf.sprintf "Table of contents for %s:\n%s%s" file_path
            (String.concat "\n" lines)
            (format_doc_errors doc)))

(** Undo the last [steps] tactics, restoring a previous proof state. *)
let undo ~token ~session_id ~steps () =
  match Session.undo session_id steps with
  | Error e -> Error e
  | Ok (actual, st) ->
    let goals_text =
      match Agent.goals ~token ~st () with
      | Ok g -> format_goals g
      | Error _ -> "(goals unavailable)"
    in
    let clamped =
      if actual < steps then
        Printf.sprintf " (requested %d, only %d in history)" steps actual
      else ""
    in
    Ok (Printf.sprintf "Undid %d step(s)%s.\n%s" actual clamped goals_text)

(** Run multiple tactics in sequence; stop at the first failure. *)
let run_tactics ~token ~session_id ~tactics () =
  let tac_list =
    String.split_on_char '\n' tactics
    |> List.map String.trim
    |> List.filter (fun s -> s <> "")
  in
  let total = List.length tac_list in
  let rec go i = function
    | [] ->
      (match Session.get session_id with
       | Error e -> Error e
       | Ok st ->
         let goals_text =
           match Agent.goals ~token ~st () with
           | Ok g -> format_goals g
           | Error _ -> "(goals unavailable)"
         in
         Ok (Printf.sprintf "All %d tactic(s) succeeded.\n%s" total goals_text))
    | tac :: rest ->
      (match Session.get session_id with
       | Error e -> Error e
       | Ok st ->
         (match Agent.run ~token ~st ~tac () with
          | Error e ->
            let goals_text =
              match Agent.goals ~token ~st () with
              | Ok g -> format_goals g
              | Error _ -> "(goals unavailable)"
            in
            Ok
              (Printf.sprintf
                 "Tactic %d/%d failed: %s\nError: %s\n\
                  State is at tactic %d. Current goals:\n%s"
                 (i + 1) total tac
                 (Agent.Error.to_string e.Request.Error.payload)
                 i goals_text)
          | Ok rr ->
            Session.set session_id rr.Agent.Run_result.st;
            if rr.Agent.Run_result.proof_finished then
              Ok
                (Printf.sprintf "Proof complete after tactic %d/%d: %s"
                   (i + 1) total tac)
            else go (i + 1) rest))
  in
  if tac_list = [] then Error "No tactics provided."
  else go 0 tac_list

(** Search for theorems/definitions matching [query] in the current context. *)
let search ~token ~session_id ~query () =
  match Session.get session_id with
  | Error e -> Error e
  | Ok st ->
    let tac =
      if String.contains query ' ' || String.contains query '"' then
        Printf.sprintf {|Search "%s".|} query
      else Printf.sprintf "Search %s." query
    in
    (match Agent.run ~token ~st ~tac () with
     | Error e ->
       Error
         (Printf.sprintf "Search error: %s"
            (Agent.Error.to_string e.Request.Error.payload))
     | Ok rr ->
       let results =
         List.map (fun (_lvl, msg) -> msg) rr.Agent.Run_result.feedback
       in
       let max_results = 50 in
       let shown = List.filteri (fun i _ -> i < max_results) results in
       let suffix =
         if List.length results > max_results then
           [ Printf.sprintf "... and %d more results"
               (List.length results - max_results)
           ]
         else []
       in
       if results = [] then Ok (Printf.sprintf "No results for: %s" query)
       else
         Ok
           (Printf.sprintf "Search results for '%s':\n%s" query
              (String.concat "\n" (shown @ suffix))))
