# blake_odin

This repository contains a BLAKE3 implementation written in Odin. The implementation has a portable scalar path and a macOS arm64 SIMD path for hashing four chunks or parent nodes at a time, following the shape of the upstream NEON implementation. Single-block compression and XOF output still use the portable code path. The package supports normal hashing, keyed hashing, key derivation, and extendable output, and it is checked against the upstream BLAKE3 test vectors included in this repository.

## Usage

Run the test vectors with `make test` or `make test-speed`. Run the benchmark with `make bench`. The benchmark compares this BLAKE3 implementation against Odin's stdlib BLAKE2s and BLAKE2b implementations.

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
