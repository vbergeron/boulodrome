(** Boulodrome MCP server: tool definitions for Rocq/Petanque. *)

open Mcp

let start_proof ~token : tool_def =
  { name = "rocq_start_proof"
  ; description =
      "Start a proof session for a specific theorem in a Coq/Rocq file"
  ; params =
      [ required_string "file_path" "Absolute path to the Coq/Rocq file"
      ; required_string "theorem_name" "Name of the theorem to prove"
      ; required_string "session_id"
          "Unique identifier for this proof session"
      ; optional_string "pre_commands"
          "Optional Coq commands to execute before starting the proof"
      ]
  ; handler =
      (fun args ->
        let* file_path = get_string args "file_path" in
        let* theorem_name = get_string args "theorem_name" in
        let* session_id = get_string args "session_id" in
        let pre_commands = get_string_opt args "pre_commands" in
        Start_proof.run ~token ~file_path ~theorem_name ~session_id
          ?pre_commands ())
  }

let run_tactics ~token : tool_def =
  { name = "rocq_run_tactics"
  ; description =
      "Execute one or more tactics on the current proof state. Execution \
       stops at the first failure. Set verbose to true to see the goal \
       state after each tactic."
  ; params =
      [ required_string "session_id" "Session identifier"
      ; required_string_array "tac_list"
          "Tactic(s) to execute, e.g. [\"induction n.\", \"simpl.\", \"auto.\"]"
      ; optional_bool "verbose"
          "If true, show goal state after each tactic (default: false)"
      ]
  ; handler =
      (fun args ->
        let* session_id = get_string args "session_id" in
        let* tac_list = get_string_list args "tac_list" in
        let verbose =
          match get_bool_opt args "verbose" with Some b -> b | None -> false
        in
        Tactics.run ~token ~session_id ~tac_list ~verbose ())
  }

let try_tactics ~token : tool_def =
  { name = "rocq_try_tactics"
  ; description =
      "Try each tactic independently on the current proof state WITHOUT \
       modifying the session. Every tactic in the list is run from the same \
       starting state, so you can compare alternatives even if some fail. \
       Use rocq_run_tactics to commit the chosen tactic."
  ; params =
      [ required_string "session_id" "Session identifier"
      ; required_string_array "tac_list"
          "Tactic(s) to try, e.g. [\"induction n.\", \"simpl.\", \"auto.\"]"
      ; optional_bool "verbose"
          "If true, show goal state after each tactic (default: false)"
      ]
  ; handler =
      (fun args ->
        let* session_id = get_string args "session_id" in
        let* tac_list = get_string_list args "tac_list" in
        let verbose =
          match get_bool_opt args "verbose" with Some b -> b | None -> false
        in
        Tactics.try_run ~token ~session_id ~tac_list ~verbose ())
  }

let get_goals ~token : tool_def =
  { name = "rocq_goals"
  ; description = "Get the current proof goals for a session"
  ; params = [ required_string "session_id" "Session identifier" ]
  ; handler =
      (fun args ->
        let* session_id = get_string args "session_id" in
        Get_goals.run ~token ~session_id ())
  }

let get_premises ~token : tool_def =
  { name = "rocq_premises"
  ; description =
      "Get available premises (lemmas, definitions) for the current proof \
       state"
  ; params = [ required_string "session_id" "Session identifier" ]
  ; handler =
      (fun args ->
        let* session_id = get_string args "session_id" in
        Get_goals.premises ~token ~session_id ())
  }

let get_file_toc ~token : tool_def =
  { name = "rocq_file_toc"
  ; description =
      "Get table of contents (definitions and theorems) for a Coq/Rocq file"
  ; params =
      [ required_string "file_path" "Absolute path to the Coq/Rocq file" ]
  ; handler =
      (fun args ->
        let* file_path = get_string args "file_path" in
        Get_file_toc.run ~token ~file_path ())
  }

let diagnostics ~token : tool_def =
  { name = "rocq_diagnostics"
  ; description =
      "Get all diagnostic messages (errors, warnings, etc.) for a Coq/Rocq \
       file. Use the optional severity parameter to filter to a single level."
  ; params =
      [ required_string "file_path" "Absolute path to the Coq/Rocq file"
      ; optional_string "severity"
          "Filter by severity: \"error\", \"warning\", \"information\", or \
           \"hint\". If omitted, all diagnostics are returned."
      ]
  ; handler =
      (fun args ->
        let* file_path = get_string args "file_path" in
        let sev_str = get_string_opt args "severity" in
        let* severity =
          match sev_str with
          | None -> Ok None
          | Some s -> Diagnostics.severity_of_string s
        in
        Diagnostics.run ~token ~file_path ?severity ())
  }

