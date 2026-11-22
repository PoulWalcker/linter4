import Core.Registry
import Checkers.L2.Audit

namespace Cqa
open Lean

private def onlyFields (json : Json) (allowed : List String) : Except String Unit := do
  let fields ← json.getObj?
  for (key, _) in fields.toList do
    unless allowed.contains key do throw s!"Unknown configuration field: {key}"

private def resolveChecks (available : Array AstCheck) (json : Json) :
    Except String (SelectedChecks × L2.Plan) := do
  onlyFields json ["rules", "leanProject"]
  for rule in ← json.getObjValAs? (Array Json) "rules" do
    onlyFields rule ["id", "name", "severity", "enabled", "checks"]
    for check in ← rule.getObjValAs? (Array Json) "checks" do
      onlyFields check ["level", "checker", "patterns", "params"]
  let project ← if let .ok value := json.getObjVal? "leanProject" then do
    onlyFields value ["artifacts", "modules", "pending"]
    some <$> fromJson? value
  else pure none
  let config : Config ← fromJson? json
  let mut ids := #[]
  let mut text := #[]
  let mut ast := #[]
  let mut semantic := #[]
  let mut notVerified := (project.bind L2.Project.pending).getD #[]
  for rule in config.rules do
    if rule.id.isEmpty || rule.name.isEmpty then throw "Rule id and name must not be empty"
    if rule.checks.isEmpty then throw s!"No checks configured for {rule.id}"
    if ids.contains rule.id then throw s!"Duplicate rule: {rule.id}"
    ids := ids.push rule.id
    let mut checkerIds := #[]
    for entry in rule.checks do
      if checkerIds.contains entry.checker then throw s!"Duplicate checker in {rule.id}: {entry.checker}"
      checkerIds := checkerIds.push entry.checker
      match entry.level with
      | "L0" =>
        if entry.params.isSome then throw s!"{entry.checker}: params apply only to L2"
        let some check := registeredTextChecks.find? (·.id == entry.checker)
          | throw s!"Unknown L0 checker: {entry.checker}"
        let patterns := entry.patterns.getD #[]
        if check.requiresPatterns && (patterns.isEmpty || patterns.any
            (fun p => p.trimAscii.isEmpty || p.contains '\n' || p.contains '\r')) then
          throw s!"{rule.id}: L0 patterns must contain non-blank single-line strings"
        if !check.requiresPatterns && entry.patterns.isSome then
          throw s!"{entry.checker}: patterns are unsupported"
        if rule.enabled then text := text.push (rule, check, patterns.toList.eraseDups.toArray)
      | "L1" =>
        if entry.params.isSome then throw s!"{entry.checker}: params apply only to L2"
        let some check := available.find? (·.id == entry.checker)
          | throw s!"Unknown L1 checker: {entry.checker}"
        if entry.patterns.isSome then throw s!"{rule.id}: patterns apply only to L0"
        if rule.enabled then ast := ast.push (rule, check)
      | "L2" =>
        if entry.patterns.isSome then throw s!"{entry.checker}: patterns apply only to L0"
        let some check := registeredSemanticChecks.find? (·.id == entry.checker)
          | throw s!"Unknown L2 checker: {entry.checker}"
        if rule.enabled then
          if let some params := entry.params then
            let run ← (check.prepare params).mapError fun error => s!"{rule.id}: {error}"
            semantic := semantic.push (rule, check.id, run)
          else notVerified := notVerified.push s!"{rule.id}: no policy parameters configured"
      | _ => throw s!"Unsupported level: {entry.level}"
  return (⟨text, ast⟩, ⟨project, semantic, notVerified⟩)

def selectChecks (available : Array AstCheck) (json : Json) : Except String (Array (Rule × AstCheck)) := do
  let (selected, _) ← resolveChecks available json
  if selected.ast.isEmpty then throw "No enabled L1 checks"
  return selected.ast

private def readConfig (path : System.FilePath) : IO (SelectedChecks × L2.Plan) := do
  let json ← IO.ofExcept <| Json.parse (← IO.FS.readFile path)
  IO.ofExcept (resolveChecks registeredChecks json)

def loadConfig (path : System.FilePath) : IO (SelectedChecks × L2.Plan) := readConfig path

end Cqa
