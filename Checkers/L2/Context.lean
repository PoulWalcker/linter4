import Core.Types
import Lean.Server.References

namespace Cqa.L2
open Lean System

structure Project where
  artifacts : String
  modules : Array String
  pending : Option (Array String)
  deriving FromJson

structure SourceModule where
  file : FilePath
  data : Server.Ilean
  importLines : Array (Name × Nat)

structure Context where
  env : Environment
  root : FilePath
  modules : Array SourceModule

def Context.owner (ctx : Context) (decl : Name) : Option Name := do
  ctx.env.allImportedModuleNames[← ctx.env.getModuleIdxFor? decl]?

def Context.sourceModule (ctx : Context) (name : Name) : Option SourceModule :=
  ctx.modules.find? (·.data.module == name)

def Context.declaration (ctx : Context) (name : String) : CoreM ConstantInfo := do
  let name := name.toName
  unless (ctx.owner name >>= ctx.sourceModule).isSome do
    throwError "Declaration {name} is outside the loaded project or missing"
  getConstInfo name

inductive Subject where
  | decl (name : Name)
  | module (name : Name) (line : Nat := 1)

structure Observation where
  subject : Subject
  message : String
  fix : String
  verified : Bool := false

abbrev Run := Context → CoreM (Array Observation)

structure Check where
  id : String
  prepare : Json → Except String Run

def names (values : Array String) : Except String (Array Name) := do
  if values.isEmpty || values.any (·.trimAscii.isEmpty) then throw "Expected a nonempty list of names"
  return values.map String.toName

structure Scoped where
  declarations : Array String
  forbidden : Array String
  deriving FromJson

def scopedCheck (json : Json) (run : Array String → Array Name → Run) : Except String Run := do
  let config : Scoped ← fromJson? json
  let _ ← names config.declarations
  return run config.declarations (← names config.forbidden)

def sortedNames (values : Array Name) : String :=
  String.intercalate ", " ((values.map (·.toString)).toList.mergeSort (· ≤ ·))

partial def Context.refs (ctx : Context) (root : ConstantInfo) : Array Name :=
  (visit [root.name] {}).toArray
where
  visit : List Name → NameSet → NameSet
    | [], seen => seen
    | name :: rest, seen =>
      if seen.contains name then visit rest seen else
      let next := if name == root.name || (ctx.owner name >>= ctx.sourceModule).isSome then
        (ctx.env.find? name).map (·.getUsedConstantsAsSet.toArray.toList) |>.getD [] else []
      visit (next ++ rest) (seen.insert name)

def Context.location (ctx : Context) (subject : Subject) : FilePath × Nat × Nat × String :=
  match subject with
  | .decl name =>
    match ctx.owner name >>= ctx.sourceModule with
    | some source =>
      let decls : Std.TreeMap String Lsp.DeclInfo := source.data.decls
      match decls.get? name.toString with
      | some decl => (source.file, decl.selectionRangeStartPosLine + 1,
        decl.selectionRangeStartPosCharacter + 1, name.toString)
      | none => (source.file, 1, 1, name.toString)
    | none => (ctx.root, 0, 0, name.toString)
  | .module name line =>
    ((ctx.sourceModule name).map (·.file) |>.getD ctx.root, line, 1, name.toString)

end Cqa.L2