let search ~token : tool_def =
  { name = "rocq_search"
  ; description =
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
  ; params =
      [ optional_string "session_id"
          "Session identifier (provide this or file_path)"
      ; optional_string "file_path"
          "Absolute path to a .v file (alternative to session_id)"
      ; required_string "query"
          "Rocq search expression, passed verbatim (see description for syntax)"
      ; required_string "kind"
          "Search command: \"search\", \"search_pattern\", or \
           \"search_rewrite\""
      ; optional_int "max_results"
          "Maximum number of results to return (default: 30)"
      ]
  ; handler =
      (fun args ->
        let session_id = get_string_opt args "session_id" in
        let file_path = get_string_opt args "file_path" in
        let* source = Search.source_of_args ~session_id ~file_path in
        let* query = get_string args "query" in
        let* kind = get_string args "kind" in
        let* kind = Search.kind_of_string kind in
        let max_results = get_int_opt args "max_results" in
        Search.run ~token ~source ~query ~kind ?max_results ())
  }

let inspect ~token : tool_def =
  { name = "rocq_inspect"
  ; description =
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
  ; params =
      [ optional_string "session_id"
          "Session identifier (provide this or file_path)"
      ; optional_string "file_path"
          "Absolute path to a .v file (alternative to session_id)"
      ; required_string "command"
          "Inspection command: \"check\", \"print\", \"about\", \"locate\", \
           or \"assumptions\""
      ; required_string "term"
          "The term, definition, or identifier to inspect (for \
           \"assumptions\", the fully-defined theorem or lemma name)"
      ]
  ; handler =
      (fun args ->
        let session_id = get_string_opt args "session_id" in
        let file_path = get_string_opt args "file_path" in
        let* source = Search.source_of_args ~session_id ~file_path in
        let* command = get_string args "command" in
        let* command = Inspect.kind_of_string command in
        let* term = get_string args "term" in
        Inspect.run ~token ~source ~command ~term ())
  }

let undo ~token : tool_def =
  { name = "rocq_undo"
  ; description =
      "Undo the last N tactic steps in a proof session, restoring a previous \
       proof state. Returns the goals after undoing."
  ; params =
      [ required_string "session_id" "Session identifier"
      ; optional_int "steps" "Number of steps to undo (default: 1)"
      ]
  ; handler =
      (fun args ->
        let* session_id = get_string args "session_id" in
        let steps =
          match get_int_opt args "steps" with Some n -> n | None -> 1
        in
        Undo.run ~token ~session_id ~steps ()
        |> Result.map_error Session.error_to_string)
  }

let proof_script ~token : tool_def =
  { name = "rocq_proof_script"
  ; description =
      "Get the exact sequence of tactics committed so far in a session, in \
       the order they were run and in a form valid to paste verbatim \
       between `Proof.` and `Qed.` in the source file. This is the actual \
       committed record, not a transcription -- use it instead of \
       reconstructing the script by hand from the conversation, which can \
       silently break `;`-chained tactics that apply across multiple \
       goals."
  ; params = [ required_string "session_id" "Session identifier" ]
  ; handler =
      (fun args ->
        let* session_id = get_string args "session_id" in
        Proof_script.run ~token ~session_id ())
  }

let list_sessions ~token : tool_def =
  { name = "rocq_list_sessions"
  ; description =
      "List all currently open proof sessions, with the file path, theorem \
       name, and proof status (complete, in progress, or unknown) for each."
  ; params = []
  ; handler = (fun _args -> List_sessions.run ~token ())
  }

let end_session : tool_def =
  { name = "rocq_end_session"
  ; description = "Close a proof session and free its state"
  ; params = [ required_string "session_id" "Session identifier to close" ]
  ; handler =
      (fun args ->
        let* session_id = get_string args "session_id" in
        Session.remove session_id
        |> Result.map_error Session.error_to_string)
  }

let config ~token : Mcp.config =
  { name = "boulodrome"
  ; version = "0.5.0"
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
      ; proof_script ~token
      ; list_sessions ~token
      ; end_session
      ]
  }

let run ~token () = Mcp.run (config ~token)
