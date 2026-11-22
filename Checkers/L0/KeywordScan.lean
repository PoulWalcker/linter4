import Checkers.L0.SourceText

namespace Cqa.L0.KeywordScan

private def word (c : Char) : Bool := c.isAlphanum || c == '_' || c == '\'' || c == '!' || c == '?'

private def explain : String → String × String
  | "sorry" | "admit" => ("Proof placeholder bypasses a complete proof.", "Complete the required proof.")
  | "axiom" => ("An axiom introduces an unproved assumption.", "Check that the assumption is allowed.")
  | "IO.sleep" => ("Timed waiting may make the test unstable.", "If waiting for readiness, check the condition with a timeout.")
  | "getD" | "getObjValD" => ("A default value may hide missing data.", "Handle absence explicitly unless the default is intentional.")
  | "toOption" => ("Conversion to Option discards the error details.", "Preserve the error if the scenario must fail.")
  | "catch" | "Except.ok" => ("Error handling may turn a failure into a normal result.", "Check that required failures still stop the scenario.")
  | "unsafe" | "partial" | "panic!" => ("This operation needs a review of its safety or termination assumptions.", "Check its preconditions and failure handling.")
  | "discard" | "let _ ←" | "let _ <-" | "let _ :=" => ("An ignored result may hide a failure.", "Propagate the result if it affects scenario success.")
  | "dbg_trace" => ("Debug output remains in the source.", "Remove it unless it is required.")
  | "TODO" | "FIXME" => ("An unfinished work marker remains.", "Complete the work or remove an outdated marker.")
  | _ => ("A configured review marker appears in the source.", "Review this marker in context.")

private def scan (tokens : Bool) (id : String) (rule : Rule) (patterns : Array String)
    (file source : String) : Array Finding := Id.run do
  let mut findings := #[]
  for line in lines source do
    let text := if tokens then line.code else line.raw
    for pattern in patterns do
      let mut column := 1
      let mut before := false
      let parts := text.splitOn pattern
      for (chunk, next) in parts.zip (parts.drop 1) do
        let offset := column + chunk.length
        let left := if chunk.isEmpty then before else chunk.toList.getLast?.any word
        let right := next.toList.head?.any word
        if !tokens || ((!left || !pattern.toList.head?.any word) &&
            (!right || !pattern.toList.getLast?.any word)) then
          let (message, fix) := explain pattern
          findings := findings.push (finding id rule file line.number offset pattern message
            fix)
        column := offset + pattern.length
        before := pattern.toList.getLast?.any word
  return findings

def check : TextCheck := ⟨"keyword-scan", scan false "keyword-scan", true⟩

def codeCheck : TextCheck := ⟨"code-markers", scan true "code-markers", true⟩

end Cqa.L0.KeywordScan
