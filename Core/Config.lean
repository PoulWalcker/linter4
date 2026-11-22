import Core.Registry

namespace Cqa
open Lean

private def onlyFields (json : Json) (allowed : List String) : Except String Unit := do
  let fields ← json.getObj?
  for (key, _) in fields.toList do
    unless allowed.contains key do throw s!"Unknown configuration field: {key}"

private def resolveChecks (available : Array AstCheck) (json : Json) :
    Except String (Array (Rule × TextCheck × Array String) × Array (Rule × AstCheck)) := do
  onlyFields json ["rules"]
  for rule in ← json.getObjValAs? (Array Json) "rules" do
    onlyFields rule ["id", "name", "severity", "enabled", "checks"]
    for check in ← rule.getObjValAs? (Array Json) "checks" do
      onlyFields check ["level", "checker", "patterns"]
  let config : Config ← fromJson? json
  let mut ids := #[]
  let mut text := #[]
  let mut ast := #[]
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
        let some check := registeredTextChecks.find? (·.id == entry.checker)
          | throw s!"Unknown L0 checker: {entry.checker}"
        let patterns := entry.patterns.getD #[]
        if patterns.isEmpty || patterns.any (fun p => p.trimAscii.isEmpty || p.contains '\n' || p.contains '\r') then
          throw s!"{rule.id}: L0 patterns must contain non-blank single-line strings"
        if rule.enabled then text := text.push (rule, check, patterns.toList.eraseDups.toArray)
      | "L1" =>
        let some check := available.find? (·.id == entry.checker)
          | throw s!"Unknown L1 checker: {entry.checker}"
        if entry.patterns.isSome then throw s!"{rule.id}: patterns apply only to L0"
        if rule.enabled then ast := ast.push (rule, check)
      | _ => throw s!"Unsupported level: {entry.level}"
  return (text, ast)

def selectChecks (available : Array AstCheck) (json : Json) : Except String (Array (Rule × AstCheck)) := do
  let (_, selected) ← resolveChecks available json
  if selected.isEmpty then throw "No enabled L1 checks"
  return selected

def loadConfig (path : System.FilePath) (level : String) : IO SelectedChecks := do
  let json ← IO.ofExcept <| Json.parse (← IO.FS.readFile path)
  if level == "L1" then return .ast (← IO.ofExcept <| selectChecks registeredChecks json)
  let (selected, _) ← IO.ofExcept <| resolveChecks registeredChecks json
  if selected.isEmpty then throw <| IO.userError "No enabled L0 checks"
  return .text selected

end Cqa
