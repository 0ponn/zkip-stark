/-
ZK-IP STARK API service: a long-running HTTP/1.1 server on Lean's native async
TCP. It serves one connection at a time, so at most one proof runs at once;
the listen backlog is the queue.

Usage: Main [PORT] [--public]
  ZKIP_API_KEY (required): bearer token for the endpoints that prove.
  Binds 127.0.0.1 unless --public is given, then 0.0.0.0.
  Cap the prover's threads with RAYON_NUM_THREADS before launch;
  scripts/serve.sh defaults it to 4.
-/

import ZkIpProtocol.Api
import Std.Internal.Async.TCP
import Std.Internal.Async.Timer
import Std.Internal.Async.Select

open Lean Std.Net Std.Internal.IO.Async

namespace ZkIpProtocol

def maxHeaderBytes : Nat := 16 * 1024
/-- A verify body carries a whole certificate (about 20 MB of hex). -/
def maxBodyBytes : Nat := 64 * 1024 * 1024
/-- A connection that sends nothing for this long is dropped. -/
def idleTimeoutMs : Nat := 10_000
/-- A request must arrive in full within this long, so a slow client cannot
hold the one-at-a-time queue. -/
def requestDeadlineMs : Nat := 60_000

structure HttpRequest where
  method : String
  path : String
  /-- Header names lowercased. -/
  headers : List (String × String)
  body : String

/-- Equal strings, compared in time independent of where they differ. -/
def constEq (a b : String) : Bool :=
  let x := a.toUTF8
  let y := b.toUTF8
  x.size == y.size && (List.range x.size).foldl (fun acc i => acc ||| (x.get! i ^^^ y.get! i)) 0 == 0

/-- Index of the first `\r\n\r\n` in `b`. -/
def headerEnd? (b : ByteArray) : Option Nat :=
  (List.range (b.size - 3)).find? fun i =>
    b.get! i == 13 && b.get! (i + 1) == 10 && b.get! (i + 2) == 13 && b.get! (i + 3) == 10

/-- Request line and headers, or an error status and message. -/
def parseHead (head : String) : Except (Nat × String) (String × String × List (String × String)) := do
  let lines := head.splitOn "\r\n"
  let some requestLine := lines.head? | throw (400, "empty request")
  let (method, path) ← match requestLine.splitOn " " with
    | m :: p :: _ => pure (m, p)
    | _ => throw (400, "malformed request line")
  let headers := lines.tail.filterMap fun line =>
    match line.splitOn ":" with
    | name :: rest => some (name.trim.toLower, (":".intercalate rest).trim)
    | [] => none
  pure (method, path, headers)

/-- The next chunk from `c`, or `none` at end of stream or after `ms` idle. -/
def recvWithin (c : TCP.Socket.Client) (ms : Nat) : Async (Option ByteArray) := do
  let timeout ← Selector.sleep (Std.Time.Millisecond.Offset.ofNat ms)
  Selectable.one #[.case (c.recvSelector 65536) pure, .case timeout fun _ => pure none]

/-- Read one request, enforcing the size limits and deadlines. -/
def readRequest (c : TCP.Socket.Client) : Async (Except (Nat × String) HttpRequest) := do
  let start ← IO.monoMsNow
  let mut buf := ByteArray.empty
  let mut headEnd : Option Nat := none
  while headEnd.isNone do
    if buf.size > maxHeaderBytes then return .error (431, "request headers too large")
    if (← IO.monoMsNow) - start > requestDeadlineMs then return .error (408, "request timeout")
    match ← recvWithin c idleTimeoutMs with
    | none => return .error (408, "connection idle or closed before the request was complete")
    | some chunk =>
      buf := buf ++ chunk
      headEnd := headerEnd? buf
  let some h := headEnd | return .error (400, "no header terminator")
  if h > maxHeaderBytes then return .error (431, "request headers too large")
  let some head := String.fromUTF8? (buf.extract 0 h) | return .error (400, "headers are not UTF-8")
  let (method, path, headers) ← match parseHead head with
    | .ok r => pure r
    | .error e => return .error e
  let length := ((headers.lookup "content-length").bind String.toNat?).getD 0
  if length > maxBodyBytes then return .error (413, s!"request body over {maxBodyBytes} bytes")
  let bodyStart := h + 4
  while buf.size < bodyStart + length do
    if (← IO.monoMsNow) - start > requestDeadlineMs then return .error (408, "request timeout")
    match ← recvWithin c idleTimeoutMs with
    | none => return .error (408, "connection idle or closed before the body was complete")
    | some chunk => buf := buf ++ chunk
  let some body := String.fromUTF8? (buf.extract bodyStart (bodyStart + length))
    | return .error (400, "body is not UTF-8")
  return .ok { method, path, headers, body }

