import Checkers.L1.Syntax

namespace Cqa.L1.ProofPlaceholders
open Lean

private def proofPlaceholder (s : Syntax) : Bool :=
  s.isOfKind ``Parser.Term.sorry ||
    s.isOfKind `Lean.Parser.Tactic.tacticSorry || s.isOfKind `Lean.Parser.Tactic.tacticAdmit

def check : AstCheck :=
  ⟨"proof-placeholders", "Proof placeholder; requiredness and trust need L2.",
    "Complete a required proof and check its transitive axioms.", findSyntax proofPlaceholder⟩

end Cqa.L1.ProofPlaceholders
