import Core.Config
import Core.Engine
import Core.Report

open Cqa

private structure Options where
  config : String := "rules.json"
  level : String := "L1"
  output : Option String := none
  json : Bool := false
  summary : Bool := false

private def usage : String :=
  "Usage: cqa <file-or-directory> [--level L0|L1] [--config rules.json] [--json | --summary] [--output report.json]"

private def options : List String → Options → Except String Options
  | [], opts => if opts.json && opts.summary then .error usage else .ok opts
  | "--config" :: path :: rest, opts => options rest { opts with config := path }
  | "--level" :: level :: rest, opts =>
    if level == "L0" || level == "L1" then options rest { opts with level := level }
    else .error s!"Unsupported level: {level}"
  | "--output" :: path :: rest, opts => options rest { opts with output := some path }
  | "--json" :: rest, opts => options rest { opts with json := true }
  | "--summary" :: rest, opts => options rest { opts with summary := true }
  | _, _ => .error usage

private def run (args : List String) : IO UInt32 := do
  let path :: flags := args | throw <| IO.userError usage
  let opts ← IO.ofExcept <| options flags {}
  let selected ← loadConfig opts.config opts.level
  let report ← audit path selected
  if let some output := opts.output then
    IO.FS.writeFile output (renderReport report true ++ "\n")
  IO.println (if opts.summary then renderSummary report else renderReport report opts.json)
  return if report.errors.isEmpty then 0 else 2

def main (args : List String) : IO UInt32 := do
  try run args
  catch e =>
    IO.eprintln e.toString
    return 2
