import Core.Config
import Core.Registry
import Core.Engine

open Lean Cqa Cqa.L1

private def expect (condition : Bool) (message : String) : IO Unit := do
  unless condition do throw <| IO.userError message

private def scan (env : Environment) (selected : Array (Rule × AstCheck))
    (source : String) : IO (Array Finding) := do
  match ← Cqa.L1.parse env "Fixture.lean" source with
  | .ok ctx => return inspect selected ctx
  | .error error => throw <| IO.userError s!"{source}\n{error}"

private def fixtures : Array (String × String × Array String) := #[
  ("sleep call", "def x := IO.sleep 3", #["waits"]),
  ("similar name", "def x := IO.sleeper 3", #[]),
  ("string", "def x := \"IO.sleep 3; sorry; xs[0]!\"", #[]),
  ("nested comment", "/- /- sorry -/ IO.sleep 3 -/\ndef x := 1", #[]),
  ("line comment", "def x := 1 -- IO.sleep 3", #[]),
  ("quoted term", "def x := `(IO.sleep 3)", #[]),
  ("quoted tactic", "def x := `(tactic| sorry)", #[]),
  ("quoted command", "def x := `(def y := IO.sleep 3)", #[]),
  ("quoted grammar", "def x := `(syntax \"hello\" : term)", #[]),
  ("interpolation text", "def x := s!\"IO.sleep 3\"", #[]),
  ("interpolation expression", "def x := s!\"{IO.sleep 3}\"", #["waits"]),
  ("unchecked index", "def x := xs[0]!", #["unchecked-access"]),
  ("checked index", "def x := xs[0]?", #[]),
  ("proven index", "def x := xs[0]'h", #[]),
  ("unchecked method", "def x := xs.get! 0", #["unchecked-access"]),
  ("unchecked projection", "def x := (read xs).get! 0", #["unchecked-access"]),
  ("unchecked function", "def x := getElem! xs 0", #["unchecked-access"]),
  ("getter reference", "def x := Array.get!", #[]),
  ("default method", "def x := value.getD 0", #["fallbacks"]),
  ("default projection", "def x := (read xs).getD 0", #["fallbacks"]),
  ("discard error", "def x := Except.toOption result", #["fallbacks"]),
  ("caught zero", "def x := do try action catch _ => pure 0", #["fallbacks"]),
  ("caught string", "def x := do try action catch _ => pure \"\"", #["fallbacks"]),
  ("caught unit", "def x := do try action catch _ => pure ()", #["fallbacks"]),
  ("rethrow", "def x := do try action catch e => throw e", #[]),
  ("recovery computation", "def x := do try action catch e => pure (recover e)", #[]),
  ("constant assertion", "def x := requireThat \"works\" true", #["constant-assertions"]),
  ("parenthesized true", "def x := assertThat \"works\" ((true))", #["constant-assertions"]),
  ("real assertion", "def x := requireThat \"denied\" (reply.status == 403)", #[]),
  ("failing assertion", "def x := requireThat \"denied\" false", #[]),
  ("partial assertion", "def x := requireThat true", #[]),
  ("term sorry", "example : True := sorry", #["proof-placeholders"]),
  ("tactic sorry", "example : True := by sorry", #["proof-placeholders"]),
  ("tactic admit", "example : True := by admit", #["proof-placeholders"]),
  ("completed proof", "example : True := by trivial", #[]),
  ("similar identifier", "def sorryCount := 0", #[])
]

private def configTests (env : Environment) : IO Unit := do
  let valid := "{\"rules\":[{\"id\":\"CUSTOM\",\"name\":\"Waits\",\"severity\":\"improvement\",\"enabled\":true,\"checks\":[{\"level\":\"L1\",\"checker\":\"waits\"}]}]}"
  let json ← IO.ofExcept <| Json.parse valid
  let selected ← IO.ofExcept <| selectChecks registeredChecks json
  expect (selected.size == 1 && selected[0]?.any (fun (r, c) =>
    r.id == "CUSTOM" && r.severity == .improvement && c.id == "waits")) "Custom rule binding"
  for (before, after) in #[
    ("waits", "missing-checker"), ("L1", "L2"), ("improvement", "critical"),
    ("true", "false"), ("checks", "cheks")
  ] do
    let json ← IO.ofExcept <| Json.parse (valid.replace before after)
    expect (!(selectChecks registeredChecks json).isOk) s!"Invalid config accepted: {after}"
  let rules ← IO.ofExcept <| json.getObjValAs? (Array Json) "rules"
  let duplicate := Json.mkObj [("rules", toJson (rules ++ rules))]
  expect (!(selectChecks registeredChecks duplicate).isOk) "Duplicate rules accepted"
  let unknown := Json.mkObj [("rules", toJson rules), ("paths", toJson #["domain/"])]
  expect (!(selectChecks registeredChecks unknown).isOk) "Unsupported scope accepted"
  let found ← scan env selected "def x := IO.sleep 3"
  expect (found[0]?.any fun f => f.rule == "CUSTOM" && f.severity == .improvement)
    "Configured rule metadata lost"

def main : IO Unit := do
  let env ← initParser
  let json ← IO.ofExcept <| Json.parse (← IO.FS.readFile "rules.json")
  let selected ← IO.ofExcept <| selectChecks registeredChecks json
  for (name, source, expected) in fixtures do
    let found ← scan env selected source
    expect (found.map (·.checker) == expected) s!"{name}: expected {expected}, got {found.map (·.checker)}"
    expect (found.all fun f => !f.evidence.isEmpty && !f.fix.isEmpty &&
      f.file == "Fixture.lean" && f.status == "candidate") s!"Missing evidence: {name}"
  let found ← scan env selected "def α := IO.sleep 3\n"
  expect (found[0]?.any fun f => f.line == 1 && f.column == 10 &&
    f.evidence == "IO.sleep 3") "Unicode source position"
  let filtered ← scan env (selected.filter (·.2.id == "waits"))
    "def x := do\n  IO.sleep 3\n  requireThat \"works\" true"
  expect (filtered.size == 1) "Checker selection"
  for source in #["def x :=", "syntax \"hello\" : term", "#exit\ndef x := IO.sleep 3"] do
    expect (!(← Cqa.L1.parse env "Invalid.lean" source).isOk) s!"Incomplete parse accepted: {source}"
  let eval ← Cqa.L1.parse env "NotExecuted.lean" "#eval throw (IO.userError \"executed\")"
  expect eval.isOk "Audited #eval executed"
  configTests env
  IO.println s!"Passed {fixtures.size} syntax cases, positions, selection, parser failures and config checks."
