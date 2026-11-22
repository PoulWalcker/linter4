import Core.Config
import Core.Engine
import Core.Report

open Cqa

private def usage : String :=
  "Usage: linter4 [file-or-directory]"

private def run (args : List String) : IO UInt32 := do
  let path ← match args with
    | [] => pure "."
    | [path] =>
      if path.startsWith "-" then throw <| IO.userError usage else pure path
    | _ => throw <| IO.userError usage
  let (selected, semantic) ← loadConfig "rules.json"
  let report ← auditProject path selected semantic
  IO.println (renderReport report)
  IO.FS.writeFile "linter4-report.json" ((Lean.toJson report).pretty ++ "\n")
  return if report.status == "incomplete" then 2 else 0

def main (args : List String) : IO UInt32 := do
  try run args
  catch e =>
    IO.eprintln e.toString
    return 2
