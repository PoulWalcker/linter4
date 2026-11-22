import Checkers.L1.Syntax
import Checkers.L0.SourceRisks
import Checkers.L2.Audit

namespace Cqa
open Lean L1

private def sortFindings (findings : Array Finding) : Array Finding :=
  findings.qsort fun a b => a.line < b.line || (a.line == b.line && a.column < b.column)

private def covers (ast text : Finding) : Bool :=
  let lines := ast.evidence.splitOn "\n"
  let lastLine := ast.line + lines.length - 1
  let lastColumn := (if lines.length == 1 then ast.column else 1) + (lines.getLast?.getD "").length
  ast.rule == text.rule && ast.file == text.file && !ast.evidence.startsWith "[redacted" &&
    (ast.line < text.line || (ast.line == text.line && ast.column ≤ text.column)) &&
    (text.line < lastLine || (text.line == lastLine && text.column < lastColumn))

def inspect (selected : Array (Rule × AstCheck)) (ctx : SyntaxContext) : Array Finding := Id.run do
  let mut findings := #[]
  let hidden := L0.SourceRisks.hiddenLines ctx.source
  for (rule, check) in selected do
    for s in check.run ctx.ast do
      if let some start := s.getPos? then
        let position := ctx.fileMap.toPosition start
        let stop := s.getTailPos?.getD start
        let evidence := if hidden.any (fun line => position.line ≤ line && line ≤ (ctx.fileMap.toPosition stop).line)
          then "[redacted: possible credential]"
          else ctx.source.toRawSubstring.extract start stop |>.toString
        findings := findings.push {
          checker := check.id, rule := rule.id, severity := rule.severity, file := ctx.file
          line := position.line, column := position.column + 1
          evidence
          message := check.message s, fix := check.fix
        }
  return sortFindings findings

private def excluded (path : System.FilePath) : Bool :=
  path.components.any fun part =>
    [".git", ".lake", ".idea", "node_modules", "dist", "target", "build"].contains part

private partial def filesAt (path : System.FilePath) : IO (Array System.FilePath) := do
  if ← path.isDir then
    let mut files := #[]
    for entry in ← path.readDir do
      unless excluded entry.path do
        if (← entry.path.symlinkMetadata).type != .symlink then
          files := files ++ (← filesAt entry.path)
    return files
  if path.extension == some "lean" then return #[path]
  return #[]

def audit (path : System.FilePath) (selected : SelectedChecks) : IO Report := do
  unless ← path.pathExists do throw <| IO.userError s!"Path does not exist: {path}"
  let paths := (← filesAt path).qsort (fun a b => a.toString < b.toString)
  if paths.isEmpty then throw <| IO.userError s!"No Lean files: {path}"
  let env ← if selected.ast.isEmpty then pure none else some <$> initParser
  let levels := (if selected.text.isEmpty then #[] else #["L0"]) ++
    (if selected.ast.isEmpty then #[] else #["L1"])
  let checks := selected.text.map (fun (_, check, _) => check.id) ++ selected.ast.map (·.2.id)
  let mut findings := #[]
  let mut errors := #[]
  for file in paths do
    try
      let source ← IO.FS.readFile file
      let textFindings := selected.text.foldl (fun found (rule, check, patterns) =>
        found ++ check.run rule patterns file.toString source) #[]
      if let some env := env then
        match ← Cqa.L1.parse env file.toString source with
        | .ok ctx =>
          let astFindings := inspect selected.ast ctx
          let textFindings := textFindings.filter fun text => !astFindings.any (covers · text)
          findings := findings ++ sortFindings (textFindings ++ astFindings)
        | .error message =>
          findings := findings ++ sortFindings textFindings
          errors := errors.push { file := file.toString, message, level := "L1" }
      else findings := findings ++ sortFindings textFindings
    catch e => errors := errors.push { file := file.toString, message := e.toString, level := "FULL" }
  return {
    status := if errors.isEmpty then "advisory" else "incomplete"
    levels, files := paths.size, checks := checks.toList.eraseDups.toArray, findings, errors
  }

def auditProject (path : System.FilePath) (selected : SelectedChecks) (plan : L2.Plan) : IO Report := do
  if selected.text.isEmpty && selected.ast.isEmpty then
    if plan.checks.isEmpty && plan.notVerified.isEmpty then throw <| IO.userError "No enabled checks"
    return ← L2.audit path plan
  let source ← audit path selected
  if plan.checks.isEmpty then return { source with notVerified := plan.notVerified }
  unless ← (path / "spec").isDir do
    let missing := plan.checks.map fun (rule, _, _) => s!"{rule.id}: no spec/ directory"
    return { source with notVerified := plan.notVerified ++ missing }
  let semantic ← L2.audit path plan
  return { source with
    levels := source.levels ++ semantic.levels, checks := source.checks ++ semantic.checks,
    status := if semantic.status == "incomplete" then semantic.status else source.status,
    findings := source.findings ++ semantic.findings, errors := source.errors ++ semantic.errors,
    notVerified := semantic.notVerified, semanticFiles := some semantic.files }

end Cqa
