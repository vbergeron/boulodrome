open Petanque

type step_result = Complete | Continue

let query_goals ~token ~st ~fallback_complete =
  match Agent.goals ~token ~st () with
  | Ok g -> (Goal.format g, Goal.are_complete g)
  | Error _ -> ("(goals unavailable)", fallback_complete)

let format_feedback (rr : Agent.State.t Agent.Run_result.t) =
  List.filter_map
    (fun (lvl, msg) ->
      if lvl > 0 then Some (Printf.sprintf "[level %d] %s" lvl msg)
      else None)
    rr.Agent.Run_result.feedback

let report_step buf ~verbose ~idx ~total ~tac ~goals_text ~feedback =
  Buffer.add_string buf
    (Printf.sprintf "Executed (%d/%d): %s\n" (idx + 1) total tac);
  List.iter (fun l -> Buffer.add_string buf (l ^ "\n")) feedback;
  if verbose || total = 1 then begin
    Buffer.add_string buf goals_text;
    Buffer.add_char buf '\n'
  end

let report_failure buf ~idx ~total ~tac ~error ~goals_text =
  Buffer.add_string buf
    (Printf.sprintf "Tactic %d/%d failed: %s\nError: %s\n\
                     State is at tactic %d. Current goals:\n%s"
       (idx + 1) total tac error idx goals_text)

let report_final buf ~goals_text ~complete =
  let status = if complete then "Proof complete!" else "Proof in progress." in
  Buffer.add_string buf (Printf.sprintf "%s\n" status);
  Buffer.add_string buf goals_text

let exec_one ~token ~session_id buf ~verbose ~idx ~total ~tac =
  match Session.get session_id with
  | Error e -> Error e
  | Ok st ->
    (match Agent.run ~token ~st ~tac () with
     | Error e ->
       let goals_text, _ = query_goals ~token ~st ~fallback_complete:false in
       let error = Agent.Error.to_string e.Request.Error.payload in
       report_failure buf ~idx ~total ~tac ~error ~goals_text;
       Ok Complete
     | Ok rr ->
       Session.set session_id rr.Agent.Run_result.st;
       let goals_text, complete =
         query_goals ~token ~st:rr.Agent.Run_result.st
           ~fallback_complete:rr.Agent.Run_result.proof_finished
       in
       let feedback = format_feedback rr in
       report_step buf ~verbose ~idx ~total ~tac ~goals_text ~feedback;
       if complete then begin
         Buffer.add_string buf "No remaining goals — proof complete!\n";
         Ok Complete
       end
       else Ok Continue)

let run ~token ~session_id ~tac_list ~verbose () =
  match tac_list with
  | [] -> Error "No tactics provided."
  | _ ->
    let total = List.length tac_list in
    let buf = Buffer.create 256 in
    let rec go idx = function
      | [] ->
        (match Session.get session_id with
         | Error e -> Error e
         | Ok st ->
           let goals_text, complete = query_goals ~token ~st ~fallback_complete:false in
           report_final buf ~goals_text ~complete;
           Ok (Buffer.contents buf))
      | tac :: rest ->
        (match exec_one ~token ~session_id buf ~verbose ~idx ~total ~tac with
         | Error e -> Error e
         | Ok Complete -> Ok (Buffer.contents buf)
         | Ok Continue -> go (idx + 1) rest)
    in
    go 0 tac_list
