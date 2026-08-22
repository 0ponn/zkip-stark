/*
 * Compatibility shim for ix's Rust FFI static lib (libix_ffi.a).
 *
 * ix's FFI (mimalloc) is cargo-built against the system glibc, whose C23
 * headers redirect `strtol` to the versioned `__isoc23_strtol@GLIBC_2.38`.
 * Lean's bundled (older) glibc used for the final link lacks that symbol, so
 * the executable link fails with `undefined symbol: __isoc23_strtol`.
 *
 * Provide it here, forwarding to plain `strtol` (present in every glibc).
 * This translation unit MUST be compiled with a pre-C23 standard
 * (see lakefile.lean: `-std=gnu11`) so our own `strtol` call is not itself
 * redirected back to `__isoc23_strtol`.
 */
#include <stdlib.h>

long __isoc23_strtol(const char *nptr, char **endptr, int base) {
  return strtol(nptr, endptr, base);
}
