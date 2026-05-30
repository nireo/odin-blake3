package main

import "core:fmt"
import "core:time"
import "core:crypto/blake2b"
import "core:crypto/blake2s"
import blake3 "../"

SAMPLE_COUNT :: 7
TARGET_SAMPLE_TIME :: 20 * time.Millisecond

Algorithm :: enum {
	BLAKE3,
	BLAKE2s,
	BLAKE2b,
}

Benchmark_Result :: struct {
	min:    time.Duration,
	median: time.Duration,
}

digest_sink: byte

benchmark_blake3 :: proc(data: []byte, iterations: int) -> time.Duration {
	hasher: blake3.Hasher
	start := time.now()
	for i := 0; i < iterations; i += 1 {
		blake3.init(&hasher)
		blake3.update(&hasher, data)
		out: [32]byte
		blake3.finalize(&hasher, out[:])
		digest_sink ~= out[0]
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
		digest_sink ~= out[0]
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
		digest_sink ~= out[0]
	}
	end := time.now()
	return time.diff(start, end)
}

benchmark_once :: proc(algo: Algorithm, data: []byte, iterations: int) -> time.Duration {
	switch algo {
	case .BLAKE3:
		return benchmark_blake3(data, iterations)
	case .BLAKE2s:
		return benchmark_blake2s(data, iterations)
	case .BLAKE2b:
		return benchmark_blake2b(data, iterations)
	}
	return 0
}

sort_durations :: proc(samples: ^[SAMPLE_COUNT]time.Duration) {
	for i := 1; i < SAMPLE_COUNT; i += 1 {
		value := samples[i]
		j := i
		for j > 0 && samples[j - 1] > value {
			samples[j] = samples[j - 1]
			j -= 1
		}
		samples[j] = value
	}
}

calibrate_iterations :: proc(data: []byte) -> int {
	iterations := 1
	for {
		elapsed := benchmark_once(.BLAKE3, data, iterations)
		if elapsed >= TARGET_SAMPLE_TIME || iterations >= 1 << 28 {
			return iterations
		}

		multiplier := 2
		if elapsed > 0 {
			multiplier = int(f64(TARGET_SAMPLE_TIME) / f64(elapsed))
			if multiplier < 2 {
				multiplier = 2
			} else if multiplier > 16 {
				multiplier = 16
			}
		}
		iterations *= multiplier
	}
}

benchmark_robust :: proc(algo: Algorithm, data: []byte, iterations: int) -> Benchmark_Result {
	benchmark_once(algo, data, 1)
	benchmark_once(algo, data, iterations)

	samples: [SAMPLE_COUNT]time.Duration
	for i := 0; i < SAMPLE_COUNT; i += 1 {
		samples[i] = benchmark_once(algo, data, iterations)
	}
	sort_durations(&samples)

	return Benchmark_Result{min = samples[0], median = samples[SAMPLE_COUNT / 2]}
}

per_hash :: proc(duration: time.Duration, iterations: int) -> time.Duration {
	return time.Duration(i64(duration) / i64(iterations))
}

main :: proc() {
	sizes := []int{64, 1024, 10240, 102400, 1048576}

	fmt.println("BLAKE3 vs BLAKE2 Benchmark")
	fmt.println("==========================")
	fmt.printf("Samples: %d, target sample time: %s\n", SAMPLE_COUNT, TARGET_SAMPLE_TIME)
	fmt.printf("%10s | %10s | %12s | %12s | %12s | %12s | %8s | %8s\n",
		"Size", "Iters", "B3 median", "B3 min", "B2s median", "B2b median", "B2s/B3", "B2b/B3")
	fmt.println("-----------|------------|--------------|--------------|--------------|--------------|----------|---------")

	for size in sizes {
		data := make([]byte, size)
		for i := 0; i < size; i += 1 {
			data[i] = byte(i % 251)
		}

		iter := calibrate_iterations(data)

		b3 := benchmark_robust(.BLAKE3, data, iter)
		b2s := benchmark_robust(.BLAKE2s, data, iter)
		b2b := benchmark_robust(.BLAKE2b, data, iter)

		b3_median := per_hash(b3.median, iter)
		b3_min := per_hash(b3.min, iter)
		b2s_median := per_hash(b2s.median, iter)
		b2b_median := per_hash(b2b.median, iter)
		b2s_ratio := f64(b2s_median) / f64(b3_median)
		b2b_ratio := f64(b2b_median) / f64(b3_median)

		fmt.printf("%10d B | %10d | %12s | %12s | %12s | %12s | %.2fx | %.2fx\n",
			size, iter, b3_median, b3_min, b2s_median, b2b_median, b2s_ratio, b2b_ratio)

		delete(data)
	}
}
