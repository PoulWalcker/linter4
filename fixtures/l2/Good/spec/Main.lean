import Cases
import Lean.Data.Json

structure Status where
  active : Bool

def internalRule (status : Status) : Bool := status.active

def compute (n : Nat) : Nat := n + 1

def decision : Nat := seed

theorem requiredProof (_ : Nat) : True := True.intro

def fixturePayload : Lean.Json := Lean.toJson "active"

def requiredJob : IO Unit := IO.println s!"{compute decision}: {fixturePayload.compress}"

def registered : List (String × IO Unit) := [("Required", requiredJob)]

def main : IO Unit := do
  for (_, job) in registered do
    job
