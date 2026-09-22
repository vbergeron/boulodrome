(** Boulodrome MCP server: tool definitions for Rocq/Petanque. *)

open Mcp

(* ------------------------------------------------------------------ *)
(* Parameters shared across several tools                              *)
(* ------------------------------------------------------------------ *)

let file_path_param =
  string_param ~name:"file_path" ~desc:"Absolute path to the Coq/Rocq file"

let file_path_opt_param =
  optional
    (string_param ~name:"file_path"
       ~desc:"Absolute path to a .v file (alternative to session_id)")

let session_id_param =
  string_param ~name:"session_id" ~desc:"Session identifier"

let session_id_opt_param =
  optional
    (string_param ~name:"session_id"
       ~desc:"Session identifier (provide this or file_path)")

let verbose_param =
  optional
    (bool_param ~name:"verbose"
       ~desc:"If true, show goal state after each tactic (default: false)")

let start_proof ~token : tool_def =
  tool ~name:"rocq_start_proof"
    ~description:
      "Start a proof session for a specific theorem in a Coq/Rocq file"
  |> field file_path_param
  |> field
       (string_param ~name:"theorem_name" ~desc:"Name of the theorem to prove")
  |> field
       (string_param ~name:"session_id"
          ~desc:"Unique identifier for this proof session")
  |> field
       (optional
          (string_param ~name:"pre_commands"
             ~desc:"Optional Coq commands to execute before starting the proof"))
  |> handle (fun file_path theorem_name session_id pre_commands ->
         Start_proof.run ~token ~file_path ~theorem_name ~session_id
           ?pre_commands ())

let run_tactics ~token : tool_def =
  tool ~name:"rocq_run_tactics"
    ~description:
      "Execute one or more tactics on the current proof state. Execution \
       stops at the first failure. Set verbose to true to see the goal \
       state after each tactic."
  |> field session_id_param
  |> field
       (array_param ~name:"tac_list"
          ~desc:
            "Tactic(s) to execute, e.g. [\"induction n.\", \"simpl.\", \"auto.\"]"
          String)
  |> field verbose_param
  |> handle (fun session_id tac_list verbose ->
         let verbose = Option.value verbose ~default:false in
         Tactics.run ~token ~session_id ~tac_list ~verbose ())

let try_tactics ~token : tool_def =
  tool ~name:"rocq_try_tactics"
    ~description:
      "Try each tactic independently on the current proof state WITHOUT \
       modifying the session. Every tactic in the list is run from the same \
       starting state, so you can compare alternatives even if some fail. \
       Use rocq_run_tactics to commit the chosen tactic."
  |> field session_id_param
  |> field
       (array_param ~name:"tac_list"
          ~desc:"Tactic(s) to try, e.g. [\"induction n.\", \"simpl.\", \"auto.\"]"
          String)
  |> field verbose_param
  |> handle (fun session_id tac_list verbose ->
         let verbose = Option.value verbose ~default:false in
         Tactics.try_run ~token ~session_id ~tac_list ~verbose ())

let get_goals ~token : tool_def =
  tool ~name:"rocq_goals" ~description:"Get the current proof goals for a session"
  |> field session_id_param
  |> handle (fun session_id -> Get_goals.run ~token ~session_id ())

let get_premises ~token : tool_def =
  tool ~name:"rocq_premises"
    ~description:
      "Get available premises (lemmas, definitions) for the current proof \
       state"
  |> field session_id_param
  |> handle (fun session_id -> Get_goals.premises ~token ~session_id ())

let get_file_toc ~token : tool_def =
  tool ~name:"rocq_file_toc"
    ~description:
      "Get table of contents (definitions and theorems) for a Coq/Rocq file"
  |> field file_path_param
  |> handle (fun file_path -> Get_file_toc.run ~token ~file_path ())

let diagnostics ~token : tool_def =
  tool ~name:"rocq_diagnostics"
    ~description:
      "Get all diagnostic messages (errors, warnings, etc.) for a Coq/Rocq \
       file. Use the optional severity parameter to filter to a single level."
  |> field file_path_param
  |> field
       (optional
          (string_param ~name:"severity"
             ~desc:
               "Filter by severity: \"error\", \"warning\", \"information\", \
                or \"hint\". If omitted, all diagnostics are returned."))
  |> handle (fun file_path sev_str ->
         let* severity =
           match sev_str with
           | None -> Ok None
           | Some s -> Diagnostics.severity_of_string s
         in
         Diagnostics.run ~token ~file_path ?severity ())

