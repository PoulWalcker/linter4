import Cases
import Infra
import Unused

abbrev Status := String

def internalRule (status : Status) : Bool := status == "active"

abbrev Computation := IO Nat

def compute (n : Nat) : Computation := pure (n + 1)

def readFixture : IO String := readOutput

def decision : IO String := readFixture

theorem requiredProof (_ : Bool) : True := And.left (And.intro foundation unapproved)

def requiredJob : IO Unit := IO.println seed

def otherJob : IO Unit := pure ()

def registered : List (String × IO Unit) := [("Other", otherJob)]

def main : IO Unit := otherJob
