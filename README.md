# Linter4

Scans `.lean` source text at L0, analyzes syntax at L1, and checks compiled Lean
test declarations at L2. The toolchain is Lean 4.35.0.

```bash
lake build
lake exe linter4 /path/to/repository
```

`rules.json` is loaded from the current directory by default. It defines rule
IDs, names, severity, enabled status and checker assignments. Changes take effect
without recompilation. One rule can select several checkers. Unknown fields,
checker IDs, unsupported levels and an empty enabled selection are errors.
There is one mode: every invocation runs all enabled checks together. With no
path, the current directory is scanned. The text report is printed to stdout;
the full JSON report is saved as `linter4-report.json` in the current directory.
There are no level or output switches.

L0 and L1 read the same `.lean` source files in one pass. Each file is counted
once. L0 findings are retained even when L1 cannot parse the file; such a file
is excluded from the fully checked count and listed under scan errors.

| L0 scenario | Signal |
|---|---|
| Incomplete proofs | Code tokens `sorry`, `admit`, and `axiom`. An axiom declaration is a review candidate. |
| Unsafe operations | Code tokens `unsafe`, `partial`, and `panic!`. |
| Arbitrary waits | `IO.sleep` in code. |
| Hidden errors | `catch`, defaults, and error conversions such as `toOption`. |
| Ignored results | `discard` and explicit wildcard bindings `let _`. |
| Debug code | `dbg_trace` in code and text markers `TODO` and `FIXME`. |
| Hardcoded secrets | Recognizable credential shapes, nonempty literals under credential-like names, and private key headers. Values are redacted. |
| Disabled tests | Commented test declarations, known skip markers, and disabling flags in test context. |

Both `keyword-scan` and `code-markers` take `patterns`, an array of non-blank,
single-line strings. `keyword-scan` searches raw text. `code-markers` checks word
boundaries and masks comments and literals before matching. This is a lexical
scan. It does not expand macros or inspect expressions inside interpolated strings.

| Checker | Default rule | L1 observation |
|---|---|---|
| `unchecked-access` | EXTRA-ACCESS | `xs[i]!`, `getElem!`, or `get!` without a recognized local bounds check |
| `ignored-assertions` | NG-05 | A recognized assertion is passed directly to `discard` or bound to `let _` |
| `constant-assertions`, `completion-only` | NG-05 | Literal `true` or a standalone assertion of success, exit code, or completion state |
| `fallbacks` | W-05 | Calls such as `getD` or `toOption`, or a catch supplying a constant result |
| `waits` | EXTRA-WAIT | `IO.sleep` outside a recognized readiness polling loop with a deadline |
| `string-states` | W-01 | The same state-like expression compared against distinct string literals |
| `exact-expectations` | EXTRA-EXPECTATION | A recognized assertion compares against an exact scalar or collection literal |
| `proof-placeholders` | NG-06 | Term `sorry`, tactic `sorry` or `admit` |

The complete policy descriptions are in [docs/rules.md](docs/rules.md).
[Additional examples](docs/sapiens4-findings.md) supply investigation targets.
`EXTRA-*` IDs are additional checks, separate from the main document's numbering.

L0 and L1 findings are **review candidates**, including findings for a `no-go` policy.
Reports include the checker, rule, severity, file, one-based line/column, source
evidence, explanation and suggested action. Evidence overlapping a detected
credential is redacted. Array bounds, allowed states, process waits and assertion
strictness may depend on the contract. Findings need human review in that context.

The text report groups issues by file. Each row shows the line and column,
severity, problem, suggested action, level and rule. Severity labels are
`NO-GO`, `Warning`, and `Could be better`. The final summary counts all issues
and each severity separately. Illustrative output:

```text
Linter4
Levels: L0, L1
Checked 23/23 files

spec/Example.lean
  12:18  NO-GO           Proof uses sorry. Complete the proof. [L1/NG-06]
  20:9   Warning         Default may hide missing data. Handle absence. [L1/W-05]
  31:4   Could be better TODO marks unfinished work. Resolve the marker. [L0/EXTRA-TASK]

3 issues: 1 NO-GO, 1 Warning, 1 Could be better
Scan errors: 0
```

