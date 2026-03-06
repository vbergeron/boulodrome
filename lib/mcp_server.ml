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
  ; description =
      "Execute one or more tactics on the current proof state. Multiple \
       tactics can be provided as newline-separated lines; execution stops \
       at the first failure. Set verbose to true to see the goal state \
       after each tactic (useful for debugging multi-step sequences)."
  ; params =
      [ required_string "session_id" "Session identifier"
      ; required_string "tac"
          "Tactic(s) to execute (e.g. 'induction n.' or multiple \
           newline-separated tactics)"
      ; optional_bool "verbose"
          "If true, show goal state after each tactic (default: false)"
      ]
  ; handler =
      (fun args ->
        let* session_id = get_string args "session_id" in
        let* tac = get_string args "tac" in
        let verbose =
          match get_bool_opt args "verbose" with Some b -> b | None -> false
        in
        Tools.run_tactic ~token ~session_id ~tac ~verbose ())
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
      ; undo ~token
      ; get_goals ~token
      ; get_premises ~token
      ; get_file_toc ~token
      ; search ~token
      ; end_session
      ]
  }

let run ~token () = Mcp.run (config ~token)
