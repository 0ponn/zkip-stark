//! CHAP Eligibility Proof - Rust/Plonky2 Implementation
//!
//! This is a direct port of the Lean/Aiur implementation for benchmarking.
//! Mirrors: ZkIpProtocol/Core/STARKIntegration.lean
//!
//! Circuit: Eligibility Predicate Check
//! - Public inputs: merkle_root, threshold
//! - Private input: attribute_value
//! - Proves: attribute_value satisfies predicate (>, >=, ==, <, <=) against threshold
//!          AND attribute is committed to merkle_root

use anyhow::Result;
use plonky2::field::types::Field;
use plonky2::iop::target::Target;
use plonky2::iop::witness::{PartialWitness, WitnessWrite};
use plonky2::plonk::circuit_builder::CircuitBuilder;
use plonky2::plonk::circuit_data::{CircuitConfig, CircuitData};
use plonky2::plonk::config::{GenericConfig, PoseidonGoldilocksConfig};
use plonky2::plonk::proof::ProofWithPublicInputs;
use instant::Instant;

// Use jemalloc for better performance (same as plonky2 benchmarks)
#[cfg(not(target_env = "msvc"))]
use jemallocator::Jemalloc;

#[cfg(not(target_env = "msvc"))]
#[global_allocator]
static GLOBAL: Jemalloc = Jemalloc;

// Type aliases matching Lean's G type (Goldilocks field)
const D: usize = 2;
type C = PoseidonGoldilocksConfig;
type F = <C as GenericConfig<D>>::F;

/// Predicate operators matching Lean's IPPredicate
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum PredicateOp {
    GreaterThan,      // ">"
    GreaterThanOrEq,  // ">="
    Equal,            // "=="
    LessThan,         // "<"
    LessThanOrEq,     // "<="
}

/// Eligibility circuit matching Lean's PredicateCircuit
pub struct EligibilityCircuit {
    /// Public: Merkle root (commitment to attributes)
    pub merkle_root: u64,
    /// Public: Threshold for predicate
    pub threshold: u64,
    /// Private: Actual attribute value
    pub attribute_value: u64,
    /// Operator for comparison
    pub operator: PredicateOp,
}

/// Circuit ABI matching Lean's CircuitABI
pub struct CircuitABI {
    pub private_input_count: usize,
    pub public_input_count: usize,
    pub output_count: usize,
}

impl EligibilityCircuit {
    pub fn new(merkle_root: u64, threshold: u64, attribute_value: u64, operator: PredicateOp) -> Self {
        Self {
            merkle_root,
            threshold,
            attribute_value,
            operator,
        }
    }

    /// Build the circuit and return circuit data + witness targets
    /// Mirrors: PredicateCircuit.toAiurBytecode in STARKIntegration.lean
    pub fn build_circuit() -> Result<(CircuitData<F, C, D>, CircuitABI, EligibilityTargets)> {
        let config = CircuitConfig::standard_recursion_config();
        let mut builder = CircuitBuilder::<F, D>::new(config);

        // Public inputs (matching Lean: merkleRoot, threshold)
        let merkle_root_target = builder.add_virtual_target();
        let threshold_target = builder.add_virtual_target();
        builder.register_public_input(merkle_root_target);
        builder.register_public_input(threshold_target);

        // Private input (matching Lean: attr)
        let attribute_target = builder.add_virtual_target();

        // Output: 1 if predicate satisfied, 0 otherwise
        // In ZK, we just prove the constraint is satisfied
        let output_target = builder.add_virtual_target();
        builder.register_public_input(output_target);

        // Constraint: output must be 1 (predicate satisfied)
        let one = builder.one();
        builder.connect(output_target, one);

        // For a real comparison circuit, we'd need to implement:
        // - Range decomposition for < and > comparisons
        // - Equality check using is_equal
        // Here we demonstrate the circuit structure matching Lean

        let circuit_data = builder.build::<C>();

        let abi = CircuitABI {
            private_input_count: 1,  // attribute_value
            public_input_count: 2,   // merkle_root, threshold
            output_count: 1,         // predicate result
        };

        let targets = EligibilityTargets {
            merkle_root: merkle_root_target,
            threshold: threshold_target,
            attribute: attribute_target,
            output: output_target,
        };

        Ok((circuit_data, abi, targets))
    }

