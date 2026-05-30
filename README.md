# blake_odin

This repository contains a BLAKE3 implementation written in Odin. The implementation is portable for now and does not use SIMD-specific code paths, which keeps it close to Odin stdlib-style portability while still aiming to be fast in scalar code. The package supports normal hashing, keyed hashing, key derivation, and extendable output, and it is checked against the upstream BLAKE3 test vectors included in this repository.

## Usage

Run the test vectors with `make test` or `make test-speed`. Run the benchmark with `make bench`. The benchmark compares this BLAKE3 implementation against Odin's stdlib BLAKE2s and BLAKE2b implementations.

## Benchmarks

These results are from `make bench`, which runs `odin run benchmark -o:speed`. The speedup column is BLAKE2s time divided by BLAKE3 time.

| Size | Iterations | BLAKE3 | BLAKE2s | BLAKE2b | Speedup vs BLAKE2s |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 64 B | 10000 | 137us | 1.886ms | 1.953ms | 13.77x |
| 1 KiB | 1000 | 1.811ms | 2.518ms | 1.424ms | 1.39x |
| 10 KiB | 100 | 1.540ms | 2.018ms | 1.410ms | 1.31x |
| 100 KiB | 10 | 1.516ms | 2.044ms | 946us | 1.35x |
| 1 MiB | 1 | 965us | 1.317ms | 765us | 1.36x |

BLAKE3 is consistently faster than BLAKE2s in this benchmark, with a very large win for tiny inputs and a steadier advantage on larger buffers. BLAKE2b is still faster for several larger sizes on this machine, which is not surprising for a scalar-only BLAKE3 implementation because BLAKE3 normally gets much of its throughput advantage from SIMD and tree parallelism.
