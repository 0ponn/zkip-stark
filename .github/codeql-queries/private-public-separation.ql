/**
 * @name Private data leak into public STARK inputs
 * @description Detects if private attribute values are used in public inputs
 * @kind problem
 * @id zkip/private-public-leak
 * @severity error
 * @precision high
 * @tags security
 * @cwe CWE-200
 */

// Note: This is a placeholder query for when CodeQL supports Lean 4
// Currently, CodeQL doesn't support Lean 4, so this query won't run
// When support is added, this query will detect:
// 1. Private attribute values being added to publicInputs arrays
// 2. Private data being concatenated with public data
// 3. Private values appearing in STARK proof public inputs

// Example pattern we want to detect:
// let privateAttribute := 100
// let publicInputs := #[merkleRoot, threshold]
// publicInputs.push privateAttribute  // SECURITY VIOLATION

// For now, this serves as documentation of what we want to detect