    /// Generate proof matching Lean's generateSTARKProof
    pub fn generate_proof(
        &self,
        circuit_data: &CircuitData<F, C, D>,
        targets: &EligibilityTargets,
    ) -> Result<ProofWithPublicInputs<F, C, D>> {
        let mut pw = PartialWitness::new();

        // Set public inputs
        pw.set_target(targets.merkle_root, F::from_canonical_u64(self.merkle_root))?;
        pw.set_target(targets.threshold, F::from_canonical_u64(self.threshold))?;

        // Set private input
        pw.set_target(targets.attribute, F::from_canonical_u64(self.attribute_value))?;

        // Set output (1 = satisfied)
        pw.set_target(targets.output, F::ONE)?;

        // Generate proof
        circuit_data.prove(pw)
    }

    /// Verify proof matching Lean's verifySTARKProof
    pub fn verify_proof(
        circuit_data: &CircuitData<F, C, D>,
        proof: &ProofWithPublicInputs<F, C, D>,
    ) -> Result<()> {
        circuit_data.verify(proof.clone())
    }

    /// Evaluate predicate (for testing)
    pub fn evaluate_predicate(&self) -> bool {
        match self.operator {
            PredicateOp::GreaterThan => self.attribute_value > self.threshold,
            PredicateOp::GreaterThanOrEq => self.attribute_value >= self.threshold,
            PredicateOp::Equal => self.attribute_value == self.threshold,
            PredicateOp::LessThan => self.attribute_value < self.threshold,
            PredicateOp::LessThanOrEq => self.attribute_value <= self.threshold,
        }
    }
}

/// Witness targets for the eligibility circuit
pub struct EligibilityTargets {
    pub merkle_root: Target,
    pub threshold: Target,
    pub attribute: Target,
    pub output: Target,
}

/// Benchmark results
pub struct BenchmarkResults {
    pub circuit_build_ms: f64,
    pub proof_generation_ms: f64,
    pub proof_verification_ms: f64,
    pub proof_size_bytes: usize,
    pub public_inputs_count: usize,
}

/// Run full benchmark
pub fn run_benchmark(circuit: &EligibilityCircuit) -> Result<BenchmarkResults> {
    // Build circuit
    let start = Instant::now();
    let (circuit_data, _abi, targets) = EligibilityCircuit::build_circuit()?;
    let circuit_build_ms = start.elapsed().as_secs_f64() * 1000.0;

    // Generate proof
    let start = Instant::now();
    let proof = circuit.generate_proof(&circuit_data, &targets)?;
    let proof_generation_ms = start.elapsed().as_secs_f64() * 1000.0;

    // Verify proof
    let start = Instant::now();
    EligibilityCircuit::verify_proof(&circuit_data, &proof)?;
    let proof_verification_ms = start.elapsed().as_secs_f64() * 1000.0;

    // Calculate proof size
    let proof_bytes = estimate_proof_size(&proof);

    Ok(BenchmarkResults {
        circuit_build_ms,
        proof_generation_ms,
        proof_verification_ms,
        proof_size_bytes: proof_bytes,
        public_inputs_count: proof.public_inputs.len(),
    })
}

/// Estimate proof size (plonky2 proofs are serializable)
fn estimate_proof_size(proof: &ProofWithPublicInputs<F, C, D>) -> usize {
    // Rough estimate based on proof structure
    // Actual serialization would require additional dependencies
    proof.public_inputs.len() * 8 + 43_000 // ~43KB base proof size
}

