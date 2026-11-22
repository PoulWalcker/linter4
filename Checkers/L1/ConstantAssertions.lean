import Checkers.L1.Syntax

namespace Cqa.L1.ConstantAssertions
open Lean

private def constantAssertion (s : Syntax) : Bool :=
  (call `requireThat s || call `assertThat s) &&
    s[1].getArgs.size == 2 && s[1].getArgs.back?.any (named `true)

def check : AstCheck :=
  ⟨"constant-assertions", "Assertion receives literal true; callee is unresolved at L1.",
    "Assert an observed outcome; verify that a known wrong outcome fails.", findSyntax constantAssertion⟩

end Cqa.L1.ConstantAssertions
