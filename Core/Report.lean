import Core.Types

namespace Cqa
open Lean

def renderSummary (report : Report) : String :=
  let rules := (report.findings.toList.map (·.rule)).eraseDups.mergeSort (· ≤ ·)
  let counts := rules.map fun rule =>
    s!"`{rule}`: {(report.findings.filter (·.rule == rule)).size}"
  let parsed := report.files - report.errors.size
  let headline := s!"**CQA {report.level}** · {report.status} · {parsed}/{report.files} files · {report.findings.size} review candidates · {report.errors.size} errors"
  if counts.isEmpty then headline else headline ++ "\n\n" ++ String.intercalate " · " counts

def renderReport (report : Report) (json : Bool) : String :=
  if json then (toJson report).pretty else
  let findings := report.findings.toList.map fun f =>
    s!"REVIEW {f.rule} ({f.severity.text}) [{f.checker}] {f.file}:{f.line}:{f.column}\n  {f.evidence}\n  {f.message}\n  Fix: {f.fix}"
  let errors := report.errors.toList.map fun e => s!"INCOMPLETE {e.file}: {e.message}"
  let summary := s!"L1 Lean: {report.files} files; {report.findings.size} review candidates; {report.status}."
  String.intercalate "\n" (findings ++ errors ++ [summary])

end Cqa
