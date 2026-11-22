import Core.Types

namespace Cqa
open Lean

private def checkedFiles (report : Report) : Nat :=
  report.files - (report.errors.toList.map (·.file)).eraseDups.length

private def indent (text : String) : String :=
  String.intercalate "\n" (text.splitOn "\n" |>.map ("  " ++ ·))

def renderSummary (report : Report) : String :=
  let rules := (report.findings.toList.map (·.rule)).eraseDups.mergeSort (· ≤ ·)
  let counts := rules.map fun rule =>
    s!"`{rule}`: {(report.findings.filter (·.rule == rule)).size}"
  let parsed := checkedFiles report
  let headline := s!"**CQA {report.level}** · {report.status} · {parsed}/{report.files} files · {report.findings.size} review candidates · {report.errors.size} errors"
  if counts.isEmpty then headline else headline ++ "\n\n" ++ String.intercalate " · " counts

def renderReport (report : Report) (json : Bool) : String :=
  if json then (toJson report).pretty else
  let result := if report.errors.isEmpty then "Complete" else "Incomplete"
  let summary := s!"CQA — {report.level}\nChecked: {checkedFiles report}/{report.files} files\nFindings: {report.findings.size}\nScan errors: {report.errors.size}\nResult: {result}"
  let findings := report.findings.toList.map fun f =>
    s!"[{f.severity.text}] {f.rule} · {f.level}\n{f.file}:{f.line}:{f.column}\n\n{indent f.evidence}\n\nFound: {f.message}\nReview: {f.fix}"
  let errors := if report.errors.isEmpty then [] else
    let entries := report.errors.toList.map fun e =>
      s!"[{e.level}] {e.file}\n{indent e.message}\n  This file was not checked."
    ["Scan errors\n" ++ String.intercalate "\n\n" entries]
  String.intercalate "\n\n" ([summary] ++ findings ++ errors)

end Cqa
