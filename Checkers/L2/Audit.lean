import Checkers.L2.Context

namespace Cqa.L2
open Lean System

structure Plan where
  project : Option Project
  checks : Array (Rule × String × Run)
  notVerified : Array String

private def inside (parent child : FilePath) : Bool :=
  parent.normalize.components.isPrefixOf child.normalize.components

private def readModule (spec artifacts : FilePath) (name : Name) : IO SourceModule := do
  let file ← IO.FS.realPath (modToFilePath spec name "lean")
  unless inside spec file do throw <| IO.userError "Lean source escapes spec/"
  let olean := modToFilePath artifacts name "olean"
  let ilean := modToFilePath artifacts name "ilean"
  let modified := (← file.metadata).modified
  if (← olean.metadata).modified < modified || (← ilean.metadata).modified < modified then
    throw <| IO.userError "Compiled artifacts are stale; rebuild this module"
  let data ← Server.Ilean.load ilean
  unless data.module == name do throw <| IO.userError "Compiled source metadata has the wrong module name"
  let input := Parser.mkInputContext (← IO.FS.readFile file) file.toString
  let (header, _, messages) ← Parser.parseHeader input
  if messages.hasErrors then throw <| IO.userError "Source import header has parse errors"
  let importLines := header.raw[2].getArgs.map fun item =>
    (item[4].getId, (input.fileMap.toPosition (item.getPos?.getD 0)).line)
  return ⟨file, data, importLines⟩

private def load (root : FilePath) (project : Project) : IO (Context × Nat × Array ScanError) := do
  let root ← IO.FS.realPath root
  let spec := root / "spec"
  unless (← spec.symlinkMetadata).type == .dir do throw <| IO.userError "Expected a regular spec/ directory"
  let artifacts ← IO.FS.realPath (spec / project.artifacts)
  unless inside spec artifacts do throw <| IO.userError "Compiled artifacts must be under spec/"
  let roots ← IO.ofExcept (names project.modules)
  for name in roots do
    unless (← (modToFilePath spec name "lean").pathExists) &&
        (← (modToFilePath artifacts name "olean").pathExists) do
      throw <| IO.userError s!"Missing spec module or compiled artifact for {name}; build the test modules first"
  initSearchPath (← findSysroot) [artifacts]
  let env ← importModules (roots.map fun name => { module := name, importAll := true }) {} (loadExts := false)
  let mut modules := #[]
  let mut errors := #[]
  for name in env.allImportedModuleNames do
    let file := modToFilePath spec name "lean"
    if ← file.pathExists then
      try modules := modules.push (← readModule spec artifacts name)
      catch e => errors := errors.push ⟨file.toString, e.toString, "L2"⟩
  return (⟨env, spec, modules⟩, modules.size + errors.size, errors)

def audit (path : FilePath) (plan : Plan) : IO Report := do
  let ids := plan.checks.map fun (rule, _, _) => rule.id
  let mut report : Report := {
    level := "L2", levels := #["L2"], status := "incomplete", files := 0, checks := #[],
    findings := #[], errors := #[], notVerified := plan.notVerified }
  let some project := plan.project | return { report with
    notVerified := report.notVerified ++ ids ++ #["No L2 project configured"] }
  if plan.checks.isEmpty then return report
  try
    let (ctx, files, errors) ← load path project
    report := { report with files, errors }
    if !errors.isEmpty then return { report with notVerified := report.notVerified ++ ids }
    for (rule, checker, run) in plan.checks do
      try
        let observations ← (run ctx).toIO' { fileName := ctx.root.toString, fileMap := default } { env := ctx.env }
        let findings := observations.map fun observed =>
          let (file, line, column, evidence) := ctx.location observed.subject
          let severity := if !observed.verified && rule.severity == .noGo then .warning else rule.severity
          {
            checker, rule := rule.id, severity, level := "L2", file := file.toString,
            line, column, evidence, message := observed.message, fix := observed.fix,
            status := if observed.verified then "verified-violation" else "suspected" : Finding }
        report := { report with checks := report.checks.push rule.id, findings := report.findings ++ findings }
      catch e => report := { report with notVerified := report.notVerified.push s!"{rule.id}: {e}" }
    return { report with status := if report.checks.size == ids.size then "advisory" else "incomplete" }
  catch e => return { report with
    errors := #[⟨path.toString, e.toString, "L2"⟩], notVerified := report.notVerified ++ ids }

end Cqa.L2
