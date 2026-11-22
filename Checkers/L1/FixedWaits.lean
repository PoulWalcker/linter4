import Checkers.L1.Syntax

namespace Cqa.L1.FixedWaits
open Lean

def check : AstCheck :=
  ⟨"waits", "Delay call; review completion and cancellation conditions.",
    "Prefer an observable event for completion; bound polling.", findSyntax (call `IO.sleep)⟩

end Cqa.L1.FixedWaits
