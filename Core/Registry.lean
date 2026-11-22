import Checkers.L0.KeywordScan
import Checkers.L0.SourceRisks
import Checkers.L1.Assertions
import Checkers.L1.ConstantAssertions
import Checkers.L1.ProofPlaceholders
import Checkers.L1.Fallbacks
import Checkers.L1.FixedWaits
import Checkers.L1.UnsafeIndexing
import Checkers.L2.Types
import Checkers.L2.Integrity
import Checkers.L2.Dependencies

namespace Cqa

def registeredTextChecks : Array TextCheck := #[L0.KeywordScan.check, L0.KeywordScan.codeCheck,
  L0.SourceRisks.secretsCheck, L0.SourceRisks.disabledCheck]

def registeredChecks : Array AstCheck := #[
  L1.ConstantAssertions.check, L1.ProofPlaceholders.check, L1.Fallbacks.check,
  L1.FixedWaits.check, L1.UnsafeIndexing.check, L1.Assertions.ignored, L1.Assertions.completion,
  L1.Assertions.states, L1.Assertions.exact
]

def registeredSemanticChecks : Array L2.Check := #[L2.Types.domain, L2.Types.purity,
  L2.Types.boundaries, L2.Integrity.proofCheck, L2.Integrity.registrationCheck, L2.Dependencies.check]

end Cqa
