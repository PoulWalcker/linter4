# Manual L2 fixtures

Run from the linter4 repository root with its pinned toolchain on the path.

```bash
lake build
linter4_root="$PWD"
fixture_run=$(mktemp -d)
cp fixtures/l2/rules.json "$fixture_run/rules.json"
for variant in Good Bad; do
  (
    cd "$linter4_root/fixtures/l2/$variant/spec"
    artifacts="$PWD/.lake/build/lib/lean"
    mkdir -p "$artifacts"
    export LEAN_PATH="$artifacts"
    for module in Cases Infra Unused Main; do
      if [ -f "$module.lean" ]; then
        lean -o "$artifacts/$module.olean" -i "$artifacts/$module.ilean" "$module.lean"
      fi
    done
  )
  (
    cd "$fixture_run"
    ELAN_TOOLCHAIN=leanprover/lean4:v4.35.0 \
      "$linter4_root/.lake/build/bin/linter4" "$linter4_root/fixtures/l2/$variant"
    mv linter4-report.json "$variant.json"
  )
done
```

Good should produce zero findings across six checks. Bad should show findings
for each check, including both an indirect `sorryAx` dependency and a missing
registration for an existing test declaration.
