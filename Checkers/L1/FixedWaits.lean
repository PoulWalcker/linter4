import Checkers.L1.Syntax

namespace Cqa.L1.FixedWaits
open Lean

def check : AstCheck :=
  ⟨"waits", "A call to IO.sleep was found.",
    "If this waits for readiness, verify readiness and bound the total wait.", findSyntax (call `IO.sleep)⟩

end Cqa.L1.FixedWaits
