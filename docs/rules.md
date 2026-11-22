# CQA rules for AI-generated code

**Source checked:** [Sapiens4 `dev/spec`](https://github.com/aleski-green/sapiens4/tree/dev/spec), 22 November 2026.  
**Purpose:** Catch incorrect behavior and unnecessary AI-generated complexity before merging.

```text
AI-generated PR
      |
      v
Check rules + collect evidence
      |
  +---+---------+--------+
  |             |        |
NO-GO        WARNING   COULD BE BETTER
  |             |        |
BLOCK         REVIEW    SUGGEST
```

Every finding must include **file/line, the violated rule, specific evidence, and a proposed fix**. An AI opinion without evidence is *not* a confirmed violation. Rules below are proposed checks, not claims that Sapiens4 violates them.

## NO-GO — Block merge when verified

### NG-01 · Missing required behavior
A required scenario is absent or returns the wrong outcome. Verify against requirements, not just the implementation.

```text
Requirement: save settings across restart
BAD:  save -> restart -> settings disappear
GOOD: save -> restart -> settings unchanged
```

**Existing good test:** [Release.lean — settings survive restart](https://github.com/aleski-green/sapiens4/blob/dev/spec/jobs/user/Release.lean).

### NG-02 · Broken security boundary
An unauthorized user can access or change protected data. Verify both the response *and* protected state.

```lean
-- Example: rejecting a request is not enough by itself
requireThat "denied" (reply.status == 403)
requireThat "state changed" (before == after)
```

**Existing good test:** [Access.lean — unauthorized requests and private data](https://github.com/aleski-green/sapiens4/blob/dev/spec/jobs/system/Access.lean).

### NG-03 · Lost data or broken recovery
A crash, restart, upgrade, or error destroys required data or fails to recover it.

```lean
-- Example: compare backup with original
requireThat "backup changed" (backup == previous)
```

**Existing good test:** [Recovery.lean — backup and restart checks](https://github.com/aleski-green/sapiens4/blob/dev/spec/jobs/system/Recovery.lean).

### NG-04 · Unsafe concurrency or retries
A race or retry violates a business rule (duplicate payment, two owners of one lock, etc.).

```text
BAD:  Agent A owns computer; Agent B also acquires it
GOOD: Agent B is refused until A releases it
```

**Existing good test:** [Recovery.lean — exclusive computer access](https://github.com/aleski-green/sapiens4/blob/dev/spec/jobs/system/Recovery.lean).

### NG-05 · Fake or weakened tests
A test always passes, checks only a mock, or removes an assertion to make CI green. **Prove it catches a known wrong result.**

```lean
-- BAD
requireThat "works" true
-- GOOD
requireThat "denied" (reply.status == 403)
```

### NG-06 · Fake formal proof
A claimed proof uses `sorry`, an unapproved axiom, or only proves an unrelated assumption.

```lean
-- BAD: accepted without proof
example : 1 + 1 = 2 := by sorry
-- GOOD: verified by Lean
example : 1 + 1 = 2 := by decide
```

**Important:** A Lean proof about a model does not automatically prove the running application follows that model.

### NG-07 · Required checks do not pass
Compilation fails; required behavioral checks fail, are skipped without approval, or return success despite failures.

```lean
-- GOOD: failed tests make the runner fail
return if failures == 0 then 0 else 1
```

**Existing good code:** [Main.lean — test-runner exit code](https://github.com/aleski-green/sapiens4/blob/dev/spec/Main.lean#L66-L79).

## WARNING — Review before merge

### W-01 · Weak domain types / missing ADTs
Using `String` or several booleans for a small fixed set of business states can allow invalid values.

```haskell
-- BAD: any string can be a status
type Status = String
-- BETTER
data Status = Pending | Running | Done
```

**Exception:** Strings are normal at JSON/HTTP boundaries; validate when converting to domain types.

### W-02 · Poor functional design
Pure computations unnecessarily depend on `IO` or mutable state, making logic harder to reason about.

```haskell
-- BAD (if no effects are needed)
isAllowed :: Role -> IO Bool
-- BETTER
isAllowed :: Role -> Bool
```

### W-03 · Duplicate functionality
AI introduces a second implementation where a suitable existing function already exists.

```text
BAD:  Module A -> validateAccess
      Module B -> checkPermission (same rule)
BETTER: both -> authorize
```

**Exception:** Keep separate functions when behavior, ownership, or security boundaries genuinely differ.

### W-04 · Unnecessary work, layers, or dependencies
A new wrapper, service, build step, or dependency has no clear purpose.

```text
BAD:  API -> Manager -> Coordinator -> Handler -> DB
BETTER (if enough): API -> Service -> DB
```

**Real `dev` review candidate:** [Main.lean lines 48–56](https://github.com/aleski-green/sapiens4/blob/dev/spec/Main.lean#L48-L56) launches [BrowserBuild.hs](https://github.com/aleski-green/sapiens4/blob/dev/spec/BrowserBuild.hs#L8-L31) **before** choosing `headless` / `browser` / `desktop`. This appears to rebuild browser fixtures even for `headless` runs. **Suggestion:** Build browser assets only for jobs that need them. This is an unnecessary-work concern, not a verified functional failure.

### W-05 · Speculative fallback hides failure
An AI-added default converts real errors into apparent success and makes failures harder to diagnose.

```haskell
-- BAD: treats any read error as empty state
loadState `catch` \_ -> pure emptyState
-- BETTER: report a typed failure
loadState :: IO (Either LoadError State)
```

**Severity note:** Escalate to NO-GO if the fallback can corrupt data or bypass security.

### W-06 · Excessive mocking
Tests only prove that mocks return what the test configured, not that real components cooperate.

```text
BAD:  mock API -> expected mock reply -> PASS
BETTER: real API -> real state -> verify outcome
```

**Exception:** Mock external providers to test controlled failures; keep the behavior under test real.

## COULD BE BETTER — Optional simplification

### CB-01 · Combine overlapping tests
Several tiny scenarios repeat expensive setup and cover pieces of one business flow.

```text
BEFORE: create / read / restart (three similar setups)
AFTER:  create -> read -> restart -> verify
```

Do not merge if one large scenario would make failures hard to locate.

### CB-02 · Reuse common test helpers
Do not recreate JSON assertions, polling, cleanup, or fixture setup in each test.

```lean
-- Example shared helper from Sapiens4
fieldsMatch actual expected
```

**Existing good example:** [Observations.lean — shared assertions](https://github.com/aleski-green/sapiens4/blob/dev/spec/pure/Observations.lean).

### CB-03 · Remove useless wrappers
A function that only forwards arguments and adds no meaning can often go.

```haskell
-- BAD: no new behavior or abstraction
getStatus x = readStatus x
-- BETTER: call readStatus directly
```

**Exception:** Keep wrappers that establish a real boundary, API contract, or useful domain vocabulary.

## Additional verified `dev` test-harness review candidates

These are concrete *risks in the code*, **not confirmed runtime defects**. They suggest useful future CQA rules about test reliability.

| Candidate | Link to real `dev` code | Why review it? | Suggested improvement |
|---|---|---|---|
| Port reservation race | [`spec/io/Relay.lean` lines 7–17](https://github.com/aleski-green/sapiens4/blob/dev/spec/io/Relay.lean#L7-L17) | Reserves an available port, then releases the socket before a new process binds it. Another process could take the port. | Keep reservation through handoff or let the relay bind port 0 and report its actual port. |
| Fixture can wait without a limit | [`spec/io/Provider.lean` line 20](https://github.com/aleski-green/sapiens4/blob/dev/spec/io/Provider.lean#L17-L21) | `while ... hold.pathExists` has no local timeout; a stuck fixture can keep waiting. | Add a deadline or explicit cancellation. |
| Browser build runs for headless tests | [`spec/Main.lean` lines 48–56](https://github.com/aleski-green/sapiens4/blob/dev/spec/Main.lean#L48-L56) | Builds browser assets before selecting the requested test group. | Select the group first, and run only its required setup. |

## How to verify the CQA rules themselves

```text
Each rule
  |
  +--> Known BAD example --> Must flag
  |
  +--> Known GOOD example -> Must accept
  |
  +--> Real repo case ----> Must show evidence
```

- **No evidence:** don't issue a confirmed finding.
- **No subjective auto-blocking:** AI can recommend; deterministic checks or reviewed evidence should support a NO-GO.
- **No duplicate findings:** report the root problem once, even if multiple rules detect it.
- **No silent test changes:** protected tests and acceptance criteria need explicit approval to change.

*Repository links target the `dev` branch and can change as it evolves. This was a targeted inspection of `spec`, not a comprehensive audit of the whole codebase.*
