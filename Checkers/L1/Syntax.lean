import Core.Types
import Lake

namespace Cqa.L1
open Lean

structure SyntaxContext where
  file : String
  source : String
  fileMap : FileMap
  ast : Syntax

def initParser : IO Environment := do
  initSearchPath (← findSysroot)
  unsafe enableInitializersExecution
  importModules #[{ module := `Lean }, { module := `Lake }] {} (loadExts := true)

def isQuotation (s : Syntax) : Bool :=
  [``Parser.Term.quot, ``Parser.Term.precheckedQuot, ``Parser.Command.quot,
    ``Parser.Term.dynamicQuot, ``Parser.Tactic.quot, ``Parser.Tactic.quotSeq].contains s.getKind

partial def findSyntax (predicate : Syntax → Bool) (root : Syntax) : Array Syntax :=
  visit root #[]
where
  visit s found :=
    if isQuotation s then found else
    s.getArgs.foldl (fun acc child => visit child acc)
      (if predicate s then found.push s else found)

private partial def changesGrammar (s : Syntax) : Bool :=
  !isQuotation s && ([`Lean.Parser.Command.syntax, `Lean.Parser.Command.syntaxAbbrev,
    `Lean.Parser.Command.syntaxCat, `Lean.Parser.Command.mixfix,
    `Lean.Parser.Command.notation, `Lean.Parser.Command.macro,
    `Lean.Parser.Command.elab].contains s.getKind ||
  s.getArgs.any changesGrammar)

partial def parse (env : Environment) (file source : String) :
    IO (Except String SyntaxContext) := do
  let input := Parser.mkInputContext source file
  let (header, state, messages) ← Parser.parseHeader input
  let env := if (Elab.HeaderSyntax.imports header).any (fun entry => (`Lake).isPrefixOf entry.module) then
    Parser.parserExtension.activateScoped env `Lake.DSL else env
  let rec commands state messages result : IO (Except String SyntaxContext) := do
    let (command, next, messages) :=
      Parser.parseCommand input { env, options := {} } state messages
    if messages.hasErrors then
      let errors ← messages.toList.filterMapM fun message => do
        if message.severity == .error then return some (← message.toString)
        return none
      return .error (String.intercalate "\n" errors)
    if changesGrammar command then
      return .error "Local syntax extensions require elaboration and are unsupported at L1"
    if Parser.isTerminalCommand command then
      if command.isOfKind ``Parser.Command.eoi then
        return .ok ⟨file, source, input.fileMap, mkNode `Cqa.file (#[header.raw] ++ result)⟩
      return .error "Early parser termination; remaining source was not inspected"
    if next.pos <= state.pos then return .error "Parser made no progress"
    commands next messages (result.push command)
  commands state messages #[]

def named (name : Name) (s : Syntax) : Bool :=
  let s := Parser.Term.dropParens s
  s.isIdent && s.getId == name

def call (name : Name) (s : Syntax) : Bool :=
  s.isOfKind ``Parser.Term.app && named name s[0]

def methodCall (name : String) (s : Syntax) : Bool :=
  if !s.isOfKind ``Parser.Term.app then false else
  let head := Parser.Term.dropParens s[0]
  let id := if head.isOfKind ``Parser.Term.proj then head[2].getId else head.getId
  match id with
  | .str _ last => last == name
  | _ => false

end Cqa.L1
