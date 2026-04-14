open Petanque

type kind = Check | Print | About | Locate

let kind_of_string = function
  | "check" -> Ok Check
  | "print" -> Ok Print
  | "about" -> Ok About
  | "locate" -> Ok Locate
  | s ->
    Error
      (Printf.sprintf
         "Unknown command '%s'. Use \"check\", \"print\", \"about\", or \
          \"locate\"."
         s)

let command_of_kind = function
  | Check -> "Check"
  | Print -> "Print"
  | About -> "About"
  | Locate -> "Locate"

let run ~token ~source ~command ~term () =
  match Search.get_state ~token source with
  | Error e -> Error e
  | Ok st ->
    let cmd = command_of_kind command in
    let tac = Printf.sprintf "%s %s." cmd term in
    (match Agent.run ~token ~st ~tac () with
     | Error e ->
       Error
         (Printf.sprintf "%s error: %s" cmd
            (Agent.Error.to_string e.Request.Error.payload))
     | Ok rr ->
       let results =
         List.map (fun (_lvl, msg) -> msg) rr.Agent.Run_result.feedback
       in
       if results = [] then Ok (Printf.sprintf "No output for: %s %s" cmd term)
       else Ok (String.concat "\n" results))
