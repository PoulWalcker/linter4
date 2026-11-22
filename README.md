# CQA — Lean L0 and L1

Scans `.lean` source text at L0 and analyzes syntax with Lean 4.35.0 at L1.

```bash
lake build
lake test
lake exe cqa /path/to/repository
lake exe cqa /path/to/File.lean --json
lake exe cqa /path/to/repository --level L0 --summary --output l0.json
lake exe cqa /path/to/repository --summary --output report.json
```

`rules.json` is loaded from the current directory by default. It defines rule
IDs, names, severity, enabled status and checker assignments. Changes take effect
without recompilation. One rule can select several checkers. Unknown fields,
checker IDs, unsupported levels and an empty enabled selection are errors.
Use `--config path.json` to select a different configuration. `--summary` prints
a Markdown summary with file, error and per-rule counts. `--output` saves the
full JSON report, including findings and parse errors, independently of stdout.

The default level is L1. L0 uses `keyword-scan` with a `patterns` array of
non-blank, single-line strings. It reports case-sensitive substring matches,
including in comments, strings and files with invalid syntax. The default
patterns are `TODO` and `FIXME`. Proof placeholders are checked at L1.
One invocation scans one level. Both levels read source files only.

| Checker | Default rule | L1 observation |
|---|---|---|
| `constant-assertions` | NG-05 | `requireThat` or `assertThat` receives literal `true` |
| `proof-placeholders` | NG-06 | Term `sorry`, tactic `sorry` or `admit` |
| `fallbacks` | W-05 | `getD`, `Except.toOption`, or a catch containing `pure` of a literal/unit |
| `waits` | EXTRA-WAIT | Explicit `IO.sleep` call |
| `unchecked-access` | EXTRA-ACCESS | `xs[i]!`, `getElem!`, or `get!` without a recognized local bounds check |

The complete policy descriptions are in [docs/rules.md](docs/rules.md).
[Additional examples](docs/sapiens4-findings.md) supply investigation targets.
`EXTRA-*` IDs are additional checks, separate from the main document's numbering.

Every finding is a **review candidate**, including findings for a `no-go` policy.
Reports include the checker, rule, severity, file, one-based line/column, exact
source fragment, explanation and suggested action. Neither L0 nor L1 confirms
a merge blocker.

The default text report starts with file coverage, finding and scan error counts.
Each finding shows its rule, severity, level, source location and exact code,
followed by `Found` (the observation) and `Review` (the suggested action).
For example, scanning a file containing `def x := IO.sleep 50` produces:

```text
CQA — L1
Checked: 1/1 files
Findings: 1
Scan errors: 0
Result: Complete

[warning] EXTRA-WAIT · L1
Example.lean:1:10

  IO.sleep 50

Found: A call to IO.sleep was found.
Review: If this waits for readiness, verify readiness and bound the total wait.
```

`Complete` means scanning finished, including when findings exist. `Incomplete`
means some files could not be checked; details appear in a separate `Scan errors`
section. Counts cover files successfully scanned at the selected level, not
application verification.
JSON retains the existing fields and adds `level` to each finding and scan error.

`0` means the scan completed in its declared scope; `2` means invalid input,
configuration, I/O failure or incomplete parsing. JSON reports use `advisory`
or `incomplete`; they never claim that the application passed verification.

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
