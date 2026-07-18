import Lake
open System Lake DSL

package zk_ip_protocol where
  version := v!"0.1.0"

require ix from git "https://github.com/argumentcomputer/ix.git" @ "main"

/--
Compatibility shim object providing `__isoc23_strtol`.

ix's Rust FFI (`libix_ffi.a`, mimalloc) is cargo-built against the system
glibc, whose C23 headers redirect `strtol` to `__isoc23_strtol@GLIBC_2.38`.
Lean's bundled (older) glibc used for the final link lacks that symbol, so
every executable link fails with `undefined symbol: __isoc23_strtol`. We
compile `native/isoc23_shim.c` (with a pre-C23 standard, so its own `strtol`
call is not redirected) and link the object into each executable.
-/
target isoc23Shim pkg : FilePath := do
  let oFile := pkg.buildDir / "native" / "isoc23_shim.o"
  let srcFile := pkg.dir / "native" / "isoc23_shim.c"
  IO.FS.createDirAll (pkg.buildDir / "native")
  proc { cmd := "cc", args := #["-c", "-fPIC", "-std=gnu11",
    "-o", oFile.toString, srcFile.toString] } (quiet := true)
  inputBinFile oFile

@[default_target]
lean_lib ZkIpProtocol

lean_exe Tests.ProtocolTests where
  root := `Tests.ProtocolTests
  srcDir := "."
  supportInterpreter := true
  moreLinkObjs := #[isoc23Shim]

lean_exe Tests.HashTests where
  root := `Tests.HashTests
  srcDir := "."
  supportInterpreter := true
  moreLinkObjs := #[isoc23Shim]

lean_exe Tests.STARKTests where
  root := `Tests.STARKTests
  srcDir := "."
  supportInterpreter := true
  moreLinkObjs := #[isoc23Shim]

lean_exe Tests.BatchingTests where
  root := `Tests.BatchingTests
  srcDir := "."
  supportInterpreter := true
  moreLinkObjs := #[isoc23Shim]

lean_exe Tests.ZKMBTests where
  root := `Tests.ZKMBTests
  srcDir := "."
  supportInterpreter := true
  moreLinkObjs := #[isoc23Shim]

lean_exe Tests.ApiTests where
  root := `Tests.ApiTests
  srcDir := "."
  supportInterpreter := true
  moreLinkObjs := #[isoc23Shim]

lean_exe Tests.Validation.MasterValidation where
  root := `Tests.Validation.MasterValidation
  srcDir := "."
  supportInterpreter := true
  moreLinkObjs := #[isoc23Shim]

lean_exe Tests.Validation.SoundnessTests where
  root := `Tests.Validation.SoundnessTests
  srcDir := "."
  supportInterpreter := true
  moreLinkObjs := #[isoc23Shim]

lean_exe Tests.Validation.STARKRoundTripTests where
  root := `Tests.Validation.STARKRoundTripTests
  srcDir := "."
  supportInterpreter := true
  moreLinkObjs := #[isoc23Shim]

lean_exe Tests.Validation.ThroughputBenchmarks where
  root := `Tests.Validation.ThroughputBenchmarks
  srcDir := "."
  supportInterpreter := true
  moreLinkObjs := #[isoc23Shim]

lean_exe Tests.Validation.ZKMBLatencyTests where
  root := `Tests.Validation.ZKMBLatencyTests
  srcDir := "."
  supportInterpreter := true
  moreLinkObjs := #[isoc23Shim]

lean_exe Tests.Validation.RecursiveStabilityTests where
  root := `Tests.Validation.RecursiveStabilityTests
  srcDir := "."
  supportInterpreter := true
  moreLinkObjs := #[isoc23Shim]

lean_exe Main where
  root := `Main
  srcDir := "."
  supportInterpreter := true
  moreLinkObjs := #[isoc23Shim]