let search ~token : tool_def =
  tool ~name:"rocq_search"
    ~description:
      "Search for theorems, definitions, and other objects using Rocq's \
       Search command. The query is passed verbatim as the argument to the \
       Rocq Search/SearchPattern/SearchRewrite command.\n\n\
       Query syntax (for kind=\"search\", the default):\n\
       - Pattern: (_ + _ = _ + _)  -- type pattern with holes _ or ?n\n\
       - Name substring: \"assoc\"  -- quoted string, matches object names\n\
       - Notation: \"+\"  -- quoted, finds objects whose type uses this notation\n\
       - Qualifiers: hyp: concl: head: headhyp: headconcl: before a pattern \
       or string\n\
       - Negation: - query  -- exclude matching objects\n\
       - Kind filter: is:Lemma, is:Definition, is:Instance, is:Fixpoint, etc.\n\
       - Scope: ... inside ModuleName  or  ... outside ModuleName\n\
       - Disjunction: [ query1 | query2 ]\n\n\
       A pattern whose top level uses an infix operator (e.g. the sumbool \
       type `{n < m} + {n = m} + {m < n}`) needs outer parentheses, since \
       unparenthesized whitespace-separated tokens are otherwise split into \
       separate conjunctive query items. If a query without them hits this, \
       it is automatically retried wrapped in (...) before failing.\n\n\
       Examples:\n\
       - \"plus_comm\" -- find by name\n\
       - (_ + _ = _ + _) -- commutativity lemmas\n\
       - \"assoc\" -- all names containing assoc\n\
       - concl:(nat -> bool) -- functions returning bool in conclusion\n\
       - (_ * _ = _ * _) -\"trivial\" -- pattern, excluding names with trivial\n\
       - [ is:Lemma (_ + _) | is:Definition headconcl:nat ] -- disjunction\n\n\
       For kind=\"search_pattern\": matches the conclusion shape only.\n\
       For kind=\"search_rewrite\": finds rewrite lemmas where one side of an \
       equality matches the pattern.\n\n\
       Provide either session_id (to search in a proof context) or file_path \
       (to search from a file's root context). session_id takes precedence."
  |> field session_id_opt_param
  |> field file_path_opt_param
  |> field
       (string_param ~name:"query"
          ~desc:
            "Rocq search expression, passed verbatim (see description for syntax)")
  |> field
       (string_param ~name:"kind"
          ~desc:
            "Search command: \"search\", \"search_pattern\", or \
             \"search_rewrite\"")
  |> field
       (optional
          (int_param ~name:"max_results"
             ~desc:"Maximum number of results to return (default: 30)"))
  |> handle (fun session_id file_path query kind max_results ->
         let* source = Search.source_of_args ~session_id ~file_path in
         let* kind = Search.kind_of_string kind in
         Search.run ~token ~source ~query ~kind ?max_results ())

let inspect ~token : tool_def =
  tool ~name:"rocq_inspect"
    ~description:
      "Inspect a Rocq term or object using Check, Print, About, Locate, or \
       Print Assumptions. Returns type signatures, full definitions, \
       documentation, location information, or the axioms a proof depends \
       on.\n\n\
       Commands:\n\
       - \"check\": show the type of a term (e.g. \"Nat.add\")\n\
       - \"print\": show the full definition of an object\n\
       - \"about\": show information including implicit arguments and scopes\n\
       - \"locate\": show the full qualified name and module of an identifier\n\
       - \"assumptions\": list the axioms and admitted lemmas a theorem \
       transitively depends on (Print Assumptions), or \"Closed under the \
       global context\" if there are none -- use this to confirm a proof is \
       axiom-free before closing it out\n\n\
       Provide either session_id (to inspect in a proof context) or file_path \
       (to inspect from a file's root context). session_id takes precedence."
  |> field session_id_opt_param
  |> field file_path_opt_param
  |> field
       (string_param ~name:"command"
          ~desc:
            "Inspection command: \"check\", \"print\", \"about\", \"locate\", \
             or \"assumptions\"")
  |> field
       (string_param ~name:"term"
          ~desc:
            "The term, definition, or identifier to inspect (for \
             \"assumptions\", the fully-defined theorem or lemma name)")
  |> handle (fun session_id file_path command term ->
         let* source = Search.source_of_args ~session_id ~file_path in
         let* command = Inspect.kind_of_string command in
         Inspect.run ~token ~source ~command ~term ())

