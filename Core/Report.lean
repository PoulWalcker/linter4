import Core.Types

namespace Cqa
private def pad (text : String) (width : Nat) : String :=
  text ++ String.ofList (List.replicate (width - text.length) ' ')

def renderReport (report : Report) : String :=
  let sourceErrors := report.errors.toList.filter fun e => report.level == "L2" || e.level != "L2"
  let checked := report.files - (sourceErrors.map (·.file)).eraseDups.length
  let semantic := report.semanticFiles.map (fun files => s!"\nL2 scope: {files} compiled spec files") |>.getD ""
  let header := s!"Linter4\nLevels: {String.intercalate ", " report.levels.toList}\nChecked {checked}/{report.files} files{semantic}"
  let files := (report.findings.toList.map (·.file)).eraseDups.mergeSort (· ≤ ·)
  let groups := files.map fun file =>
    let findings := (report.findings.filter (·.file == file)).qsort fun a b =>
      a.line < b.line || (a.line == b.line && a.column < b.column)
    let positions := findings.map fun f => s!"{f.line}:{f.column}"
    let width := positions.foldl (fun n p => max n p.length) 0
    let rows := (findings.zip positions).toList.map fun (f, position) =>
      let subject := if f.level == "L2" then s!"{f.evidence}: " else ""
      s!"  {pad position width}  {pad f.severity.label 15}  {subject}{f.message} {f.fix} [{f.level}/{f.rule}]"
    file ++ "\n" ++ String.intercalate "\n" rows
  let count := fun severity => (report.findings.filter (·.severity == severity)).size
  let noun := if report.findings.size == 1 then "issue" else "issues"
  let summary := s!"{report.findings.size} {noun}: {count .noGo} NO-GO, {count .warning} Warning, {count .improvement} Could be better\nScan errors: {report.errors.size}"
  let errors := if report.errors.isEmpty then [] else
    ["Scan errors\n" ++ String.intercalate "\n" (report.errors.toList.map fun e =>
      s!"  [{e.level}] {e.file}\n    {e.message.replace "\n" "\n    "}")]
  let pending := report.notVerified.toList.map ("  " ++ ·)
  let unverified := if pending.isEmpty then [] else ["NOT_VERIFIED\n" ++ String.intercalate "\n" pending]
  String.intercalate "\n\n" ([header] ++ groups ++ [summary] ++ errors ++ unverified)

end Cqa
