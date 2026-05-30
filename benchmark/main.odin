package main

import "core:fmt"
import "core:time"
import "core:crypto/blake2b"
import "core:crypto/blake2s"
import blake3 "../"

benchmark_blake3 :: proc(data: []byte, iterations: int) -> time.Duration {
	hasher: blake3.Hasher
	start := time.now()
	for i := 0; i < iterations; i += 1 {
		blake3.init(&hasher)
		blake3.update(&hasher, data)
		out: [32]byte
		blake3.finalize(&hasher, out[:])
	}
	end := time.now()
	return time.diff(start, end)
}

benchmark_blake2s :: proc(data: []byte, iterations: int) -> time.Duration {
	ctx: blake2s.Context
	start := time.now()
	for i := 0; i < iterations; i += 1 {
		blake2s.init(&ctx, 32)
		blake2s.update(&ctx, data)
		out: [32]byte
		blake2s.final(&ctx, out[:])
	}
	end := time.now()
	return time.diff(start, end)
}

benchmark_blake2b :: proc(data: []byte, iterations: int) -> time.Duration {
	ctx: blake2b.Context
	start := time.now()
	for i := 0; i < iterations; i += 1 {
		blake2b.init(&ctx, 64)
		blake2b.update(&ctx, data)
		out: [64]byte
		blake2b.final(&ctx, out[:])
	}
	end := time.now()
	return time.diff(start, end)
}

main :: proc() {
	sizes := []int{64, 1024, 10240, 102400, 1048576}
	iterations := []int{10000, 1000, 100, 10, 1}

	fmt.println("BLAKE3 vs BLAKE2 Benchmark")
	fmt.println("==========================")
	fmt.printf("%10s | %8s | %10s | %10s | %10s | %s\n",
		"Size", "Iters", "BLAKE3", "BLAKE2s", "BLAKE2b", "Speedup")
	fmt.println("-----------|----------|------------|------------|------------|-------------")

	for size, idx in sizes {
		data := make([]byte, size)
		for i := 0; i < size; i += 1 {
			data[i] = byte(i % 251)
		}

		iter := iterations[idx]

		t3 := benchmark_blake3(data, iter)
		t2s := benchmark_blake2s(data, iter)
		t2b := benchmark_blake2b(data, iter)

		ratio := f64(t2s) / f64(t3)

		fmt.printf("%10d B | %8d iters | %10s | %10s | %10s | %.2fx faster\n",
			size, iter, t3, t2s, t2b, ratio)

		delete(data)
	}
}
