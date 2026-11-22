import Lean

-- A deliberately small source scanner for Sapiens4 Lean files.
-- Findings are review candidates, not proven defects.

structure Finding where
  rule : String
  message : String

-- Simple textual matching: no parser, no semantic inference.
def has (source pattern : String) : Bool :=
  (source.splitOn pattern).length > 1

def checkLine (line : String) : Array Finding := Id.run do
  -- Ignore single-line comments (block comments/strings need a real parser).
  let code := (line.splitOn "--").head!
  let mut findings : Array Finding := #[]

  if has code "IO.sleep" then
    findings := findings.push ⟨"W-01", "Check whether a fixed wait is necessary"⟩

  if has code "]!" || has code ".get!" then
    findings := findings.push ⟨"W-04", "Check unsafe indexing or unchecked access"⟩

  if has code "sorry" || has code "admit" then
    findings := findings.push ⟨"NG-13", "Review incomplete proof (not automatically a No-Go)"⟩

  return findings

def auditFile (path : System.FilePath) : IO Nat := do
  let source ← IO.FS.readFile path
  let mut lineNo := 0
  let mut count := 0

  for line in source.splitOn "\n" do
    lineNo := lineNo + 1
    for finding in checkLine line do
      IO.println s!"REVIEW {finding.rule}  {path}:{lineNo}  {finding.message}"
      count := count + 1

  return count

def isExcluded (path : System.FilePath) : Bool :=
  path.components.any fun part =>
    part == ".git" || part == ".lake" || part == "node_modules" ||
    part == "dist" || part == "target" || part == "build"

def runAudit (directory : String) (strict : Bool) : IO UInt32 := do
  let root := System.FilePath.mk directory
  if !(← root.isDir) then
    IO.println s!"Not a directory: {directory}"
    return 2

  let paths ← root.walkDir (fun path => pure (!isExcluded path))
  let mut files := 0
  let mut findings := 0

  for path in paths do
    if path.extension == some "lean" && !isExcluded path then
      files := files + 1
      findings := findings + (← auditFile path)

  IO.println s!"Scanned {files} Lean files; {findings} review candidates."
  if strict && findings > 0 then
    IO.println "FAIL (strict mode): review candidates found."
    return 1
  IO.println "PASS: scan completed; findings are not confirmed violations."
  return 0

def main (args : List String) : IO UInt32 := do
  match args with
  | [directory] => runAudit directory false
  | [directory, "--strict"] => runAudit directory true
  | _ =>
    IO.println "Usage: lake exe cqa <path-to-sapiens4> [--strict]"
    return 2
