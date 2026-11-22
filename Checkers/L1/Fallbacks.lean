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
  methodCall "getD" s || methodCall "getObjValD" s || methodCall "toOption" s ||
    let body := if s.isOfKind ``Parser.Term.doCatch then s[4]
      else if s.isOfKind ``Parser.Term.doCatchMatch then s[1] else .missing
    contains (fun t => (call `pure t && t[1].getArgs.back?.any constant) ||
      (t.isOfKind ``Parser.Term.doReturn && t[1].getArgs.back?.any constant)) body

private def message (s : Syntax) : String :=
  if methodCall "toOption" s then "Conversion to Option discards the error details."
  else if methodCall "getD" s || methodCall "getObjValD" s then
    "A default value may hide missing data."
  else "Exception handler contains a fallback result that may hide a failure."

def check : AstCheck :=
  ⟨"fallbacks", message,
    "Handle absence or errors explicitly unless recovery is intentional.", findSyntax fallback⟩

end Cqa.L1.Fallbacks
