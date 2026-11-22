import Checkers.L1.Syntax

namespace Cqa.L1.UnsafeIndexing
open Lean

private def uncheckedAccess (s : Syntax) : Bool :=
  match s with
  | `($_[$_]!) => true
  | _ => methodCall "get!" s || call `getElem! s

private inductive Bound where
  | length (array : Name) (minimum : Nat)
  | index (array index : Name)

private def sizeName (s : Syntax) : Option Name :=
  let s := Parser.Term.dropParens s
  let name := if s.isOfKind ``Parser.Term.proj && named `size s[2] then s[0].getId
    else match s.getId with | .str array "size" => array | _ => .anonymous
  if name.isAnonymous then none else some name

private def lengthBound (a b : Syntax) (extra := 0) : Array Bound :=
  match sizeName a, (Parser.Term.dropParens b).isNatLit? with
  | some name, some n => #[.length name (n + extra)]
  | _, _ => #[]

private def below (index limit : Syntax) : Array Bound :=
  let index := Parser.Term.dropParens index
  lengthBound limit index 1 ++
    if index.isIdent then (sizeName limit).toArray.map (Bound.index · index.getId) else #[]

private partial def conditions (s : Syntax) : Array Bound :=
  match Parser.Term.dropParens s with
  | `($a && $b) => conditions a ++ conditions b
  | `($a == $b) => lengthBound a b ++ lengthBound b a
  | `($a < $b) => below a b
  | `($a > $b) => below b a
  | `($a ≤ $b) => lengthBound b a
  | `($a ≥ $b) => lengthBound a b
  | _ => #[]

private def access (s : Syntax) : Option (Syntax × Syntax) :=
  match s with
  | `($xs[$i]!) => some (xs, i)
  | _ =>
    if call `getElem! s || call `Array.get! s || call `List.get! s then
      some (s[1][0], s[1][1])
    else if methodCall "get!" s then
      let head := Parser.Term.dropParens s[0]
      let array := if head.isOfKind ``Parser.Term.proj then head[0] else
        match head.getId with | .str name _ => mkIdent name | _ => .missing
      some (array, s[1][0])
    else none

private def guarded (bounds : Array Bound) (s : Syntax) : Bool := Id.run do
  let some (array, index) := access s | return false
  unless array.isIdent do return false
  let index := Parser.Term.dropParens index
  return bounds.any fun bound => match bound with
    | .length name n => name == array.getId && index.isNatLit?.any (· < n)
    | .index name i => name == array.getId && index.isIdent && i == index.getId

private def writes (s : Syntax) : Bool :=
  !(findSyntax (fun t => t.isOfKind ``Parser.Term.doReassign ||
    t.isOfKind ``Parser.Term.doReassignArrow) s).isEmpty

private def forgetName (bounds : Array Bound) (name : Name) : Array Bound :=
  bounds.filter fun bound => match bound with
    | .length array _ => !name.isPrefixOf array
    | .index array index => !name.isPrefixOf array && !name.isPrefixOf index

private def forget (bounds : Array Bound) (s : Syntax) : Array Bound :=
  if bounds.isEmpty then #[]
  else if writes s then #[]
  else if s.isOfKind ``Parser.Term.doLet && s[3][0].isOfKind ``Parser.Term.letIdDecl then
    forgetName bounds s[3][0][0][0].getId
  else if s.isOfKind ``Parser.Term.doLetArrow && s[3].isOfKind ``Parser.Term.doIdDecl then
    forgetName bounds s[3][0].getId
  else if [``Parser.Term.doLet, ``Parser.Term.doLetArrow, ``Parser.Term.doHave,
    ``Parser.Term.doLetElse, ``Parser.Term.doLetRec, ``Parser.Term.doErased,
    ``Parser.Term.doErasedArrow].contains s.getKind then #[]
  else bounds

private partial def unchecked (root : Syntax) : Array Syntax :=
  visit #[] root
where
  visit (bounds : Array Bound) (s : Syntax) : Array Syntax := Id.run do
    if isQuotation s then return #[]
    if s.isOfKind ``Parser.Term.doSeqIndent || s.isOfKind ``Parser.Term.doSeqBracketed then
      let items := if s.isOfKind ``Parser.Term.doSeqIndent then s[0] else s[1]
      return (items.getArgs.foldl (fun (found, facts) item =>
        (found ++ visit facts item[0], forget facts item[0])) (#[], bounds)).1
    if s.isOfKind ``Parser.Term.do then return visit bounds s[1]
    if let `(doElem| for $i:ident in [:$limit] do $body) := s then
      let facts := if writes body || writes limit then #[] else
        let rangeFacts := if (sizeName limit).any i.getId.isPrefixOf then #[] else below i limit
        forgetName bounds i.getId ++ rangeFacts
      return visit bounds limit ++ visit facts body
    let branch := match s with
      | `(if $c then $yes else $no) => some (c.raw, yes.raw, no.raw)
      | `(doElem| if $c then $yes else $no) => some (c.raw, yes.raw, no.raw)
      | `(doElem| if $c then $yes) => some (c.raw, yes.raw, Syntax.missing)
      | _ => none
    if let some (condition, yes, no) := branch then
      let changed := writes condition
      let yesFacts := if changed then #[] else bounds ++ conditions condition
      return visit bounds condition ++ visit yesFacts yes ++ visit (if changed then #[] else bounds) no
    let bounds := if [``Parser.Term.basicFun, ``Parser.Term.let, ``Parser.Term.match,
      ``Parser.Term.doMatch, ``Parser.Term.doLetElse, ``Parser.Term.doFor, ``Parser.Term.doIf,
      ``Parser.Term.doCatch, ``Parser.Term.doCatchMatch].contains s.getKind ||
      (!bounds.isEmpty && writes s) then #[] else bounds
    return s.getArgs.foldl (fun acc child => acc ++ visit bounds child)
      (if uncheckedAccess s && !guarded bounds s then #[s] else #[])

def check : AstCheck :=
  ⟨"unchecked-access", "Unchecked access without a recognized local bounds check.",
    "Use checked access or establish its precondition.", unchecked⟩

end Cqa.L1.UnsafeIndexing
