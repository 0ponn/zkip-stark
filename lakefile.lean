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

lean_exe Tests.Validation.ProveVerifyRoundtrip where
  root := `Tests.Validation.ProveVerifyRoundtrip
  srcDir := "."
  supportInterpreter := true
  moreLinkObjs := #[isoc23Shim]

lean_exe Tests.Validation.PredicateSoundness where
  root := `Tests.Validation.PredicateSoundness
  srcDir := "."
  supportInterpreter := true
  moreLinkObjs := #[isoc23Shim]

lean_exe Tests.Validation.CpuBaseline where
  root := `Tests.Validation.CpuBaseline
  srcDir := "."
  supportInterpreter := true
  moreLinkObjs := #[isoc23Shim]

lean_exe Tests.Validation.MerkleScheme where
  root := `Tests.Validation.MerkleScheme
  srcDir := "."
  supportInterpreter := true
  moreLinkObjs := #[isoc23Shim]

lean_exe Tests.Validation.Blake3CircuitSpike where
  root := `Tests.Validation.Blake3CircuitSpike
  srcDir := "."
  supportInterpreter := true
  moreLinkObjs := #[isoc23Shim]

lean_exe Tests.Validation.MerkleNodeHashSpike where
  root := `Tests.Validation.MerkleNodeHashSpike
  srcDir := "."
  supportInterpreter := true
  moreLinkObjs := #[isoc23Shim]

lean_exe Tests.Validation.MerkleCircuitSingle where
  root := `Tests.Validation.MerkleCircuitSingle
  srcDir := "."
  supportInterpreter := true
  moreLinkObjs := #[isoc23Shim]

lean_exe Tests.Validation.MerkleCircuitPath where
  root := `Tests.Validation.MerkleCircuitPath
  srcDir := "."
  supportInterpreter := true
  moreLinkObjs := #[isoc23Shim]

lean_exe Tests.Validation.MerklePredicate where
  root := `Tests.Validation.MerklePredicate
  srcDir := "."
  supportInterpreter := true
  moreLinkObjs := #[isoc23Shim]

lean_exe Tests.Validation.BatchDisclosure where
  root := `Tests.Validation.BatchDisclosure
  srcDir := "."
  supportInterpreter := true
  moreLinkObjs := #[isoc23Shim]

lean_exe Tests.Validation.ScalingStudy where
  root := `Tests.Validation.ScalingStudy
  srcDir := "."
  supportInterpreter := true
  moreLinkObjs := #[isoc23Shim]

lean_exe Tests.Validation.ProofPhaseProfile where
  root := `Tests.Validation.ProofPhaseProfile
  srcDir := "."
  supportInterpreter := true
  moreLinkObjs := #[isoc23Shim]

lean_exe Main where
  root := `Main
  srcDir := "."
  supportInterpreter := true
  moreLinkObjs := #[isoc23Shim]
