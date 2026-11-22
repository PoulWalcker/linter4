import Checkers.L1.Syntax

namespace Cqa.L1.Fallbacks
open Lean

private def constant (s : Syntax) : Bool :=
  let s := Parser.Term.dropParens s
  s.isOfKind strLitKind || s.isOfKind numLitKind ||
    named `true s || named `false s || named `none s ||
    (s.isOfKind ``Parser.Term.tuple && s[1].getArgs.isEmpty)

private partial def contains (p : Syntax → Bool) (s : Syntax) : Bool :=
  !isQuotation s && !s.isOfKind ``Parser.Term.doCatch &&
    !s.isOfKind ``Parser.Term.doCatchMatch && (p s || s.getArgs.any (contains p))

private def fallback (s : Syntax) : Bool :=
  methodCall "getD" s || call `Except.toOption s ||
    (s.isOfKind ``Parser.Term.doCatch &&
      contains (fun t => call `pure t && t[1].getArgs.back?.any constant) s[4])

def check : AstCheck :=
  ⟨"fallbacks", "A getD call, Except.toOption call, or constant pure expression in a catch was found.",
    "Check whether the default or recovery is intentional and preserves required failures.", findSyntax fallback⟩

end Cqa.L1.Fallbacks
