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
         | Ok g -> Goal.format g
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

(** Run one or more tactics on the current session state.  Tactics are
    newline-separated; execution stops at the first failure.  When [verbose]
    is set, the goal state after each successful tactic is included. *)
let run_tactic ~token ~session_id ~tac ~verbose () =
  let tac_list =
    String.split_on_char '\n' tac
    |> List.map String.trim
    |> List.filter (fun s -> s <> "")
  in
  match tac_list with
  | [] -> Error "No tactics provided."
  | _ ->
    let total = List.length tac_list in
    let buf = Buffer.create 256 in
    let rec go i = function
      | [] ->
        (match Session.get session_id with
         | Error e -> Error e
         | Ok st ->
           let goals_result = Agent.goals ~token ~st () in
           let complete =
             match goals_result with
             | Ok g -> Goal.are_complete g
             | Error _ -> false
           in
           let status =
             if complete then "Proof complete!" else "Proof in progress."
           in
           Buffer.add_string buf (Printf.sprintf "%s\n" status);
           (match goals_result with
            | Ok g -> Buffer.add_string buf (Goal.format g)
            | Error _ -> Buffer.add_string buf "(goals unavailable)");
           Ok (Buffer.contents buf))
      | tac :: rest ->
        (match Session.get session_id with
         | Error e -> Error e
         | Ok st ->
           (match Agent.run ~token ~st ~tac () with
            | Error e ->
              let goals_text =
                match Agent.goals ~token ~st () with
                | Ok g -> Goal.format g
                | Error _ -> "(goals unavailable)"
              in
              Buffer.add_string buf
                (Printf.sprintf "Tactic %d/%d failed: %s\nError: %s\n\
                                 State is at tactic %d. Current goals:\n%s"
                   (i + 1) total tac
                   (Agent.Error.to_string e.Request.Error.payload)
                   i goals_text);
              Ok (Buffer.contents buf)
            | Ok rr ->
              Session.set session_id rr.Agent.Run_result.st;
              let goals_result = Agent.goals ~token ~st:rr.Agent.Run_result.st () in
              let complete =
                match goals_result with
                | Ok g -> Goal.are_complete g
                | Error _ -> rr.Agent.Run_result.proof_finished
              in
              let feedback_lines =
                List.filter_map
                  (fun (lvl, msg) ->
                    if lvl > 0 then Some (Printf.sprintf "[level %d] %s" lvl msg)
                    else None)
                  rr.Agent.Run_result.feedback
              in
              if verbose || total = 1 then begin
                Buffer.add_string buf
                  (Printf.sprintf "Executed (%d/%d): %s\n" (i + 1) total tac);
                List.iter
                  (fun l -> Buffer.add_string buf (l ^ "\n"))
                  feedback_lines;
                (match goals_result with
                 | Ok g -> Buffer.add_string buf (Goal.format g)
                 | Error _ -> Buffer.add_string buf "(goals unavailable)");
                Buffer.add_char buf '\n'
              end else begin
                Buffer.add_string buf
                  (Printf.sprintf "Executed (%d/%d): %s\n" (i + 1) total tac);
                List.iter
                  (fun l -> Buffer.add_string buf (l ^ "\n"))
                  feedback_lines
              end;
              if complete then begin
                Buffer.add_string buf "No remaining goals — proof complete!\n";
                Ok (Buffer.contents buf)
              end
              else go (i + 1) rest))
    in
    go 0 tac_list

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
     | Ok g -> Ok (Goal.format g))

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
      | Ok g -> Goal.format g
      | Error _ -> "(goals unavailable)"
    in
    let clamped =
      if actual < steps then
        Printf.sprintf " (requested %d, only %d in history)" steps actual
      else ""
    in
    Ok (Printf.sprintf "Undid %d step(s)%s.\n%s" actual clamped goals_text)

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
