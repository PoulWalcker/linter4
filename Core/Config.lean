import Core.Types

namespace Cqa
open Lean

private def onlyFields (json : Json) (allowed : List String) : Except String Unit := do
  let fields ← json.getObj?
  for (key, _) in fields.toList do
    unless allowed.contains key do throw s!"Unknown configuration field: {key}"

def selectChecks (available : Array AstCheck) (json : Json) : Except String (Array (Rule × AstCheck)) := do
  onlyFields json ["rules"]
  for rule in ← json.getObjValAs? (Array Json) "rules" do
    onlyFields rule ["id", "name", "severity", "enabled", "checks"]
    for check in ← rule.getObjValAs? (Array Json) "checks" do
      onlyFields check ["level", "checker"]
  let config : Config ← fromJson? json
  let mut ids := #[]
  let mut selected := #[]
  for rule in config.rules do
    if rule.id.isEmpty || rule.name.isEmpty then throw "Rule id and name must not be empty"
    if rule.checks.isEmpty then throw s!"No checks configured for {rule.id}"
    if ids.contains rule.id then throw s!"Duplicate rule: {rule.id}"
    ids := ids.push rule.id
    let mut checkerIds := #[]
    for entry in rule.checks do
      unless entry.level == "L1" do throw s!"Unsupported level: {entry.level}"
      let some check := available.find? (·.id == entry.checker)
        | throw s!"Unknown checker: {entry.checker}"
      if checkerIds.contains check.id then throw s!"Duplicate checker in {rule.id}: {check.id}"
      checkerIds := checkerIds.push check.id
      if rule.enabled then selected := selected.push (rule, check)
  if selected.isEmpty then throw "No enabled L1 checks"
  return selected

def loadConfig (path : System.FilePath) (available : Array AstCheck) : IO (Array (Rule × AstCheck)) := do
  let json ← IO.ofExcept <| Json.parse (← IO.FS.readFile path)
  IO.ofExcept <| selectChecks available json

end Cqa
