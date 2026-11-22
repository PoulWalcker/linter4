import Checkers.L0.SourceText

namespace Cqa.L0.SourceRisks

private def words (text : String) : List String :=
  (text.toLower.toList.splitOnP fun c => !c.isAlphanum && c != '_').filterMap fun part =>
    if part.isEmpty then none else some (String.ofList part)

private def credentialName (key : String) : Bool :=
  ["password", "passwd", "secret", "token", "apikey", "api_key", "access_token", "private_key"].any
    fun suffix => key.endsWith suffix

private def credentialValue (value : String) : Bool :=
  value.length ≥ 16 && ["ghp_", "github_pat_", "sk-", "xoxb-", "AKIA"].any (value.startsWith ·)

private def privateKey (text : String) : Bool :=
  text.contains "-----BEGIN " && text.contains "PRIVATE KEY-----"

private def secret (line : Line) : Bool :=
  privateKey line.raw ||
    (line.raw.toList.splitOnP fun c => !c.isAlphanum && c != '_' && c != '-').any
      (credentialValue ∘ String.ofList) ||
    ((line.comment.trimAscii.isEmpty || !line.code.trimAscii.isEmpty) && quoted "" (line.raw.splitOn "\""))
where
  quoted (previous : String) : List String → Bool
    | before :: value :: rest =>
      let parts := before.splitOn ":="
      let lhs := parts.dropLast.getLast?.getD ""
      let rhs := parts.getLast?.getD "" |>.trimAscii.toString
      let before := before.trimAscii.toString
      let key := if before == ":" then previous.toLower
        else (words ((lhs.splitOn ":").head?.getD "")).getLast?.getD ""
      let binding := before == ":" || (!lhs.isEmpty &&
        (rhs.isEmpty || (rhs.startsWith "r" && (rhs.toList.drop 1).all (· == '#'))))
      credentialValue value || (binding && credentialName key && !value.trimAscii.isEmpty) ||
        quoted value rest
    | _ => false

def hiddenLines (source : String) : Array Nat := Id.run do
  let mut hidden := #[]
  let mut pem := false
  for line in lines source do
    pem := pem || privateKey line.raw
    if pem || secret line then hidden := hidden.push line.number
    if line.raw.contains "-----END " && line.raw.contains "PRIVATE KEY-----" then pem := false
  return hidden

private def secrets (rule : Rule) (_ : Array String) (file source : String) : Array Finding :=
  (lines source).filterMap fun line =>
    if secret line then some (finding "hardcoded-secrets" rule file line.number 1 "[redacted]"
      "A private key marker or possible credential literal was found."
      "Check whether this value is a fixture or needs to come from protected configuration.") else none

private def testName (name : String) : Bool :=
  name.startsWith "test" || name.startsWith "spec" || name.startsWith "job" || name.endsWith "test"

private def disabled (rule : Rule) (_ : Array String) (file source : String) : Array Finding :=
  (lines source).filterMap fun line =>
    let code := line.code.toLower
    let commented := words line.comment
    let testFile := (file.replace "\\" "/").splitOn "/" |>.any (fun part =>
      ["jobs", "tests"].contains part.toLower || part.toLower.endsWith "test.lean" || part.toLower == "tests.lean")
    let declaration := match commented with
      | kind :: name :: _ => ["def", "example", "theorem", "test", "job"].contains kind &&
        (testFile || testName name)
      | _ => false
    let marker := ["test.skip", "skiptest", "disabledtest", "@[skip_test"].find? (code.contains ·)
    let flag := (code.contains "if false then" || code.contains "enabled := false") &&
      (testFile || (words code).any testName)
    if declaration || marker.isSome || flag then
      some (finding "disabled-tests" rule file line.number 1
        (if declaration then "[commented declaration]" else marker.getD "[disabled test flag]")
        "A commented test declaration, skip marker, or disabling flag was found."
        "Check whether the relevant test should be active.")
    else none

def secretsCheck : TextCheck := { id := "hardcoded-secrets", run := secrets }
def disabledCheck : TextCheck := { id := "disabled-tests", run := disabled }

end Cqa.L0.SourceRisks
