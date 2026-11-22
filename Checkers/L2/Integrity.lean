import Checkers.L2.Context
import Lean.Util.CollectAxioms

namespace Cqa.L2.Integrity
open Lean

private structure RequiredProof where
  name : String
  sourceModule : String
  parameters : Nat
  assumptionHeads : Option (Array String)
  deriving FromJson

private structure ProofPolicy where
  proofs : Array RequiredProof
  allowedAxioms : Array String
  deriving FromJson

private def arity : Expr → Nat
  | .forallE _ _ body _ => arity body + 1
  | _ => 0

private def heads : Expr → List String
  | .forallE _ type body _ =>
    (type.getAppFn.constName?.map (·.toString) |>.getD "<non-constant>") :: heads body
  | _ => []

private def proofs (config : ProofPolicy) : Run := fun ctx => do
  let mut found := #[]
  for proof in config.proofs do
    let name := proof.name.toName
    let moduleName := proof.sourceModule.toName
    unless (ctx.sourceModule moduleName).isSome do throwError "Proof module {moduleName} was not loaded"
    let some (.thmInfo info) := ctx.env.find? name |>.filter (fun _ => ctx.owner name == some moduleName)
      | found := found.push ⟨.module moduleName, s!"Required theorem {name} is missing from {moduleName}.",
          "Restore the required theorem.", true⟩
        continue
    if arity info.type != proof.parameters then
      found := found.push ⟨.decl name, s!"Expected {proof.parameters} leading parameters or assumptions; found {arity info.type}.",
        "Compare the theorem statement with the agreed contract.", true⟩
    if let some expected := proof.assumptionHeads then
      let actual := heads info.type |>.toArray
      if actual != expected then
        found := found.push ⟨.decl name, s!"Expected parameter type heads {expected}; found {actual}.",
          "Restore the configured assumption types.", true⟩
    let forbidden := (← collectAxioms name).filter fun ax =>
      ax == `sorryAx || !config.allowedAxioms.contains ax.toString
    unless forbidden.isEmpty do
      found := found.push ⟨.decl name, s!"The theorem transitively uses {sortedNames forbidden}.",
        "Complete placeholder proofs and remove unapproved assumptions.", true⟩
  return found

private structure RequiredSuite where
  registry : String
  required : Array String
  deriving FromJson

private structure RegistrationPolicy where
  runner : String
  suites : Array RequiredSuite
  deriving FromJson

private partial def jobs (expr : Expr) : Except String (Array Name) := do
  if expr.isAppOfArity `List.nil 1 then return #[]
  unless expr.isAppOfArity `List.cons 3 do throw "Registry is not a literal list"
  let args := expr.getAppArgs
  let pair := args[1]?.getD expr
  unless pair.isAppOfArity `Prod.mk 4 do throw "Expected registry entries (label, declaration)"
  let some (.const test _) := pair.getAppArgs.back? | throw "Registry job is not a named declaration"
  return #[test] ++ (← jobs (args[2]?.getD expr))

private def registration (config : RegistrationPolicy) : Run := fun ctx => do
  let runner ← ctx.declaration config.runner
  let refs := ctx.refs runner
  let mut found := #[]
  for suite in config.suites do
    let name := suite.registry.toName
    let registry := ctx.env.find? name |>.filter (fun _ => (ctx.owner name >>= ctx.sourceModule).isSome)
    let some registry := registry | found := found.push ⟨.decl runner.name,
      s!"Required registry {name} is missing.", "Restore the suite registry.", true⟩; continue
    let some body := registry.value? | throwError "Registry {name} has no inspectable body"
    let registered ← match jobs body with
      | .ok names => pure names
      | .error detail => throwError "{name}: {detail}"
    if !refs.contains name then
      found := found.push ⟨.decl runner.name, s!"Runner does not reference required registry {name}.",
        "Connect the suite to its runner.", true⟩
    let missing := suite.required.map String.toName |>.filter fun job => !registered.contains job
    unless missing.isEmpty do
      found := found.push ⟨.decl name, s!"Missing required registrations: {sortedNames missing}.",
        "Register these declarations in their required suite.", true⟩
  return found

def proofCheck : Check := ⟨"proof-integrity", fun json => do
  let config : ProofPolicy ← fromJson? json
  let _ ← names (config.proofs.map (·.name) ++ config.proofs.map (·.sourceModule))
  for proof in config.proofs do
    if let some expected := proof.assumptionHeads then
      unless expected.size == proof.parameters && !expected.any (·.trimAscii.isEmpty) do
        throw s!"{proof.name}: assumptionHeads must match the parameter count"
  return proofs config⟩

def registrationCheck : Check := ⟨"test-registration", fun json => do
  let config : RegistrationPolicy ← fromJson? json
  let _ ← names (#[config.runner] ++ config.suites.map (·.registry))
  if config.suites.isEmpty then throw "Expected at least one required suite"
  for suite in config.suites do
    let _ ← names suite.required
  return registration config⟩

end Cqa.L2.Integrity
