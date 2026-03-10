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
  { name = "rocq_get_goals"
  ; description = "Get the current proof goals for a session"
  ; params = [ required_string "session_id" "Session identifier" ]
  ; handler =
      (fun args ->
        let* session_id = get_string args "session_id" in
        Get_goals.run ~token ~session_id ())
  }

let get_premises ~token : tool_def =
  { name = "rocq_get_premises"
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
  { name = "rocq_get_file_toc"
  ; description =
      "Get table of contents (definitions and theorems) for a Coq/Rocq file"
  ; params =
      [ required_string "file_path" "Absolute path to the Coq/Rocq file" ]
  ; handler =
      (fun args ->
        let* file_path = get_string args "file_path" in
        Get_file_toc.run ~token ~file_path ())
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
  ; version = "0.4.0"
  ; tools =
      [ start_proof ~token
      ; run_tactics ~token
      ; try_tactics ~token
      ; undo ~token
      ; get_goals ~token
      ; get_premises ~token
      ; get_file_toc ~token
      ; search ~token
      ; end_session
      ]
  }

let run ~token () = Mcp.run (config ~token)