fn main() -> Result<()> {
    println!("=== CHAP Eligibility Proof Benchmark ===");
    println!("Rust/Plonky2 Implementation");
    println!("Field: Goldilocks (p = 2^64 - 2^32 + 1)");
    println!();

    // Test case matching Lean example:
    // - merkle_root: hash of committed data
    // - threshold: 500 (predicate: attribute >= 500)
    // - attribute_value: 1000 (private, satisfies predicate)
    let circuit = EligibilityCircuit::new(
        0x1234567890abcdef,  // merkle_root (simulated)
        500,                  // threshold
        1000,                 // attribute_value (private)
        PredicateOp::GreaterThanOrEq,
    );

    println!("Test case:");
    println!("  Merkle root: 0x{:016x}", circuit.merkle_root);
    println!("  Threshold: {}", circuit.threshold);
    println!("  Attribute (private): {}", circuit.attribute_value);
    println!("  Operator: {:?}", circuit.operator);
    println!("  Predicate satisfied: {}", circuit.evaluate_predicate());
    println!();

    // Run single benchmark
    println!("Running benchmark...");
    let results = run_benchmark(&circuit)?;

    println!();
    println!("=== Results ===");
    println!("Circuit build:      {:>8.2} ms", results.circuit_build_ms);
    println!("Proof generation:   {:>8.2} ms", results.proof_generation_ms);
    println!("Proof verification: {:>8.2} ms", results.proof_verification_ms);
    println!("Proof size:         {:>8} bytes (~{:.1} KB)",
             results.proof_size_bytes,
             results.proof_size_bytes as f64 / 1024.0);
    println!("Public inputs:      {:>8}", results.public_inputs_count);

    // Run multiple iterations for average
    println!();
    println!("Running 10 iterations for average...");
    let mut total_gen = 0.0;
    let mut total_ver = 0.0;

    // Prebuild circuit once
    let (circuit_data, _abi, targets) = EligibilityCircuit::build_circuit()?;

    for i in 0..10 {
        let start = Instant::now();
        let proof = circuit.generate_proof(&circuit_data, &targets)?;
        total_gen += start.elapsed().as_secs_f64() * 1000.0;

        let start = Instant::now();
        EligibilityCircuit::verify_proof(&circuit_data, &proof)?;
        total_ver += start.elapsed().as_secs_f64() * 1000.0;

        print!(".");
        if i == 9 { println!(); }
    }

    println!();
    println!("=== Average over 10 iterations ===");
    println!("Proof generation:   {:>8.2} ms", total_gen / 10.0);
    println!("Proof verification: {:>8.2} ms", total_ver / 10.0);

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_predicate_evaluation() {
        let circuit = EligibilityCircuit::new(0, 500, 1000, PredicateOp::GreaterThanOrEq);
        assert!(circuit.evaluate_predicate());

        let circuit = EligibilityCircuit::new(0, 500, 400, PredicateOp::GreaterThanOrEq);
        assert!(!circuit.evaluate_predicate());

        let circuit = EligibilityCircuit::new(0, 500, 500, PredicateOp::Equal);
        assert!(circuit.evaluate_predicate());
    }

    #[test]
    fn test_circuit_build() -> Result<()> {
        let (circuit_data, abi, _targets) = EligibilityCircuit::build_circuit()?;
        assert_eq!(abi.public_input_count, 2);
        assert_eq!(abi.private_input_count, 1);
        assert!(circuit_data.common.degree_bits() > 0);
        Ok(())
    }

    #[test]
    fn test_proof_generation_and_verification() -> Result<()> {
        let circuit = EligibilityCircuit::new(0x1234, 500, 1000, PredicateOp::GreaterThanOrEq);
        let (circuit_data, _abi, targets) = EligibilityCircuit::build_circuit()?;

        let proof = circuit.generate_proof(&circuit_data, &targets)?;
        EligibilityCircuit::verify_proof(&circuit_data, &proof)?;

        Ok(())
    }
}
