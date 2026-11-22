import Checkers.L1.Syntax

namespace Cqa.L1.ProofPlaceholders
open Lean

private def proofPlaceholder (s : Syntax) : Bool :=
  s.isOfKind ``Parser.Term.sorry ||
    s.isOfKind `Lean.Parser.Tactic.tacticSorry || s.isOfKind `Lean.Parser.Tactic.tacticAdmit

def check : AstCheck :=
  ⟨"proof-placeholders", fun _ => "Proof is unfinished: sorry or admit bypasses the proof.",
    "Complete the proof if it is required.", findSyntax proofPlaceholder⟩

end Cqa.L1.ProofPlaceholders
