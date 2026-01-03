-- ZkIpProtocol/DebugLogger.lean
-- Conditional debug logging based on environment variable

namespace ZkIpProtocol

/-- Check if debug mode is enabled via DEBUG_ZK environment variable -/
def isDebugEnabled : IO Bool := do
  match (← IO.getEnv "DEBUG_ZK") with
  | some "true" => return true
  | some "1" => return true
  | _ => return false

/-- Debug logger that only outputs if DEBUG_ZK is set -/
def debugLog (message : String) : IO Unit := do
  if (← isDebugEnabled) then
    IO.eprintln s!"[DEBUG] {message}"

/-- Debug logger with formatted string -/
def debugLogF (format : String) (args : Array String) : IO Unit := do
  if (← isDebugEnabled) then
    let mut message := ""
    let mut argIndex := 0
    for c in format.toList do
      if c == '%' && argIndex < args.size then
        message := message ++ args[argIndex]!
        argIndex := argIndex + 1
      else
        message := message ++ String.mk [c]
    IO.eprintln s!"[DEBUG] {message}"

end ZkIpProtocol