let verify ~token : tool_def =
  tool ~name:"rocq_verify"
    ~description:
      "Verify a Coq/Rocq file: confirm it compiles with no errors, then \
       audit every Theorem/Lemma/Corollary/Proposition/Fact/Remark/Example \
       in it with Print Assumptions, flagging any that depend on an axiom \
       or Admitted lemma not covered by allowed_axioms. Use this as the \
       final check before trusting a proof is done -- rocq_run_tactics \
       stopping only tells you the tactic script succeeded, not that the \
       file is free of Admitted/axioms.\n\n\
       Restrict the audit to a single theorem with theorem_name, or check \
       every provable statement in the file by omitting it. Pass \
       allowed_axioms to whitelist axioms that are expected/acceptable \
       (matched by substring against the full \"name : type\" line, so a \
       bare identifier is enough)."
  |> field file_path_param
  |> field
       (optional
          (string_param ~name:"theorem_name"
             ~desc:
               "If given, only audit this theorem/lemma instead of every \
                provable statement in the file"))
  |> field
       (optional
          (array_param ~name:"allowed_axioms"
             ~desc:
               "Axiom names (or substrings) that are acceptable dependencies; \
                any axiom not matching one of these is flagged"
             String))
  |> handle (fun file_path theorem_name allowed_axioms ->
         Verify.run ~token ~file_path ?theorem_name ?allowed_axioms ())

let undo ~token : tool_def =
  tool ~name:"rocq_undo"
    ~description:
      "Undo tactic steps in a proof session, restoring a previous proof \
       state. Every proof state reached by rocq_run_tactics is indexed \
       under an id (reported as `[state N]` in its output); pass that id as \
       proof_state_id to jump straight back to it instead of counting \
       steps. proof_state_id takes precedence over steps when both are \
       given. Returns the goals after undoing."
  |> field session_id_param
  |> field
       (optional
          (int_param ~name:"steps" ~desc:"Number of steps to undo (default: 1)"))
  |> field
       (optional
          (int_param ~name:"proof_state_id"
             ~desc:
               "Id of a proof state previously reported by rocq_run_tactics \
                (or 0 for the state right after rocq_start_proof) to restore \
                directly, instead of counting steps back"))
  |> handle (fun session_id steps proof_state_id ->
         match proof_state_id with
         | Some proof_state_id ->
           Undo.run_to ~token ~session_id ~proof_state_id ()
           |> Result.map_error Session.error_to_string
         | None ->
           let steps = Option.value steps ~default:1 in
           Undo.run ~token ~session_id ~steps ()
           |> Result.map_error Session.error_to_string)

let proof_script ~token : tool_def =
  tool ~name:"rocq_proof_script"
    ~description:
      "Get the exact sequence of tactics committed so far in a session, in \
       the order they were run and in a form valid to paste verbatim \
       between `Proof.` and `Qed.` in the source file. This is the actual \
       committed record, not a transcription -- use it instead of \
       reconstructing the script by hand from the conversation, which can \
       silently break `;`-chained tactics that apply across multiple \
       goals."
  |> field session_id_param
  |> handle (fun session_id -> Proof_script.run ~token ~session_id ())

let list_sessions ~token : tool_def =
  handle0 ~name:"rocq_list_sessions"
    ~description:
      "List all currently open proof sessions, with the file path, theorem \
       name, and proof status (complete, in progress, or unknown) for each."
    (fun () -> List_sessions.run ~token ())

let end_session : tool_def =
  tool ~name:"rocq_end_session"
    ~description:"Close a proof session and free its state"
  |> field session_id_param
  |> handle (fun session_id ->
         Session.remove session_id |> Result.map_error Session.error_to_string)

let config ~token : Mcp.config =
  { name = "boulodrome"
  ; version = "0.6.1"
  ; tools =
      [ start_proof ~token
      ; run_tactics ~token
      ; try_tactics ~token
      ; undo ~token
      ; get_goals ~token
      ; get_premises ~token
      ; get_file_toc ~token
      ; diagnostics ~token
      ; search ~token
      ; inspect ~token
      ; verify ~token
      ; proof_script ~token
      ; list_sessions ~token
      ; end_session
      ]
  }

let run ~token () = Mcp.run (config ~token)
