import Checkers.L1.Syntax

namespace Cqa
open Lean L1

private def sortFindings (findings : Array Finding) : Array Finding :=
  findings.qsort fun a b => a.line < b.line || (a.line == b.line && a.column < b.column)

def inspect (selected : Array (Rule × AstCheck)) (ctx : SyntaxContext) : Array Finding := Id.run do
  let mut findings := #[]
  for (rule, check) in selected do
    for s in check.run ctx.ast do
      if let some start := s.getPos? then
        let position := ctx.fileMap.toPosition start
        findings := findings.push {
          checker := check.id, rule := rule.id, severity := rule.severity, file := ctx.file
          line := position.line, column := position.column + 1
          evidence := ctx.source.toRawSubstring.extract start (s.getTailPos?.getD start) |>.toString
          message := check.message, fix := check.fix
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
  let scanner : IO (String × Array String × (String → String → IO (Except String (Array Finding)))) :=
    match selected with
    | .text checks => pure ("L0", checks.map (fun (_, check, _) => check.id), fun file source =>
        pure (.ok (sortFindings (checks.foldl (fun found (rule, check, patterns) =>
          found ++ check.run rule patterns file source) #[]))))
    | .ast checks => do
      let env ← initParser
      pure ("L1", checks.map (·.2.id), fun file source =>
        (·.map (inspect checks)) <$> Cqa.L1.parse env file source)
  let (level, checks, scan) ← scanner
  let mut findings := #[]
  let mut errors := #[]
  for file in paths do
    try
      let source ← IO.FS.readFile file
      match ← scan file.toString source with
      | .ok found => findings := findings ++ found
      | .error message => errors := errors.push { file := file.toString, message, level }
    catch e => errors := errors.push { file := file.toString, message := e.toString, level }
  return {
    status := if errors.isEmpty then "advisory" else "incomplete"
    level, files := paths.size, checks := checks.toList.eraseDups.toArray, findings, errors
  }

end Cqa
