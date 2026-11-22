import Checkers.L1.Syntax

namespace Cqa.L1.ConstantAssertions
open Lean

private def constantAssertion (s : Syntax) : Bool :=
  (call `requireThat s || call `assertThat s) &&
    s[1].getArgs.size == 2 && s[1].getArgs.back?.any (named `true)

def check : AstCheck :=
  ⟨"constant-assertions", fun _ => "Assertion uses true and cannot detect an incorrect result.",
    "Assert the actual outcome.", findSyntax constantAssertion⟩

end Cqa.L1.ConstantAssertions
