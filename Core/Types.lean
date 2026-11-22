import Lean

namespace Cqa
open Lean

inductive Severity where
  | noGo | warning | improvement
  deriving BEq

def Severity.text : Severity → String
  | .noGo => "no-go"
  | .warning => "warning"
  | .improvement => "improvement"

def Severity.label : Severity → String
  | .noGo => "NO-GO"
  | .warning => "Warning"
  | .improvement => "Could be better"

instance : FromJson Severity where
  fromJson? json := do
    match ← json.getStr? with
    | "no-go" => return .noGo
    | "warning" => return .warning
    | "improvement" => return .improvement
    | value => throw s!"Unknown severity: {value}"

instance : ToJson Severity where
  toJson value := toJson value.text

structure CheckConfig where
  level : String
  checker : String
  patterns : Option (Array String)
  params : Option Json
  deriving FromJson

structure Rule where
  id : String
  name : String
  severity : Severity
  enabled : Bool
  checks : Array CheckConfig
  deriving FromJson

structure Config where
  rules : Array Rule
  deriving FromJson

structure Finding where
  checker : String
  rule : String
  severity : Severity
  status : String := "candidate"
  level : String := "L1"
  file : String
  line : Nat
  column : Nat
  evidence : String
  message : String
  fix : String
  deriving ToJson

structure AstCheck where
  id : String
  message : Syntax → String
  fix : String
  run : Syntax → Array Syntax

structure TextCheck where
  id : String
  run : Rule → Array String → String → String → Array Finding
  requiresPatterns : Bool := false

structure SelectedChecks where
  text : Array (Rule × TextCheck × Array String)
  ast : Array (Rule × AstCheck)

structure ScanError where
  file : String
  message : String
  level : String := "L1"
  deriving ToJson

structure Report where
  level : String := "FULL"
  levels : Array String
  language : String := "Lean"
  status : String
  files : Nat
  checks : Array String
  findings : Array Finding
  errors : Array ScanError
  notVerified : Array String := #[]
  semanticFiles : Option Nat := none
  deriving ToJson

end Cqa
