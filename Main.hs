import Lean

-- Lightweight Lean source scanner. Findings require review.
structure Finding where
  rule : String
  message : String

def has (source pattern : String) : Bool :=
  (source.splitOn pattern).length > 1

-- Ignore single-line comments and quoted strings, including escaped quotes.
-- Block comments and Lean syntax still need proper parsing.
def codeOnly (line : String) : String := Id.run do
  let mut quoted := false
  let mut escaped := false
  let mut result := ""
  for ch in line.toList do
    if quoted then
      if escaped then
        escaped := false
      else if ch == '\\' then
        escaped := true
      else if ch == '"' then
        quoted := false
    else if ch == '"' then
      quoted := true
    else
      result := result.push ch
  return (result.splitOn "--").head!

def checkLine (line : String) : Array Finding := Id.run do
  let code := codeOnly line
  let mut findings : Array Finding := #[]

  if has code "IO.sleep" then
    if has code "while" then
      findings := findings.push ⟨"W-02", "Check whether the polling loop has a deadline"⟩
    else
      findings := findings.push ⟨"W-01", "Check whether waiting for an event is possible"⟩

  if has code "]!" || has code ".get!" then
    findings := findings.push ⟨"W-04", "Check whether bounds and input shape were validated"⟩

  if has code "sorry" || has code "admit" then
    findings := findings.push ⟨"NG-13", "Review incomplete proof (not automatically a No-Go)"⟩

  return findings

def selfTest : IO UInt32 := do
  let tests : Array (String × Bool) := #[
    ("ignore comment", (checkLine "-- by sorry").isEmpty),
    ("ignore quoted text", (checkLine "let msg := \"the scheduler to admit work\"").isEmpty),
    ("detect real sorry", (checkLine "example : True := by sorry").any (fun f => f.rule == "NG-13")),
    ("detect fixed wait", (checkLine "IO.sleep 300").any (fun f => f.rule == "W-01")),
    ("detect polling without visible deadline", (checkLine "while ← hold.pathExists do IO.sleep 50").any (fun f => f.rule == "W-02")),
    ("detect unchecked index", (checkLine "let x := content[0]!").any (fun f => f.rule == "W-04"))
  ]
  let mut failures := 0
  for (name, passed) in tests do
    IO.println ((if passed then "PASS " else "FAIL ") ++ name)
    if !passed then failures := failures + 1
  return if failures == 0 then 0 else 1

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
  let selfTestResult ← selfTest
  if selfTestResult != 0 then
    IO.println "FAIL: auditor self-checks failed."
    return 2
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
    IO.println "FAIL (strict mode): unconfirmed review candidates found."
    return 1
  IO.println "PASS: scan completed; findings are not confirmed violations."
  return 0

def main (args : List String) : IO UInt32 := do
  match args with
  | ["--self-test"] => selfTest
  | [directory] => runAudit directory false
  | [directory, "--strict"] => runAudit directory true
  | _ =>
    IO.println "Usage: lake exe cqa <path-to-sapiens4> [--strict] | --self-test"
    return 2
