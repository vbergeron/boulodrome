open Petanque

(* Declaration kinds worth an axiom audit -- the statements a user would
   expect "verified" to cover. Definitions/Inductives/Records are not
   included: [Print Assumptions] on them answers a different question
   (whether *building* the term used axioms) than the one this tool is
   for (did the LLM actually prove this claim). *)
let provable_kinds =
  [ "Theorem"; "Lemma"; "Corollary"; "Proposition"; "Fact"; "Remark"
  ; "Example"
  ]

let entry_kind (entry : Coq_init.toc_entry) =
  match entry.info with
  | Some (info :: _) -> info.detail
  | _ -> None

let closed_marker = "Closed under the global context"

(* [Print Assumptions] reports either the closed-context sentinel or an
   "Axioms:" header followed by one "name : type" line per axiom. *)
let axioms_of_report report =
  if Tools_helpers.contains ~needle:closed_marker report then []
  else
    String.split_on_char '\n' report
    |> List.map String.trim
    |> List.filter (fun line -> line <> "" && line <> "Axioms:")

let assumptions_for ~token ~st name =
  let tac =
    Printf.sprintf "%s %s." (Inspect.command_of_kind Inspect.Assumptions) name
  in
  match Agent.run ~token ~st ~tac () with
  | Error e -> Error (Agent.Error.to_string e.Request.Error.payload)
  | Ok rr ->
    let msgs = List.map (fun (_lvl, msg) -> msg) rr.Agent.Run_result.feedback in
    Ok (String.concat "\n" msgs)

let is_whitelisted ~allowed axiom =
  List.exists (fun a -> Tools_helpers.contains ~needle:a axiom) allowed

let check_one ~token ~st ~allowed name =
  match assumptions_for ~token ~st name with
  | Error e -> `Unchecked (Printf.sprintf "- %s: could not check (%s)" name e)
  | Ok report ->
    (match axioms_of_report report with
     | [] -> `Ok (Printf.sprintf "- %s: closed, no axioms" name)
     | axioms ->
       let flagged = List.filter (fun ax -> not (is_whitelisted ~allowed ax)) axioms in
       if flagged = [] then
         `Ok
           (Printf.sprintf "- %s: depends on whitelisted axiom(s):\n    %s"
              name
              (String.concat "\n    " axioms))
       else
         `Flagged
           (Printf.sprintf "- %s: DEPENDS ON UNLISTED AXIOM(S):\n    %s" name
              (String.concat "\n    " flagged)))

let run ~token ~file_path ?theorem_name ?allowed_axioms () =
  match Tools_helpers.build_doc ~token file_path with
  | Error e -> Error e
  | Ok doc ->
    let errors = Coq_init.doc_errors doc in
    if errors <> [] then
      let unique = List.sort_uniq String.compare errors in
      let shown = List.filteri (fun i _ -> i < 10) unique in
      Error
        (Printf.sprintf
           "NOT VERIFIED: %s has %d error(s); cannot check.\n\n\
            Document errors:\n\
            %s"
           file_path (List.length unique)
           (String.concat "\n" (List.map (fun e -> "  - " ^ e) shown)))
    else
      match Coq_init.get_toc ~token ~doc with
      | Error e ->
        Error
          (Printf.sprintf "TOC error: %s"
             (Agent.Error.to_string e.Request.Error.payload))
      | Ok toc ->
        let candidates =
          List.filter
            (fun (_name, entry) ->
              match entry_kind entry with
              | Some k -> List.mem k provable_kinds
              | None -> false)
            toc
        in
        let targets =
          match theorem_name with
          | None -> candidates
          | Some name -> List.filter (fun (n, _) -> n = name) candidates
        in
        (match theorem_name, targets with
         | Some name, [] ->
           Error
             (Printf.sprintf
                "No theorem/lemma named '%s' found in %s (it must be a \
                 Theorem, Lemma, Corollary, Proposition, Fact, Remark, or \
                 Example)."
                name file_path)
         | _, targets ->
           (match Agent.get_root_state ~doc () with
            | Error e ->
              Error
                (Printf.sprintf "Failed to get root state for %s: %s"
                   file_path
                   (Agent.Error.to_string e.Request.Error.payload))
            | Ok rr ->
              let st = rr.Agent.Run_result.st in
              let allowed = Option.value allowed_axioms ~default:[] in
              if targets = [] then
                Ok
                  (Printf.sprintf
                     "Verification of %s:\n\
                      No compile errors.\n\
                      No theorem/lemma/corollary/proposition/fact/remark/example \
                      found to check.\n\n\
                      VERIFIED: file compiles clean; nothing to audit for \
                      axioms."
                     file_path)
              else
                let results =
                  List.map
                    (fun (name, _entry) -> check_one ~token ~st ~allowed name)
                    targets
                in
                let lines =
                  List.map
                    (function `Ok s | `Flagged s | `Unchecked s -> s)
                    results
                in
                let all_ok =
                  List.for_all (function `Ok _ -> true | _ -> false) results
                in
                let verdict =
                  if all_ok then
                    "VERIFIED: file compiles clean and no unlisted axioms."
                  else
                    "NOT VERIFIED: see flagged item(s) above. Pass \
                     allowed_axioms to accept specific axioms."
                in
                Ok
                  (Printf.sprintf
                     "Verification of %s:\n\
                      No compile errors.\n\
                      %d theorem(s)/lemma(s) checked for axioms:\n\
                      %s\n\n\
                      %s"
                     file_path (List.length targets)
                     (String.concat "\n" lines) verdict)))
