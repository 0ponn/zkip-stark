/-
ZK-IP STARK API Service
Simple HTTP API for generating and verifying ZK certificates
-/

import ZkIpProtocol.STARKIntegration
import ZkIpProtocol.Advertisement
import ZkIpProtocol.CoreTypes
import ZkIpProtocol.MerkleCommitment
import ZkIpProtocol.Api
import Lean.Data.Json

open Lean

namespace ZkIpProtocol

-- All these definitions are now in Api.lean, just use them directly
-- They're in the same namespace, so we can use them directly

/-- Handle POST /api/v1/certificate/generate -/
def handleGenerateCertificate (body : String) : IO HttpResponse := do
  -- Use the implementation from Api.lean
  handleGenerate body

/-- Handle POST /api/v1/certificates/batch -/
def handleBatchCertificates (body : String) : IO HttpResponse := do
  let json ← match Json.parse body with
    | .ok j => pure j
    | .error err => return (← errorResponse 400 s!"Invalid JSON: {err}")

  -- Parse batch request: { "requests": [ { "ixon": {...}, "predicate": {...}, "privateAttribute": N }, ... ] }
  let requestsJson ← match (Json.getObjVal? json "requests" >>= Json.getArr?).toOption with
    | some arr => pure arr
    | none => return (← errorResponse 400 "Missing 'requests' array")

  if requestsJson.isEmpty then
    return (← errorResponse 400 "Empty requests array")

  -- Process each request
  let mut results : Array Json := #[]
  let mut successCount := 0
  let mut failureCount := 0

  for reqJson in requestsJson do
    let cert? ← try
      let ixon? := parseIxon reqJson
      let predicate? := (Json.getObjVal? reqJson "predicate").toOption >>= parseIPPredicate
      let privateAttribute? := (Json.getObjVal? reqJson "privateAttribute" >>= Json.getNat?).toOption

      match ixon?, predicate?, privateAttribute? with
      | some ixon, some predicate, some privateAttribute =>
        -- Build IP data from attributes for Merkle tree
        let ipData := ixon.attributes.map (fun attr =>
          match attr with
          | .performance n => natToByteArray n
          | .security n => natToByteArray n
          | .efficiency n => natToByteArray n
          | .custom _ n => natToByteArray n
        )

        -- Compute Merkle root if not provided
        let ixonWithRoot ← if ixon.merkleRoot.isEmpty then do
          let root ← buildMerkleTree ipData
          pure { ixon with merkleRoot := root }
        else
          pure ixon

        let attributeIndex := 0  -- Default to first attribute

        -- Generate certificate
        generateCertificateWithSTARK
          ixonWithRoot
          predicate
          privateAttribute
          ipData
          attributeIndex
      | _, _, _ => pure none

    catch ex => do
      let stderr ← IO.getStderr
      stderr.putStrLn s!"Batch certificate generation exception: {ex}"
      pure none

    match cert? with
    | some cert =>
      results := results.push (certificateToJson cert)
      successCount := successCount + 1
    | none =>
      results := results.push (Json.mkObj [("error", Json.str "Failed to generate certificate")])
      failureCount := failureCount + 1

  return jsonResponse 200 (Json.mkObj [
    ("success", Json.bool true),
    ("total", Json.num requestsJson.size),
    ("succeeded", Json.num successCount),
    ("failed", Json.num failureCount),
    ("certificates", Json.arr results)
  ])

/-- Handle POST /api/v1/certificate/verify -/
def handleVerifyCertificate (body : String) : IO HttpResponse := do
  -- Use the real implementation from Api.lean
  handleVerify body

/-- Handle GET /health -/
def handleHealth : IO HttpResponse :=
  return jsonResponse 200 (Json.mkObj [
    ("status", Json.str "healthy"),
    ("service", Json.str "zkip-stark"),
    ("version", Json.str "0.1.0")
  ])

/-- Handle GET /ready -/
def handleReady : IO HttpResponse :=
  return jsonResponse 200 (Json.mkObj [
    ("status", Json.str "ready")
  ])

/-- Parse HTTP request -/
def parseRequest (request : String) : Option (String × String) := do
  let lines := request.splitOn "\r\n"
  let firstLine ← lines[0]?
  let parts := firstLine.splitOn " "
  if parts.length < 2 then none
  else some (parts[0]!.trim, parts[1]!.trim)

/-- Extract request body from HTTP request -/
def extractBody (request : String) : String :=
  let parts := request.splitOn "\r\n\r\n"
  if parts.length > 1 then parts[1]! else ""

/-- Handle HTTP request -/
def handleRequest (request : String) : IO HttpResponse := do
  let (method, path) ← match parseRequest request with
    | some (m, p) => pure (m, p)
    | none => return (← errorResponse 400 "Invalid request format")

  match method, path with
  | "GET", "/health" => handleHealth
  | "GET", "/ready" => handleReady
  | "POST", "/api/v1/certificate/generate" =>
    let body := extractBody request
    handleGenerateCertificate body
  | "POST", "/api/v1/certificates/batch" =>
    let body := extractBody request
    handleBatchCertificates body
  | "POST", "/api/v1/certificate/verify" =>
    let body := extractBody request
    handleVerifyCertificate body
  | _, _ => return (← errorResponse 404 "Not Found")

