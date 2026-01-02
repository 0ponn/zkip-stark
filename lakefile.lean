import Lake
open System Lake DSL

package zk_ip_protocol where
  version := v!"0.1.0"

require ix from git "https://github.com/argumentcomputer/ix.git" @ "main"

@[default_target]
lean_lib ZkIpProtocol

lean_exe Tests.ProtocolTests where
  root := `Tests.ProtocolTests
  srcDir := "."
  supportInterpreter := true

lean_exe Tests.STARKTests where
  root := `Tests.STARKTests
  srcDir := "."
  supportInterpreter := true

lean_exe Tests.BatchingTests where
  root := `Tests.BatchingTests
  srcDir := "."
  supportInterpreter := true

lean_exe Tests.ZKMBTests where
  root := `Tests.ZKMBTests
  srcDir := "."
  supportInterpreter := true

lean_exe Tests.Validation.MasterValidation where
  root := `Tests.Validation.MasterValidation
  srcDir := "."
  supportInterpreter := true

lean_exe Tests.Validation.SoundnessTests where
  root := `Tests.Validation.SoundnessTests
  srcDir := "."
  supportInterpreter := true

lean_exe Tests.Validation.STARKRoundTripTests where
  root := `Tests.Validation.STARKRoundTripTests
  srcDir := "."
  supportInterpreter := true

lean_exe Tests.Validation.ThroughputBenchmarks where
  root := `Tests.Validation.ThroughputBenchmarks
  srcDir := "."
  supportInterpreter := true

lean_exe Tests.Validation.ZKMBLatencyTests where
  root := `Tests.Validation.ZKMBLatencyTests
  srcDir := "."
  supportInterpreter := true

lean_exe Tests.Validation.RecursiveStabilityTests where
  root := `Tests.Validation.RecursiveStabilityTests
  srcDir := "."
  supportInterpreter := true
