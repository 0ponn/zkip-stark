# Stack Overflow Investigation

## Problem
The `AiurSystem.prove` call in `generateSTARKProof` causes a stack overflow when attempting to generate real STARK proofs.

## Current Status
- **Temporary Fix**: Mock proofs are returned to prevent server crashes
- **Root Cause**: Unknown - needs investigation

## Investigation Steps

### 1. FRI Parameters
**Current**: `numQueries := 20` (changed to 100 to match Ix examples)
**Issue**: Lower `numQueries` might cause issues, but 20 should still work

### 2. Circuit Complexity
**Current Circuit**: Very simple - just returns the attribute value
```lean
body := Aiur.Term.ret (Aiur.Term.var (Aiur.Local.str "attr"))
```
**Issue**: The circuit might be too simple, causing the prover to hit edge cases

### 3. Argument Order
**Current**: `publicInputs ++ privateInputs`
**Expected**: Based on `buildClaim`, the order should be:
- `#[functionChannel, .ofNat funIdx] ++ input ++ output`
- But `prove` takes `args` which should be `input` (public + private)

**Potential Issue**: The `args` array might be in the wrong order or missing required values.

### 4. IOBuffer
**Current**: `default` (empty IOBuffer)
**Issue**: Some circuits might require IOBuffer data. Our simple circuit shouldn't, but worth checking.

### 5. Function Index
**Current**: `abi.funIdx := 0`
**Issue**: The function might not exist at index 0, or the bytecode might be malformed.

## Debugging Strategy

### Step 1: Add Logging
Add detailed logging before the `prove` call:
```lean
IO.eprintln s!"System built: {system}"
IO.eprintln s!"FRI params: {friParams}"
IO.eprintln s!"FunIdx: {funIdx}"
IO.eprintln s!"Args: {args}"
IO.eprintln s!"Args length: {args.size}"
```

### Step 2: Test with Minimal Circuit
Try an even simpler circuit that just returns a constant:
```lean
body := Aiur.Term.ret (Aiur.Term.const (Aiur.G.ofNat 1))
```

### Step 3: Check Rust FFI
The stack overflow might be happening in the Rust FFI layer. Check:
- Rust stack size limits
- Recursive calls in `rs_aiur_system_prove`
- Memory allocation issues

### Step 4: Compare with Working Examples
Compare our `prove` call with the working examples in:
- `.lake/packages/ix/Tests/Common.lean`
- `.lake/packages/ix/Benchmarks/Aiur.lean`

**Key Differences Found:**
- Examples use `numQueries := 100` (we changed to match)
- Examples use `default` IOBuffer (we do too)
- Examples pass simple args like `#[10]` (we pass `publicInputs ++ privateInputs`)

### Step 5: Verify Bytecode
Add a check to verify the bytecode is valid:
```lean
let bytecodeValid := bytecodeToplevel.functions.size > 0
if !bytecodeValid then
  IO.eprintln "ERROR: Invalid bytecode"
  return none
```

## Potential Fixes

### Fix 1: Increase Stack Size
If the issue is in Rust, we might need to increase the stack size limit.

### Fix 2: Fix Argument Order
Ensure `args` matches what the circuit expects:
- Public inputs first (merkleRoot, threshold)
- Private inputs second (attribute)

### Fix 3: Use Async/Threading
Move proof generation to a separate thread with its own stack:
```lean
let proofTask ← IO.asTask (generateSTARKProof ...)
-- This might help if it's a stack size issue
```

### Fix 4: Simplify Circuit Further
Try the absolute simplest circuit possible to isolate the issue.

## Next Steps
1. Add detailed logging before `prove` call
2. Test with minimal constant-returning circuit
3. Compare bytecode output with working examples
4. Check Rust FFI implementation for stack issues
5. Consider using async proof generation

