import Checkers.L0.KeywordScan
import Checkers.L1.ConstantAssertions
import Checkers.L1.ProofPlaceholders
import Checkers.L1.Fallbacks
import Checkers.L1.FixedWaits
import Checkers.L1.UnsafeIndexing

namespace Cqa

def registeredTextChecks : Array TextCheck := #[L0.KeywordScan.check]

def registeredChecks : Array AstCheck := #[
  L1.ConstantAssertions.check, L1.ProofPlaceholders.check, L1.Fallbacks.check,
  L1.FixedWaits.check, L1.UnsafeIndexing.check
]

end Cqa
