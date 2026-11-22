import Core.Types

namespace Cqa.L0.KeywordScan

private def checkerId := "keyword-scan"

private def scan (rule : Rule) (patterns : Array String) (file source : String) : Array Finding := Id.run do
  let mut findings := #[]
  for (text, line) in (source.splitOn "\n").zipIdx 1 do
    for pattern in patterns do
      let mut column := 1
      for chunk in (text.splitOn pattern).dropLast do
        column := column + chunk.length
        findings := findings.push {
          checker := checkerId, rule := rule.id, severity := rule.severity
          level := "L0", file, line, column, evidence := pattern
          message := "Configured text matches this source location."
          fix := "Review the surrounding source and resolve the marker if applicable."
        }
        column := column + pattern.length
  return findings

def check : TextCheck := ⟨checkerId, scan⟩

end Cqa.L0.KeywordScan
