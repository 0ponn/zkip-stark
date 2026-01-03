# Stack Overflow Debugging Progress

## ✅ Step 1: Minimal Constant Circuit (COMPLETED)

**Implementation:**
- Created `PredicateCircuit.toAiurBytecodeMinimal` - simplest possible circuit
  - No inputs
  - Returns constant field element `G.ofNat 1`
  - Tests FFI stability in isolation

**Debugging Infrastructure:**
- Added `testMinimalCircuit` function that:
  - Compiles minimal circuit
  - Logs all intermediate steps
  - Attempts `AiurSystem.prove` with empty args
  - Catches and reports stack overflow if it occurs

**Integration:**
- `generateCertificateWithSTARK` now:
  1. First tests minimal circuit
  2. If minimal circuit fails → FFI issue confirmed
  3. If minimal circuit passes → attempts full predicate circuit
  4. Logs detailed debug info at each step

## 🔄 Step 2: Argument Order Validation (IN PROGRESS)

**Current Status:**
- Added argument count validation in `generateSTARKProof`
- Logs expected vs actual argument counts
- **TODO**: Verify that `publicInputs ++ privateInputs` matches circuit definition order

**Circuit Definition:**
```lean
inputs := [
  ("merkleRoot", field),    -- publicInputs[0]
  ("threshold", field),     -- publicInputs[1]
  ("attr", field)           -- privateInputs[0]
]
```

**Current Call:**
```lean
args := publicInputs ++ privateInputs
-- Should be: [merkleRoot, threshold, attr]
```

**Next Steps:**
- Verify bytecode compilation matches this order
- Compare with working Ix examples

## ⏳ Step 3: Stack Limit Testing (PENDING)

**Test Script Created:**
- `test_stack_overflow.sh` - sets `ulimit -s unlimited` before running service

**Usage:**
```bash
./test_stack_overflow.sh
# Then make API request to trigger proof generation
```

## 📊 Debug Output Format

All debug messages use `[DEBUG]` prefix and go to stderr:

```
[DEBUG] Minimal circuit compiled successfully
[DEBUG] ABI: funIdx=0, publicInputs=0, privateInputs=0
[DEBUG] AiurSystem built successfully
[DEBUG] FRI params: logFinalPolyLen=0, numQueries=100
[DEBUG] About to call AiurSystem.prove...
[DEBUG] funIdx=0, args.size=0, ioBuffer=...
[DEBUG] Proof generated successfully! Claim size: 2
[DEBUG] Proof bytes size: ...
```

## 🎯 Next Actions

1. **Test minimal circuit** - Run API service and make a request
   - If minimal circuit fails → FFI/Rust issue
   - If minimal circuit passes → Issue is in full circuit logic

2. **Validate argument order** - Compare with Ix examples
   - Check `buildClaim` function usage
   - Verify input/output ordering

3. **Test with increased stack** - Use `test_stack_overflow.sh`
   - If unlimited stack fixes it → Resource constraint
   - If still fails → Logic error

## 🔍 Key Files Modified

- `ZkIpProtocol/STARKIntegration.lean`:
  - Added `toAiurBytecodeMinimal`
  - Added `testMinimalCircuit`
  - Enhanced `generateSTARKProof` with logging
  - Enhanced `generateCertificateWithSTARK` with minimal circuit test

- `test_stack_overflow.sh`:
  - Helper script for stack limit testing

