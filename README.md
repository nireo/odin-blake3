# blake_odin

This repository contains a BLAKE3 implementation written in Odin. The implementation has a portable scalar path and a macOS arm64 SIMD path for hashing four chunks or parent nodes at a time, following the shape of the upstream NEON implementation. Single-block compression and XOF output still use the portable code path. The package supports normal hashing, keyed hashing, key derivation, and extendable output, and it is checked against the upstream BLAKE3 test vectors included in this repository.

## Usage

Run the test vectors with `make test` or `make test-speed`. Run the benchmark with `make bench`. The benchmark compares this BLAKE3 implementation against Odin's stdlib BLAKE2s and BLAKE2b implementations.

Import the package and use `Hasher` for the same places you would normally use a BLAKE2 context:

```odin
import blake3 "path/to/blake_odin"

message := "hello from BLAKE3"

hasher: blake3.Hasher
out: [blake3.OUT_LEN]byte

blake3.init(&hasher)
blake3.update(&hasher, transmute([]byte)message)
blake3.finalize(&hasher, out[:])
```

### Replacing BLAKE2s/BLAKE2b hashing

BLAKE3's default output length is 32 bytes, which is the usual replacement for a 256-bit BLAKE2s digest. If you need a 64-byte digest, use a larger output buffer; BLAKE3 is an extendable-output function.

```odin
data := transmute([]byte)"hash this payload"

hasher: blake3.Hasher
digest_32: [32]byte
digest_64: [64]byte

blake3.init(&hasher)
blake3.update(&hasher, data)
blake3.finalize(&hasher, digest_32[:])

blake3.init(&hasher)
blake3.update(&hasher, data)
blake3.finalize(&hasher, digest_64[:])
```

### Streaming Input

Call `update` repeatedly for file or network data, then `finalize` once at the end.

```odin
hasher: blake3.Hasher
digest: [blake3.OUT_LEN]byte

blake3.init(&hasher)
blake3.update(&hasher, chunk_a)
blake3.update(&hasher, chunk_b)
blake3.update(&hasher, chunk_c)
blake3.finalize(&hasher, digest[:])
```

### Keyed Hashing / MACs

Use keyed mode where you would use keyed BLAKE2 for a MAC. BLAKE3 keys are always 32 bytes.

```odin
key: [blake3.KEY_LEN]byte
copy(key[:], "0123456789abcdef0123456789abcdef")

hasher: blake3.Hasher
mac: [blake3.OUT_LEN]byte

blake3.init_keyed(&hasher, key)
blake3.update(&hasher, transmute([]byte)"authenticated message")
blake3.finalize(&hasher, mac[:])
```

### Key Derivation

Use `init_derive_key` with a stable, application-specific context string, then hash the input key material.

```odin
context :: "example.com 2026-06-05 session key v1"
input_key_material := transmute([]byte)"shared secret or master key"

hasher: blake3.Hasher
derived_key: [32]byte

blake3.init_derive_key(&hasher, context)
blake3.update(&hasher, input_key_material)
blake3.finalize(&hasher, derived_key[:])
```

### Extendable Output

For XOF-style output, pass any output length to `finalize`. Use `finalize_seek` to read a later section of the same output stream.

```odin
hasher: blake3.Hasher
first_128: [128]byte
next_64: [64]byte

blake3.init(&hasher)
blake3.update(&hasher, transmute([]byte)"expand this input")
blake3.finalize(&hasher, first_128[:])
blake3.finalize_seek(&hasher, 128, next_64[:])
```

## Benchmarks

These results are from `make bench`, which runs `odin run benchmark -o:speed`. The benchmark warms each implementation, calibrates the iteration count per input size to target about 20ms per sample, takes seven samples, and reports median time per hash. The speedup columns are the BLAKE2 median time divided by the BLAKE3 median time.

| Size | Iterations | BLAKE3 median | BLAKE3 min | BLAKE2s median | BLAKE2b median | BLAKE2s/BLAKE3 | BLAKE2b/BLAKE3 |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 64 B | 262144 | 47ns | 46ns | 65ns | 83ns | 1.38x | 1.77x |
| 1 KiB | 49152 | 719ns | 716ns | 1.000us | 601ns | 1.39x | 0.84x |
| 10 KiB | 7168 | 5.186us | 5.172us | 9.969us | 5.963us | 1.92x | 1.15x |
| 100 KiB | 512 | 45.417us | 45.185us | 99.761us | 59.677us | 2.20x | 1.31x |
| 1 MiB | 64 | 462.421us | 461.000us | 1.020ms | 610.906us | 2.21x | 1.32x |

BLAKE3 is consistently faster than BLAKE2s in this benchmark, with a very large win for tiny inputs and a stronger advantage once the input is large enough to use the four-way SIMD chunk and parent hashing path. BLAKE2b is still competitive on the smallest and 1 KiB cases, but the macOS arm64 SIMD path moves the larger BLAKE3 cases ahead in this run. Benchmark timings are noisy, so the exact numbers should be treated as a local snapshot rather than a universal result.
