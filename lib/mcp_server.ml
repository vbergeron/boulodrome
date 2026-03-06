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
        Tools.start_proof ~token ~file_path ~theorem_name ~session_id
          ?pre_commands ())
  }

let run_tactic ~token : tool_def =
  { name = "rocq_run_tactic"
  ; description = "Execute a tactic or command on the current proof state"
  ; params =
      [ required_string "session_id" "Session identifier"
      ; required_string "tac"
          "Tactic or command to execute (e.g. 'induction n.', 'auto.')"
      ; optional_int "timeout" "Optional timeout in seconds"
      ]
  ; handler =
      (fun args ->
        let* session_id = get_string args "session_id" in
        let* tac = get_string args "tac" in
        Tools.run_tactic ~token ~session_id ~tac ())
  }

let get_goals ~token : tool_def =
  { name = "rocq_get_goals"
  ; description = "Get the current proof goals for a session"
  ; params = [ required_string "session_id" "Session identifier" ]
  ; handler =
      (fun args ->
        let* session_id = get_string args "session_id" in
        Tools.get_goals ~token ~session_id ())
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
        Tools.get_premises ~token ~session_id ())
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
        Tools.get_file_toc ~token ~file_path ())
  }

let search ~token : tool_def =
  { name = "rocq_search"
  ; description =
      "Search for theorems, definitions, and other objects in the current \
       context"
  ; params =
      [ required_string "session_id" "Session identifier"
      ; required_string "query"
          "Search query (e.g. 'plus_comm', 'nat -> nat')"
      ]
  ; handler =
      (fun args ->
        let* session_id = get_string args "session_id" in
        let* query = get_string args "query" in
        Tools.search ~token ~session_id ~query ())
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
        Tools.undo ~token ~session_id ~steps ())
  }

let run_tactics ~token : tool_def =
  { name = "rocq_run_tactics"
  ; description =
      "Run multiple tactics in sequence, stopping at the first failure. On \
       failure, the proof state stays at the last successful tactic and the \
       response reports which tactic failed. Tactics are newline-separated."
  ; params =
      [ required_string "session_id" "Session identifier"
      ; required_string "tactics"
          "Newline-separated list of tactics to execute in order"
      ]
  ; handler =
      (fun args ->
        let* session_id = get_string args "session_id" in
        let* tactics = get_string args "tactics" in
        Tools.run_tactics ~token ~session_id ~tactics ())
  }

let end_session : tool_def =
  { name = "rocq_end_session"
  ; description = "Close a proof session and free its state"
  ; params = [ required_string "session_id" "Session identifier to close" ]
  ; handler =
      (fun args ->
        let* session_id = get_string args "session_id" in
        Session.remove session_id)
  }

let config ~token : Mcp.config =
  { name = "boulodrome"
  ; version = "0.1.0"
  ; tools =
      [ start_proof ~token
      ; run_tactic ~token
      ; run_tactics ~token
      ; undo ~token
      ; get_goals ~token
      ; get_premises ~token
      ; get_file_toc ~token
      ; search ~token
      ; end_session
      ]
  }

let run ~token () = Mcp.run (config ~token)