/-- Format HTTP response -/
def formatResponse (resp : HttpResponse) : String :=
  let statusText := match resp.statusCode with
    | 200 => "OK"
    | 400 => "Bad Request"
    | 404 => "Not Found"
    | 500 => "Internal Server Error"
    | _ => "Unknown"
  let contentLength := s!"Content-Length: {resp.body.utf8ByteSize}"
  let allHeaders := contentLength :: resp.headers.map (fun (k, v) => s!"{k}: {v}")
  let headersStr := String.join (allHeaders.map (· ++ "\r\n"))
  -- Ensure proper HTTP/1.1 format: status line, headers, empty line, body
  s!"HTTP/1.1 {resp.statusCode} {statusText}\r\n{headersStr}\r\n{resp.body}"

/-- Parse headers until empty line and extract Content-Length -/
partial def parseHeaders (hIn : IO.FS.Stream) (acc : List String) : IO (List String × Option Nat) := do
  let line ← hIn.getLine
  if line.trim.isEmpty then
    return (acc, none)
  else
    let trimmed := line.trim
    -- Check for Content-Length header
    let contentLength := if trimmed.toLower.startsWith "content-length:" then
      let lenStr := trimmed.splitOn ":" |>.getD 1 "" |>.trim
      String.toNat? lenStr
    else
      none
    let (rest, foundLength) ← parseHeaders hIn (trimmed :: acc)
    return (rest, contentLength <|> foundLength)

/-- Simple HTTP server using stdin/stdout (works with reverse proxy or netcat) -/
def serveStream (hIn : IO.FS.Stream) (hOut : IO.FS.Stream) : IO Unit := do
  -- Read request line (getLine includes the newline)
  let firstLine ← hIn.getLine
  if firstLine.trim.isEmpty then
    return

  -- Read headers until empty line and get Content-Length
  let (headers, contentLength) ← parseHeaders hIn []
  let headersReversed := headers.reverse

  -- Read body if Content-Length is specified
  let body ← match contentLength with
    | some len =>
      if len > 0 then do
        let bodyBytes ← hIn.read (USize.ofNat len)
        match String.fromUTF8? bodyBytes with
        | some s => pure s
        | none => pure ""
      else
        pure ""
    | none => pure ""

  -- Build request string
  let requestLine := firstLine.trim
  let requestStr := requestLine ++ "\r\n" ++ String.join (headersReversed.map (· ++ "\r\n")) ++ "\r\n" ++ body

  -- Wrap request handling in try-catch to prevent server crashes
  let response ← try
    handleRequest requestStr
  catch ex => do
    let stderr ← IO.getStderr
    stderr.putStrLn s!"Request handling error: {ex}"
    errorResponse 500 s!"Internal server error: {ex}"

  let responseStr := formatResponse response
  -- Use putStr to write the response (handles UTF-8 correctly)
  hOut.putStr responseStr
  hOut.flush

/-- Simple HTTP server loop -/
def serve (port : UInt16) : IO Unit := do
  -- Send startup messages to stderr, not stdout (stdout is for HTTP responses)
  let stderr ← IO.getStderr
  stderr.putStrLn s!"Starting ZK-IP STARK API Service on port {port}..."
  stderr.putStrLn "Endpoints:"
  stderr.putStrLn "  GET  /health"
  stderr.putStrLn "  GET  /ready"
  stderr.putStrLn "  POST /api/v1/certificate/generate"
  stderr.putStrLn "  POST /api/v1/certificates/batch"
  stderr.putStrLn "  POST /api/v1/certificate/verify"
  stderr.putStrLn ""
  stderr.putStrLn "Note: Using stdin/stdout mode. Use with:"
  stderr.putStrLn "  socat TCP-LISTEN:8080,fork,reuseaddr EXEC:'lake exe Main'"
  stderr.putStrLn "  or configure your reverse proxy to use this executable"

  -- Use stdin/stdout for simplicity (can be wrapped by systemd, docker, etc.)
  let hIn ← IO.getStdin
  let hOut ← IO.getStdout
  serveStream hIn hOut

end ZkIpProtocol

/-- Main entry point - must be at root level for executable -/
def main (args : List String) : IO UInt32 := do
  let portStr := match args[0]? with
    | some p => p
    | none => "8080"

  let port ← match String.toNat? portStr with
    | some p =>
      if p > 65535 then
        IO.eprintln s!"Error: Port {p} is too large (max 65535)"
        return 1
      else if p == 0 then
        IO.eprintln "Error: Port 0 is not valid"
        return 1
      else
        pure (UInt16.ofNat p)
    | none =>
      IO.eprintln s!"Error: Invalid port number '{portStr}'. Use a number between 1-65535."
      IO.eprintln "Usage: Main [PORT]"
      IO.eprintln "Example: Main 8080"
      return 1

  ZkIpProtocol.serve port
  return 0
