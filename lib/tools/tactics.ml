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

(* Header + feedback are always shown. The goal state itself is shown
   exactly once per tactic: always on completion (it's the one thing that
   matters), always on the last tactic of a batch (so the final state is
   never left unshown), and on every step when [verbose] (to trace
   progress across a multi-tactic batch). *)
let report_step buf ~verbose ~is_last ~idx ~total ~tac ~goals_text ~complete
    ~feedback =
  Buffer.add_string buf
    (Printf.sprintf "Executed (%d/%d): %s\n" (idx + 1) total tac);
  List.iter (fun l -> Buffer.add_string buf (l ^ "\n")) feedback;
  if complete || verbose || is_last then begin
    Buffer.add_string buf goals_text;
    Buffer.add_char buf '\n'
  end

let report_failure buf ~idx ~total ~tac ~error ~goals_text =
  Buffer.add_string buf
    (Printf.sprintf "Tactic %d/%d failed: %s\nError: %s\n\
                     State is at tactic %d. Current goals:\n%s"
       (idx + 1) total tac error idx goals_text)

let exec_one ~token ~st buf ~verbose ~is_last ~idx ~total ~tac =
  match Agent.run ~token ~st ~tac () with
  | Error e ->
    let goals_text, _ = query_goals ~token ~st ~fallback_complete:false in
    let error = Agent.Error.to_string e.Request.Error.payload in
    report_failure buf ~idx ~total ~tac ~error ~goals_text;
    Ok (st, Complete)
  | Ok rr ->
    let st' = rr.Agent.Run_result.st in
    let goals_text, complete =
      query_goals ~token ~st:st'
        ~fallback_complete:rr.Agent.Run_result.proof_finished
    in
    let feedback = format_feedback rr in
    report_step buf ~verbose ~is_last ~idx ~total ~tac ~goals_text ~complete
      ~feedback;
    Ok (st', if complete then Complete else Continue)

let run ~token ~session_id ~tac_list ~verbose () =
  match tac_list with
  | [] -> Error "No tactics provided."
  | _ ->
    (match Session.get session_id with
     | Error e -> Error (Session.error_to_string e)
     | Ok st ->
       let total = List.length tac_list in
       let buf = Buffer.create 256 in
       let rec go idx st = function
         | [] -> Ok (Buffer.contents buf)
         | tac :: rest ->
           let is_last = rest = [] in
           (match exec_one ~token ~st buf ~verbose ~is_last ~idx ~total ~tac with
            | Error e -> Error e
            | Ok (_, Complete) -> Ok (Buffer.contents buf)
            | Ok (st', Continue) ->
              Session.set session_id st';
              go (idx + 1) st' rest)
       in
       go 0 st tac_list)

let try_run ~token ~session_id ~tac_list ~verbose:_ () =
  match tac_list with
  | [] -> Error "No tactics provided."
  | _ ->
    (match Session.get session_id with
     | Error e -> Error (Session.error_to_string e)
     | Ok st ->
       let total = List.length tac_list in
       let buf = Buffer.create 256 in
       List.iteri
         (fun idx tac ->
           ignore
             (exec_one ~token ~st buf ~verbose:true ~is_last:true ~idx ~total
                ~tac))
         tac_list;
       Ok (Buffer.contents buf))
