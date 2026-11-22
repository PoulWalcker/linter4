import Checkers.L1.Syntax

namespace Cqa.L1.Assertions
open Lean

private def tail (name : Name) : String :=
  match name with | .str _ value => value | _ => ""

private def member (s : Syntax) : String :=
  tail (if s.isOfKind ``Parser.Term.proj then s[2].getId else s.getId)

private def appName (s : Syntax) : String :=
  if s.isOfKind ``Parser.Term.app then member (Parser.Term.dropParens s[0]) else ""

private def isAssertion (s : Syntax) : Bool :=
  ["requireThat", "assertThat", "assertEq", "fieldsMatch", "assertTrue", "assertFalse"].contains (appName s)

private def discarded (s : Syntax) : Bool :=
  match s with
  | `($f <| $x) => named `discard f && isAssertion (Parser.Term.dropParens x)
  | _ => (call `discard s && isAssertion (Parser.Term.dropParens s[1][0])) ||
    (s.isOfKind ``Parser.Term.letIdDecl && s[0][0].isOfKind ``Parser.Term.hole &&
      isAssertion (Parser.Term.dropParens s[4])) ||
    (s.isOfKind ``Parser.Term.doPatDecl && s[0].isOfKind ``Parser.Term.hole &&
      isAssertion (Parser.Term.dropParens (if s[3].isOfKind ``Parser.Term.doExpr then s[3][0] else s[3])))

private def comparison (s : Syntax) : Option (Syntax × Syntax) :=
  match Parser.Term.dropParens s with
  | `($a == $b) | `($a = $b) | `($a != $b) | `($a ≠ $b) =>
    some (Parser.Term.dropParens a, Parser.Term.dropParens b)
  | _ => none

private def stateField (s : Syntax) : Bool :=
  ["state", "status", "phase", "mode"].contains (member s).toLower ||
    ((methodCall "getObjValD" s || methodCall "getObjVal?" s || appName s == "stringField") &&
     (s[1].getArgs.back?.bind Syntax.isStrLit?).any (["state", "status", "phase", "mode"].contains ·))

private def completionValue (s : Syntax) : Bool :=
  s.isStrLit?.any (fun v => ["done", "complete", "completed", "finished", "success", "succeeded"].contains v.toLower)

private def completionCheck (s : Syntax) : Bool :=
  let s := Parser.Term.dropParens s
  ["isOk", "isSuccess", "isFinished", "isDone", "completed"].contains (member s) ||
    (comparison s).any fun (a, b) =>
      (stateField a && completionValue b) || (stateField b && completionValue a) ||
      (member a == "exitCode" && b.isNatLit? == some 0)

private def assertionTerm (s : Syntax) : Option Syntax :=
  if ["requireThat", "assertThat", "assertTrue"].contains (appName s) then s[1].getArgs.back?
  else if s.isOfKind ``Parser.Term.doAssert || s.isOfKind ``Parser.Term.assert then some s[1]
  else none

private def completionOnly (s : Syntax) : Bool :=
  (assertionTerm s).any completionCheck ||
    (appName s == "assertEq" && stateField s[1][0] && completionValue s[1][1]) ||
    (appName s == "fieldsMatch" &&
      let expected := Parser.Term.dropParens s[1][1]
      let fields := expected[1][1].getArgs
      let field := fields[0]?.getD .missing
      expected.isOfKind `Lean.Json.«termJson%_» && expected[1].isOfKind `Lean.Json.«json{_}» &&
        fields.size == 1 && ["status", "state", "phase"].contains field[0][0].getId.toString &&
        completionValue field[2][0])

private def literal (s : Syntax) : Bool :=
  let s := Parser.Term.dropParens s
  s.isOfKind `«term#[_,]» || s.isOfKind `«term[_]» ||
    (s.isOfKind `Lean.Json.«termJson%_» && s[1].isOfKind `Lean.Json.«json[_]») ||
    s.isStrLit?.isSome || s.isNatLit?.isSome

private def exactExpectation (s : Syntax) : Bool :=
  if completionOnly s then false else
  if appName s == "assertEq" then literal s[1][0] || literal s[1][1]
  else if appName s == "fieldsMatch" then literal s[1][1]
  else (assertionTerm s).any fun condition =>
    !(findSyntax (fun t => (comparison t).any (fun (a, b) => literal a || literal b))
      (Parser.Term.dropParens condition)).isEmpty

private def stateComparison (s : Syntax) : Option (String × String) := do
  let (a, b) ← comparison s
  if stateField a then return (a.reprint |>.getD "", ← b.isStrLit?)
  if stateField b then return (b.reprint |>.getD "", ← a.isStrLit?)
  none

private def repeatedStates (root : Syntax) : Array Syntax :=
  let comparisons := (findSyntax (fun s => !s.isOfKind ``Parser.Term.paren) root).filterMap fun s =>
    (stateComparison s).map fun (field, value) => (s, field.trimAscii.toString, value)
  comparisons.filterMap fun (s, field, value) =>
    if !field.isEmpty && comparisons.any (fun (_, other, otherValue) => field == other && value != otherValue)
    then some s else none

def ignored : AstCheck := ⟨"ignored-assertions", fun _ => "Discarded assertion results may let a failing test continue.",
  "Make sure assertion failures propagate.", findSyntax discarded⟩

def completion : AstCheck := ⟨"completion-only", fun _ => "Completion alone does not establish the required behavior.",
  "Also assert the observable outcome.", findSyntax completionOnly⟩

def exact : AstCheck := ⟨"exact-expectations", fun _ => "An exact expected value may make the test unnecessarily strict.",
  "Check whether the contract requires this exact value or order.", findSyntax exactExpectation⟩

def states : AstCheck := ⟨"string-states", fun _ => "String-based states allow misspellings and unexpected values.",
  "Consider an enum if the set of states is fixed.", repeatedStates⟩

end Cqa.L1.Assertions