def handleHealth : IO HttpResponse :=
  return jsonResponse 200 (Json.mkObj [
    ("status", Json.str "healthy"),
    ("service", Json.str "zkip-stark"),
    ("version", Json.str "0.1.0")
  ])

def handleReady : IO HttpResponse :=
  return jsonResponse 200 (Json.mkObj [("status", Json.str "ready")])

/-- Route a request. Proving endpoints need the bearer key; verifying is open,
since it is cheap and meant for third parties. -/
def route (req : HttpRequest) (apiKey : String) : IO HttpResponse := do
  let authorized := match req.headers.lookup "authorization" with
    | some v => constEq v s!"Bearer {apiKey}"
    | none => false
  let needsKey (handler : String → IO HttpResponse) : IO HttpResponse :=
    if authorized then handler req.body else do
      let r ← errorResponse 401 "missing or wrong API key (Authorization: Bearer <key>)"
      return { r with headers := ("WWW-Authenticate", "Bearer") :: r.headers }
  match req.method, req.path with
  | "GET", "/health" => handleHealth
  | "GET", "/ready" => handleReady
  | "POST", "/api/v1/certificate/generate" => needsKey handleGenerate
  | "POST", "/api/v1/certificates/batch" => needsKey handleBatchCertificates
  | "POST", "/api/v1/certificate/verify" => handleVerify req.body
  | _, _ => errorResponse 404 "Not Found"

def formatResponse (resp : HttpResponse) : String :=
  let statusText := match resp.statusCode with
    | 200 => "OK"
    | 400 => "Bad Request"
    | 401 => "Unauthorized"
    | 404 => "Not Found"
    | 408 => "Request Timeout"
    | 413 => "Content Too Large"
    | 431 => "Request Header Fields Too Large"
    | 500 => "Internal Server Error"
    | _ => "Unknown"
  let allHeaders := s!"Content-Length: {resp.body.utf8ByteSize}" :: "Connection: close" ::
    resp.headers.map (fun (k, v) => s!"{k}: {v}")
  s!"HTTP/1.1 {resp.statusCode} {statusText}\r\n{String.join (allHeaders.map (· ++ "\r\n"))}\r\n{resp.body}"

/-- Serve one connection: read, route, respond, close. -/
def serveConnection (c : TCP.Socket.Client) (apiKey : String) : Async Unit := do
  let response ← match ← readRequest c with
    | .error (status, msg) => errorResponse status msg
    | .ok req =>
      try route req apiKey
      catch ex => do
        IO.eprintln s!"request handling error: {ex}"
        errorResponse 500 "internal server error"
  c.send (formatResponse response).toUTF8
  c.shutdown

def serve (addr : SocketAddress) (apiKey : String) : Async Unit := do
  let server ← TCP.Socket.Server.mk
  server.bind addr
  server.listen 128
  while true do
    let client ← server.accept
    try serveConnection client apiKey
    catch ex => IO.eprintln s!"connection error: {ex}"

end ZkIpProtocol

def main (args : List String) : IO UInt32 := do
  let isPublic := args.contains "--public"
  let portArgs := args.filter (· != "--public")
  let some port := (portArgs.head?.getD "8080").toNat?.filter (fun p => 0 < p && p < 65536)
    | IO.eprintln "usage: Main [PORT] [--public]  (PORT 1-65535)"; return 1
  let some apiKey := (← IO.getEnv "ZKIP_API_KEY").filter (·.length ≥ 16)
    | IO.eprintln "ZKIP_API_KEY must be set (16 or more characters): it guards the endpoints that prove."
      return 1
  if (← IO.getEnv "RAYON_NUM_THREADS").isNone then
    IO.eprintln "warning: RAYON_NUM_THREADS is unset, so proofs use every core (scripts/serve.sh defaults it to 4)"
  -- Build the circuit and the single-disclosure shape now, not on the first request.
  let _ ← ZkIpProtocol.fusedEntryFor 1
  let host : IPv4Addr := if isPublic then IPv4Addr.ofParts 0 0 0 0 else IPv4Addr.ofParts 127 0 0 1
  IO.eprintln s!"zkip-stark API listening on {if isPublic then "0.0.0.0" else "127.0.0.1"}:{port}"
  ZkIpProtocol.serve (.v4 { addr := host, port := port.toUInt16 }) apiKey |>.block
  return 0
