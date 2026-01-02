/-
Master Validation Suite
Runs all validation tests and generates a comprehensive report.
-/

import Tests.Validation.SoundnessTests
import Tests.Validation.STARKRoundTripTests
import Tests.Validation.ThroughputBenchmarks
import Tests.Validation.ZKMBLatencyTests
import Tests.Validation.RecursiveStabilityTests

namespace Tests.Validation

/-- Run complete validation suite -/
def runMasterValidation : IO Unit := do
  IO.println ""
  IO.println "╔════════════════════════════════════════════════════════════╗"
  IO.println "║   ZK-IP Protocol: Master Validation Suite                   ║"
  IO.println "║   Moving from 'Production Ready' to 'Verified Reality'     ║"
  IO.println "╚════════════════════════════════════════════════════════════╝"
  IO.println ""

  let timestamp ← IO.getDateTime
  IO.println s!"Validation Date: {timestamp}"
  IO.println ""

  -- Pillar 1: Soundness
  IO.println "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  IO.println "Pillar 1: Soundness (Formal & Cryptographic Validity)"
  IO.println "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  runSoundnessTests
  IO.println ""

  -- STARK Round-Trip
  IO.println "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  IO.println "STARK Round-Trip Integration"
  IO.println "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  runSTARKRoundTripTests
  IO.println ""

  -- Pillar 2: Speed
  IO.println "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  IO.println "Pillar 2: Speed (Hardware & Performance Validity)"
  IO.println "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  runThroughputBenchmarks
  IO.println ""

  -- Application: ZKMB
  IO.println "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  IO.println "Application: ZKMB Validity (Real-World Use Case)"
  IO.println "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  runZKMBLatencyTests
  IO.println ""
  runRecursiveStabilityTests
  IO.println ""

  -- Final Summary
  IO.println "╔════════════════════════════════════════════════════════════╗"
  IO.println "║                    Validation Summary                       ║"
  IO.println "╚════════════════════════════════════════════════════════════╝"
  IO.println ""
  IO.println "✅ All validation tests completed"
  IO.println ""
  IO.println "Next Steps:"
  IO.println "  1. Review test results above"
  IO.println "  2. Address any warnings or failures"
  IO.println "  3. Run: lake build (verify no sorry)"
  IO.println "  4. Update PRODUCTION_READY.md with results"
  IO.println ""

/-- Main entry point -/
def main : IO Unit := runMasterValidation

end Tests.Validation
