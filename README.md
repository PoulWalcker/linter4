# Minimal CQA (Lean 4)

A **source-pattern scanner** for Sapiens4's `.lean` files. No LLM, server,
GitHub integration, or extra dependencies.

## Usage

```bash
lake build
lake exe cqa /absolute/path/to/sapiens4
# Optional demo mode: exit 1 if any potential finding is present
lake exe cqa /absolute/path/to/sapiens4 --strict
```

Example output:

```text
REVIEW W-01  /path/spec/Example.lean:15  Check whether a fixed wait is necessary
Scanned 100 Lean files; 1 review candidates.
PASS: scan completed; findings are not confirmed violations.
```

## Built-in candidates

- **W-01**: `IO.sleep` (fixed wait)
- **W-04**: `]!` or `.get!` (unchecked access)
- **NG-13**: `sorry` or `admit` (possible incomplete proof)

These **do not prove a rule was violated**. `NG-13` must only block when an
*actually required* proof is incomplete or untrusted. The tool therefore
prints `REVIEW`, not `NO-GO`, and returns 0 on a successful default scan. The optional `--strict` flag is a demo, **not safe as a merge gate**.

## Exit codes

- `0`: scan ran successfully; no definitive merge decision
- `1`: `--strict` enabled and a potential finding was detected (may be false positive)
- `2`: bad CLI arguments or directory (other I/O exceptions also stop execution)

## Limits

This is a text scanner, not an AST analyzer. It ignores `--` line comments,
but may report strings or block comments as false positives. It does not run
tests, check behavior, prove architecture quality, support PR URLs, or enforce
all 21 rules. Add real verification and explicit No-Go criteria before using it
as a merge gate.

The Lean toolchain is selected as `stable` for easy setup; pin the precise
version approved by your team for reproducible runs.
