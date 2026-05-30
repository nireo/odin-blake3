ODIN ?= odin
BUILD_DIR ?= .build
BENCH_OUT ?= $(BUILD_DIR)/blake_bench

.PHONY: help test test-speed bench bench-debug bench-build bench-run check clean

help:
	@printf "Common commands:\n"
	@printf "  make test         Run BLAKE3 test vectors\n"
	@printf "  make test-speed   Run test vectors optimized\n"
	@printf "  make bench        Run optimized benchmark\n"
	@printf "  make bench-debug  Run benchmark without -o:speed\n"
	@printf "  make bench-build  Build optimized benchmark to $(BENCH_OUT)\n"
	@printf "  make bench-run    Build and run optimized benchmark binary\n"
	@printf "  make check        Run test, test-speed, and bench\n"
	@printf "  make clean        Remove local build outputs\n"

test:
	$(ODIN) test .

test-speed:
	$(ODIN) test . -o:speed

bench:
	$(ODIN) run benchmark -o:speed

bench-debug:
	$(ODIN) run benchmark

bench-build:
	@mkdir -p "$(BUILD_DIR)"
	$(ODIN) build benchmark -o:speed -out:$(BENCH_OUT)

bench-run: bench-build
	$(BENCH_OUT)

check: test test-speed bench

clean:
	rm -rf "$(BUILD_DIR)"
