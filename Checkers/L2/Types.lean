import Checkers.L2.Context

namespace Cqa.L2.Types
open Lean

private partial def typeNames (env : Environment) (type : Expr) : Array Name :=
  (visit type.getUsedConstants.toList {}).toArray
where
  visit : List Name → NameSet → NameSet
    | [], seen => seen
    | name :: rest, seen =>
      if seen.contains name then visit rest seen else
      let refs := match env.find? name with
        | some (.defnInfo value) =>
          if value.type.getForallBody.isSort then value.value.getUsedConstants.toList else []
        | _ => []
      visit (refs ++ rest) (seen.insert name)

private def signature (resultOnly : Bool) (declarations : Array String) (forbidden : Array Name) : Run := fun ctx => do
  let results ← declarations.mapM fun name => do
    let decl ← ctx.declaration name
    let type := if resultOnly then decl.type.getForallBody else decl.type
    let used := (typeNames ctx.env type).filter forbidden.contains
    if used.isEmpty then return none
    return some (⟨.decl decl.name,
      s!"The configured {(if resultOnly then "pure result" else "domain signature")} uses {sortedNames used}.",
      "Keep the reusable logic within the configured type boundary.", false⟩ : Observation)
  return results.filterMap id

private def effects (declarations : Array String) (forbidden : Array Name) : Run := fun ctx => do
  let results ← declarations.mapM fun name => do
    let decl ← ctx.declaration name
    let denied := (ctx.refs decl).filter fun dependency => dependency != decl.name &&
      forbidden.any fun prefixName => prefixName.isPrefixOf dependency ||
        (ctx.owner dependency).any prefixName.isPrefixOf
    if denied.isEmpty then return none
    return some (⟨.decl decl.name, s!"The helper depends on {sortedNames denied}.",
      "Move the effect to the caller and pass its result to the helper.", false⟩ : Observation)
  return results.filterMap id

def domain : Check := ⟨"strong-domain-types", fun json => scopedCheck json (signature false)⟩
def purity : Check := ⟨"pure-test-logic", fun json => scopedCheck json (signature true)⟩
def boundaries : Check := ⟨"effect-boundaries", fun json => scopedCheck json effects⟩

end Cqa.L2.Types
