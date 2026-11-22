import Checkers.L1.Syntax

namespace Cqa.L1.ProofPlaceholders
open Lean

private def proofPlaceholder (s : Syntax) : Bool :=
  s.isOfKind ``Parser.Term.sorry ||
    s.isOfKind `Lean.Parser.Tactic.tacticSorry || s.isOfKind `Lean.Parser.Tactic.tacticAdmit

def check : AstCheck :=
  ⟨"proof-placeholders", "A sorry or admit proof placeholder was found.",
    "Complete the proof if required, then check the axioms it depends on.", findSyntax proofPlaceholder⟩

end Cqa.L1.ProofPlaceholders