The checked count covers the source scan; L2 reports its compiled-module scope
separately when configured. Findings need review; their severity alone does not
establish a confirmed defect. JSON also
includes source evidence, checker IDs, and errors. Its `level` is `FULL`, and
`levels` lists the enabled levels; each finding and error retains its own level.

`0` means the scan completed in its declared scope; `2` means invalid input,
configuration, I/O failure or incomplete parsing. JSON reports use `advisory`
or `incomplete`; they never claim that the application passed verification.

## L2 on Sapiens4

```bash
lake -d /path/to/sapiens4/spec build +Main +pure.ProviderReply
lake exe linter4 /path/to/sapiens4
```

L2 reads the elaborated declarations from `.olean` files and source positions
and resolved references from `.ilean` files. `leanProject.modules` selects the
root modules under `spec/`. The shipped profile selects `Main`, `pure.ProviderReply`
and their spec imports. Standalone executables such as `io.Provider` and the Lake configuration
lie outside that profile. The audit reads the artifacts without running tests or
loading initializers. Missing or older artifacts make L2 incomplete.

| Rule | Configured verification |
|---|---|
| L2-01 | Find forbidden types in selected declaration types, including through type aliases. |
| L2-04 | Find forbidden effect types in the results of selected pure helpers. |
| L2-05 | Follow resolved declaration dependencies through the project and check forbidden declaration or module prefixes. |
| L2-07 | Verify the named theorem, its parameter count and configured assumption type heads, and its transitive axioms. |
| L2-08 | Check named jobs in literal `(label, declaration)` lists and check that the runner references each list. |
| L2-10 | Check forbidden direct imports and suggest imports with no exclusive recorded use. |

Each checker reads `params` from `rules.json`. The Sapiens4 proof and job lists
are a baseline from revision `7ae4825`. Replace them with approved requirements
for a contract audit. The theorem check does not compare full theorem statements.
Registration does not establish which jobs actually run. Import suggestions can
miss dependencies on syntax or initialization.

L2 reports `verified-violation` for demonstrated mismatches with a configured
obligation, and `suspected` for design warnings. `NOT_VERIFIED` lists unavailable
or unspecified checks. L2-02, L2-03, L2-06 and L2-09 are pending contracts and
detectors. Exit codes report audit completion rather than merge eligibility.

`Main.lean` handles CLI and initialization. `Core/Types.lean` defines shared
types, `Config.lean` loads and validates rules, `Registry.lean` registers
checkers, `Engine.lean` prepares shared analysis data and runs selected checks,
and `Report.lean` renders results. Independent algorithms live in `Checkers/L0/`
and `Checkers/L1/`. `Syntax.lean` prepares one AST and source map per L1 file. `Tests.lean` calibrates
the analysis interface with positive, negative and near-miss examples.

The parser uses Lean's standard grammar and Lake DSL for files importing Lake.
Audited imports and commands are not executed or elaborated. Comments, strings and quoted syntax do not produce
operation findings; expressions inside interpolated strings are inspected.
Local grammar extensions are reported as unsupported. Imported custom syntax
may fail to parse. Nested catches are inspected independently without attributing
an inner fallback to its outer catch. Bounds recognition covers simple size
comparisons in the true branch and `[:array.size]` loops. Rebinding, assignments
and ambiguous scopes discard facts. Calls such as `requireThat`, `assertThat`
and `throw` supply no bounds information at L1. Interprocedural guarantees,
macro expansion, name resolution, proof trust and runtime behavior require
later levels.

Haskell and PureScript are outside this stage's scope. Directory scans include
only `.lean` files and skip symlinks and `.git`, `.lake`, `.idea`, `node_modules`,
`dist`, `target`, `build` directories. No Lean files is an error.
