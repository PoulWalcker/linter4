import Checkers.L1.Syntax

namespace Cqa.L1.FixedWaits
open Lean

private def statements (s : Syntax) : Array Syntax :=
  (if s.isOfKind ``Parser.Term.doSeqBracketed then s[1] else s[0]).getArgs.map (·[0])

private def throws (s : Syntax) : Bool :=
  match s with
  | `($f <| $_) => named `throw f
  | _ => call `throw s

private partial def waits (root : Syntax) : Array Syntax :=
  visit root #[]
where
  visit s found :=
    if isQuotation s then found else
    if s.isOfKind ``Parser.Term.doRepeat then
      let steps := statements s[3]
      let guards := steps.filter (·.isOfKind ``Parser.Term.doIf)
      let ready := guards.any fun guard => (statements guard[3]).any (·.isOfKind ``Parser.Term.doReturn)
      let deadline := guards.any fun guard =>
        !(findSyntax (named `IO.monoMsNow) guard[1]).isEmpty &&
          (statements guard[3]).any (fun stmt => stmt.isOfKind ``Parser.Term.doExpr && throws stmt[0])
      if ready && deadline then
        steps.foldl (fun acc step =>
          if step.isOfKind ``Parser.Term.doExpr && call `IO.sleep step[0] then acc else visit step acc) found
      else s.getArgs.foldl (fun acc child => visit child acc) found
    else s.getArgs.foldl (fun acc child => visit child acc)
      (if call `IO.sleep s then found.push s else found)

def check : AstCheck :=
  ⟨"waits", fun _ => "Timed waiting may make this test unstable.",
    "If waiting for readiness, check the condition with a timeout.", waits⟩

end Cqa.L1.FixedWaits
