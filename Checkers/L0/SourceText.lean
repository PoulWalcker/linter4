import Core.Types

namespace Cqa.L0

private inductive Mode where
  | code | block (depth : Nat) | string (hashes : Option Nat) | quoted

structure Line where
  number : Nat
  raw : String
  code : String
  comment : String

private partial def mask (input : List Char) (mode : Mode) (code comment : String) :
    Mode × String × String :=
  match mode, input with
  | _, [] => (mode, code, comment)
  | .code, '-' :: '-' :: rest =>
    (.code, code ++ String.ofList (List.replicate (rest.length + 2) ' '),
      comment ++ "  " ++ String.ofList rest)
  | .code, '/' :: '-' :: rest => mask rest (.block 1) (code ++ "  ") (comment ++ "  ")
  | .block depth, '/' :: '-' :: rest => mask rest (.block (depth + 1)) (code ++ "  ") (comment ++ "  ")
  | .block depth, '-' :: '/' :: rest =>
    mask rest (if depth == 1 then .code else .block (depth - 1)) (code ++ "  ") (comment ++ "  ")
  | .block depth, c :: rest => mask rest (.block depth) (code.push ' ') (comment.push c)
  | .code, '\'' :: '\\' :: _ :: '\'' :: rest => mask rest .code (code ++ "    ") (comment ++ "    ")
  | .code, '\'' :: _ :: '\'' :: rest => mask rest .code (code ++ "   ") (comment ++ "   ")
  | .code, 'r' :: rest =>
    let hashes := (rest.takeWhile (· == '#')).length
    match rest.drop hashes with
    | '"' :: tail =>
      let space := String.ofList (List.replicate (hashes + 2) ' ')
      mask tail (.string (some hashes)) (code ++ space) (comment ++ space)
    | _ => mask rest .code (code.push 'r') (comment.push ' ')
  | .code, '"' :: rest => mask rest (.string none) (code.push ' ') (comment.push ' ')
  | .code, '«' :: rest => mask rest .quoted (code.push ' ') (comment.push ' ')
  | .string none, '\\' :: _ :: rest => mask rest mode (code ++ "  ") (comment ++ "  ")
  | .string hashes, '"' :: rest =>
    let n := hashes.getD 0
    if (List.replicate n '#').isPrefixOf rest then
      let space := String.ofList (List.replicate (n + 1) ' ')
      mask (rest.drop n) .code (code ++ space) (comment ++ space)
    else mask rest mode (code.push ' ') (comment.push ' ')
  | .quoted, '»' :: rest => mask rest .code (code.push ' ') (comment.push ' ')
  | .code, c :: rest => mask rest .code (code.push c) (comment.push ' ')
  | _, _ :: rest => mask rest mode (code.push ' ') (comment.push ' ')

def lines (source : String) : Array Line := Id.run do
  let mut result := #[]
  let mut mode := Mode.code
  for (raw, number) in (source.splitOn "\n").zipIdx 1 do
    let (next, code, comment) := mask raw.toList mode "" ""
    mode := next
    result := result.push ⟨number, raw, code, comment⟩
  return result

def finding (checker : String) (rule : Rule) (file : String) (line column : Nat)
    (evidence message fix : String) : Finding :=
  { checker, rule := rule.id, severity := rule.severity, level := "L0",
    file, line, column, evidence, message, fix }

end Cqa.L0
