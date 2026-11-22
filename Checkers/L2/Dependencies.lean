import Checkers.L2.Context

namespace Cqa.L2.Dependencies
open Lean

private structure Policy where
  modules : Array String
  forbidden : Array String
  unused : Bool
  deriving FromJson

private def moduleData (env : Environment) (name : Name) : Option ModuleData := do
  env.header.moduleData[← env.getModuleIdx? name]?

private partial def reachable (env : Environment) (pending : List Name) (seen : NameSet := {}) : NameSet :=
  match pending with
  | [] => seen
  | name :: rest =>
    if seen.contains name then reachable env rest seen else
    let imports := (moduleData env name).map (·.imports.toList.map (·.module)) |>.getD []
    reachable env (imports ++ rest) (seen.insert name)

private def usedModules (ctx : Context) (source : SourceModule) : NameSet := Id.run do
  let mut used := {}
  let refs : Std.TreeMap Lsp.RefIdent Lsp.RefInfo := source.data.references
  for (ref, info) in refs do
    if let .const name _ := ref then
      unless info.usages.isEmpty do used := (used : NameSet).insert name.toName
  if let some data := moduleData ctx.env source.data.module then
    for decl in data.constants do
      for dependency in decl.getUsedConstantsAsSet.toArray do
        if let some owner := ctx.owner dependency then used := used.insert owner
  return used

private def dependencies (config : Policy) : Run := fun ctx => do
  let mut found := #[]
  for moduleName in config.modules do
    let name := moduleName.toName
    let some source := ctx.sourceModule name | throwError "Module {name} is outside the loaded spec"
    let used := if config.unused then usedModules ctx source else {}
    let imports := source.data.directImports.map (·.module.toName)
    let forbidden := config.forbidden.map String.toName
    for imported in imports do
      let line := (source.importLines.find? (·.1 == imported)).map (·.2) |>.getD 1
      let denied := forbidden.any (·.isPrefixOf imported)
      let exclusive := if config.unused && !denied then
        let alternative := reachable ctx.env (`Init :: (imports.filter (· != imported)).toList)
        (reachable ctx.env [imported]).toArray.any (fun dependency => used.contains dependency &&
          !alternative.contains dependency)
      else true
      if denied || !exclusive then
        found := found.push ⟨.module name line,
          if denied then s!"Direct import {imported} is forbidden by this module policy."
          else s!"No recorded declaration reference needs direct import {imported}.",
          if denied then "Remove the forbidden coupling."
          else "Check syntax, instances and initialization before removing the import.", denied⟩
  return found

def check : Check := ⟨"dependencies", fun json => do
  let config : Policy ← fromJson? json
  let _ ← names config.modules
  if !config.unused && config.forbidden.isEmpty then throw "No dependency restriction configured"
  if config.forbidden.any (·.trimAscii.isEmpty) then throw "Blank dependency prefix"
  return dependencies config⟩

end Cqa.L2.Dependencies
