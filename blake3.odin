package _blake3

import "base:intrinsics"
import "core:encoding/endian"

KEY_LEN   :: 32
OUT_LEN   :: 32
BLOCK_LEN :: 64
CHUNK_LEN :: 1024
MAX_DEPTH :: 54

SIMD_DEGREE      :: 1
SIMD_DEGREE_OR_2 :: 2

CHUNK_START         :: u8(1)
CHUNK_END           :: u8(2)
PARENT              :: u8(4)
ROOT                :: u8(8)
KEYED_HASH          :: u8(16)
DERIVE_KEY_CONTEXT  :: u8(32)
DERIVE_KEY_MATERIAL :: u8(64)

@(private, rodata)
IV := [8]u32{
	0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
	0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
}

@(private, rodata)
MSG_SCHEDULE := [7][16]u8{
	{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15},
	{2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8},
	{3, 4, 10, 12, 13, 2, 7, 14, 6, 5, 9, 0, 11, 15, 8, 1},
	{10, 7, 12, 9, 14, 3, 13, 15, 4, 0, 11, 2, 5, 8, 1, 6},
	{12, 13, 9, 11, 15, 10, 14, 8, 7, 2, 5, 3, 0, 1, 6, 4},
	{9, 14, 11, 5, 8, 12, 15, 1, 13, 3, 0, 10, 2, 6, 4, 7},
	{11, 15, 5, 0, 1, 9, 8, 6, 14, 10, 2, 12, 3, 4, 7, 13},
}

Chunk_State :: struct {
	cv:                [8]u32,
	chunk_counter:     u64,
	buf:               [BLOCK_LEN]byte,
	buf_len:           u8,
	blocks_compressed: u8,
	flags:             u8,
}

Output :: struct {
	input_cv:  [8]u32,
	counter:   u64,
	block:     [BLOCK_LEN]byte,
	block_len: u8,
	flags:     u8,
}

Hasher :: struct {
	key:          [8]u32,
	chunk:        Chunk_State,
	cv_stack_len: u8,
	cv_stack:     [(MAX_DEPTH + 1) * OUT_LEN]byte,
}

highest_one :: proc "contextless" (x: u64) -> uint {
	x := x
	c: uint = 0
	if x & 0xffffffff00000000 != 0 { x >>= 32; c += 32 }
	if x & 0x00000000ffff0000 != 0 { x >>= 16; c += 16 }
	if x & 0x000000000000ff00 != 0 { x >>=  8; c +=  8 }
	if x & 0x00000000000000f0 != 0 { x >>=  4; c +=  4 }
	if x & 0x000000000000000c != 0 { x >>=  2; c +=  2 }
	if x & 0x0000000000000002 != 0 {           c +=  1 }
	return c
}

popcnt :: proc "contextless" (x: u64) -> uint {
	x := x
	count: uint = 0
	for x != 0 {
		count += 1
		x &= x - 1
	}
	return count
}

round_down_to_power_of_2 :: proc "contextless" (x: u64) -> u64 {
	return u64(1) << highest_one(x | 1)
}

load_key_words :: proc "contextless" (key: []byte) -> (key_words: [8]u32) {
	for i := 0; i < 8; i += 1 {
		key_words[i] = endian.unchecked_get_u32le(key[i * 4:])
	}
	return
}

store_cv_words :: proc "contextless" (bytes_out: []byte, cv_words: ^[8]u32) {
	endian.unchecked_put_u32le(bytes_out[0 * 4:], cv_words[0])
	endian.unchecked_put_u32le(bytes_out[1 * 4:], cv_words[1])
	endian.unchecked_put_u32le(bytes_out[2 * 4:], cv_words[2])
	endian.unchecked_put_u32le(bytes_out[3 * 4:], cv_words[3])
	endian.unchecked_put_u32le(bytes_out[4 * 4:], cv_words[4])
	endian.unchecked_put_u32le(bytes_out[5 * 4:], cv_words[5])
	endian.unchecked_put_u32le(bytes_out[6 * 4:], cv_words[6])
	endian.unchecked_put_u32le(bytes_out[7 * 4:], cv_words[7])
}

g :: #force_inline proc "contextless" (state: ^[16]u32, a, b, c, d: int, x, y: u32) {
	state[a] = state[a] + state[b] + x
	state[d] ~= state[a]
	state[d] = state[d] << (32 - 16) | state[d] >> 16
	state[c] = state[c] + state[d]
	state[b] ~= state[c]
	state[b] = state[b] << (32 - 12) | state[b] >> 12
	state[a] = state[a] + state[b] + y
	state[d] ~= state[a]
	state[d] = state[d] << (32 - 8) | state[d] >> 8
	state[c] = state[c] + state[d]
	state[b] ~= state[c]
	state[b] = state[b] << (32 - 7) | state[b] >> 7
}

round_fn :: #force_inline proc "contextless" (state: ^[16]u32, msg: ^[16]u32, round: int) {
	s := MSG_SCHEDULE[round]
	g(state, 0, 4,  8, 12, msg[s[0]],  msg[s[1]])
	g(state, 1, 5,  9, 13, msg[s[2]],  msg[s[3]])
	g(state, 2, 6, 10, 14, msg[s[4]],  msg[s[5]])
	g(state, 3, 7, 11, 15, msg[s[6]],  msg[s[7]])
	g(state, 0, 5, 10, 15, msg[s[8]],  msg[s[9]])
	g(state, 1, 6, 11, 12, msg[s[10]], msg[s[11]])
	g(state, 2, 7,  8, 13, msg[s[12]], msg[s[13]])
	g(state, 3, 4,  9, 14, msg[s[14]], msg[s[15]])
}

compress_pre :: #force_inline proc "contextless" (state: ^[16]u32, cv: ^[8]u32, block: []byte, block_len: u8, counter: u64, flags: u8) {
	block_words: [16]u32 = ---
	block_words[0] = endian.unchecked_get_u32le(block[0 * 4:])
	block_words[1] = endian.unchecked_get_u32le(block[1 * 4:])
	block_words[2] = endian.unchecked_get_u32le(block[2 * 4:])
	block_words[3] = endian.unchecked_get_u32le(block[3 * 4:])
	block_words[4] = endian.unchecked_get_u32le(block[4 * 4:])
	block_words[5] = endian.unchecked_get_u32le(block[5 * 4:])
	block_words[6] = endian.unchecked_get_u32le(block[6 * 4:])
	block_words[7] = endian.unchecked_get_u32le(block[7 * 4:])
	block_words[8] = endian.unchecked_get_u32le(block[8 * 4:])
	block_words[9] = endian.unchecked_get_u32le(block[9 * 4:])
	block_words[10] = endian.unchecked_get_u32le(block[10 * 4:])
	block_words[11] = endian.unchecked_get_u32le(block[11 * 4:])
	block_words[12] = endian.unchecked_get_u32le(block[12 * 4:])
	block_words[13] = endian.unchecked_get_u32le(block[13 * 4:])
	block_words[14] = endian.unchecked_get_u32le(block[14 * 4:])
	block_words[15] = endian.unchecked_get_u32le(block[15 * 4:])

	state[0] = cv[0]
	state[1] = cv[1]
	state[2] = cv[2]
	state[3] = cv[3]
	state[4] = cv[4]
	state[5] = cv[5]
	state[6] = cv[6]
	state[7] = cv[7]
	state[8] = IV[0]
	state[9] = IV[1]
	state[10] = IV[2]
	state[11] = IV[3]
	state[12] = u32(counter)
	state[13] = u32(counter >> 32)
	state[14] = u32(block_len)
	state[15] = u32(flags)

	round_fn(state, &block_words, 0)
	round_fn(state, &block_words, 1)
	round_fn(state, &block_words, 2)
	round_fn(state, &block_words, 3)
	round_fn(state, &block_words, 4)
	round_fn(state, &block_words, 5)
	round_fn(state, &block_words, 6)
}

compress_in_place :: proc "contextless" (cv: ^[8]u32, block: []byte, block_len: u8, counter: u64, flags: u8) {
	state: [16]u32
	compress_pre(&state, cv, block, block_len, counter, flags)
	cv[0] = state[0] ~ state[8]
	cv[1] = state[1] ~ state[9]
	cv[2] = state[2] ~ state[10]
	cv[3] = state[3] ~ state[11]
	cv[4] = state[4] ~ state[12]
	cv[5] = state[5] ~ state[13]
	cv[6] = state[6] ~ state[14]
	cv[7] = state[7] ~ state[15]
}

compress_xof :: proc "contextless" (cv: ^[8]u32, block: []byte, block_len: u8, counter: u64, flags: u8, out: []byte) {
	state: [16]u32
	compress_pre(&state, cv, block, block_len, counter, flags)

	endian.unchecked_put_u32le(out[ 0*4:], state[0]  ~ state[8])
	endian.unchecked_put_u32le(out[ 1*4:], state[1]  ~ state[9])
	endian.unchecked_put_u32le(out[ 2*4:], state[2]  ~ state[10])
	endian.unchecked_put_u32le(out[ 3*4:], state[3]  ~ state[11])
	endian.unchecked_put_u32le(out[ 4*4:], state[4]  ~ state[12])
	endian.unchecked_put_u32le(out[ 5*4:], state[5]  ~ state[13])
	endian.unchecked_put_u32le(out[ 6*4:], state[6]  ~ state[14])
	endian.unchecked_put_u32le(out[ 7*4:], state[7]  ~ state[15])
	endian.unchecked_put_u32le(out[ 8*4:], state[8]  ~ cv[0])
	endian.unchecked_put_u32le(out[ 9*4:], state[9]  ~ cv[1])
	endian.unchecked_put_u32le(out[10*4:], state[10] ~ cv[2])
	endian.unchecked_put_u32le(out[11*4:], state[11] ~ cv[3])
	endian.unchecked_put_u32le(out[12*4:], state[12] ~ cv[4])
	endian.unchecked_put_u32le(out[13*4:], state[13] ~ cv[5])
	endian.unchecked_put_u32le(out[14*4:], state[14] ~ cv[6])
	endian.unchecked_put_u32le(out[15*4:], state[15] ~ cv[7])
}

compress_xof_32 :: proc "contextless" (cv: ^[8]u32, block: []byte, block_len: u8, counter: u64, flags: u8, out: []byte) {
	state: [16]u32
	compress_pre(&state, cv, block, block_len, counter, flags)

	endian.unchecked_put_u32le(out[0 * 4:], state[0] ~ state[8])
	endian.unchecked_put_u32le(out[1 * 4:], state[1] ~ state[9])
	endian.unchecked_put_u32le(out[2 * 4:], state[2] ~ state[10])
	endian.unchecked_put_u32le(out[3 * 4:], state[3] ~ state[11])
	endian.unchecked_put_u32le(out[4 * 4:], state[4] ~ state[12])
	endian.unchecked_put_u32le(out[5 * 4:], state[5] ~ state[13])
	endian.unchecked_put_u32le(out[6 * 4:], state[6] ~ state[14])
	endian.unchecked_put_u32le(out[7 * 4:], state[7] ~ state[15])
}

hash_one :: proc "contextless" (input: []byte, blocks: int, key: [8]u32, counter: u64, flags, flags_start, flags_end: u8, out: []byte) {
	cv := key
	block_flags := flags | flags_start
	input := input
	blocks := blocks
	for blocks > 1 {
		compress_in_place(&cv, input, BLOCK_LEN, counter, block_flags)
		input = input[BLOCK_LEN:]
		blocks -= 1
		block_flags = flags
	}
	compress_in_place(&cv, input, BLOCK_LEN, counter, block_flags | flags_end)
	store_cv_words(out, &cv)
}

chunk_state_init :: proc "contextless" (self: ^Chunk_State, key: [8]u32, flags: u8) {
	self.cv = key
	self.chunk_counter = 0
	self.buf_len = 0
	self.blocks_compressed = 0
	self.flags = flags
}

chunk_state_reset :: proc "contextless" (self: ^Chunk_State, key: [8]u32, chunk_counter: u64) {
	self.cv = key
	self.chunk_counter = chunk_counter
	self.blocks_compressed = 0
	self.buf_len = 0
}

chunk_state_len :: proc "contextless" (self: ^Chunk_State) -> int {
	return int(BLOCK_LEN) * int(self.blocks_compressed) + int(self.buf_len)
}

chunk_state_fill_buf :: proc "contextless" (self: ^Chunk_State, input: []byte) -> int {
	take := int(BLOCK_LEN) - int(self.buf_len)
	if take > len(input) {
		take = len(input)
	}
	copy(self.buf[int(self.buf_len):], input[:take])
	self.buf_len += u8(take)
	return take
}

chunk_state_maybe_start_flag :: proc "contextless" (self: ^Chunk_State) -> u8 {
	if self.blocks_compressed == 0 {
		return CHUNK_START
	}
	return 0
}

chunk_state_update :: proc "contextless" (self: ^Chunk_State, input: []byte) {
	input := input

	if self.buf_len > 0 {
		take := chunk_state_fill_buf(self, input)
		input = input[take:]
		if len(input) > 0 {
			compress_in_place(&self.cv, self.buf[:], BLOCK_LEN, self.chunk_counter,
				self.flags | chunk_state_maybe_start_flag(self))
			self.blocks_compressed += 1
			self.buf_len = 0
		}
	}

	for len(input) > BLOCK_LEN {
		compress_in_place(&self.cv, input, BLOCK_LEN, self.chunk_counter,
			self.flags | chunk_state_maybe_start_flag(self))
		self.blocks_compressed += 1
		input = input[BLOCK_LEN:]
	}

	chunk_state_fill_buf(self, input)
}

chunk_state_output :: proc "contextless" (self: ^Chunk_State) -> Output {
	block_flags := self.flags | chunk_state_maybe_start_flag(self) | CHUNK_END
	return make_output(self.cv, self.buf[:], self.buf_len, self.chunk_counter, block_flags)
}

make_output :: proc "contextless" (input_cv: [8]u32, block: []byte, block_len: u8, counter: u64, flags: u8) -> Output {
	ret: Output
	ret.input_cv = input_cv
	copy(ret.block[:int(block_len)], block[:int(block_len)])
	if block_len < BLOCK_LEN {
		intrinsics.mem_zero(&ret.block[int(block_len)], BLOCK_LEN - int(block_len))
	}
	ret.block_len = block_len
	ret.counter = counter
	ret.flags = flags
	return ret
}

chunk_state_chaining_value :: proc "contextless" (self: ^Chunk_State, cv: []byte) {
	cv_words := self.cv
	block_flags := self.flags | chunk_state_maybe_start_flag(self) | CHUNK_END
	if self.buf_len == BLOCK_LEN {
		compress_in_place(&cv_words, self.buf[:], self.buf_len, self.chunk_counter, block_flags)
	} else {
		block: [BLOCK_LEN]byte = ---
		copy(block[:int(self.buf_len)], self.buf[:int(self.buf_len)])
		if self.buf_len < BLOCK_LEN {
			intrinsics.mem_zero(&block[int(self.buf_len)], BLOCK_LEN - int(self.buf_len))
		}
		compress_in_place(&cv_words, block[:], self.buf_len, self.chunk_counter, block_flags)
	}
	store_cv_words(cv, &cv_words)
}

parent_chaining_value :: proc "contextless" (block: []byte, key: ^[8]u32, flags: u8, cv: []byte) {
	cv_words := key^
	compress_in_place(&cv_words, block, BLOCK_LEN, 0, flags | PARENT)
	store_cv_words(cv, &cv_words)
}

output_chaining_value :: proc "contextless" (self: ^Output, cv: []byte) {
	cv_words := self.input_cv
	compress_in_place(&cv_words, self.block[:], self.block_len, self.counter, self.flags)
	store_cv_words(cv, &cv_words)
}

output_root_bytes :: proc "contextless" (self: ^Output, seek: u64, out: []byte) {
	out_len := len(out)
	if out_len == 0 { return }
	if seek == 0 && out_len == OUT_LEN {
		compress_xof_32(&self.input_cv, self.block[:], self.block_len, 0, self.flags | ROOT, out)
		return
	}

	output_block_counter := seek / 64
	offset_within_block := int(seek % 64)

	out_pos := 0
	remaining := out_len

	wide_buf: [64]byte

	if offset_within_block != 0 {
		compress_xof(&self.input_cv, self.block[:], self.block_len, output_block_counter, self.flags | ROOT, wide_buf[:])
		available_bytes := 64 - offset_within_block
		bytes := remaining
		if bytes > available_bytes { bytes = available_bytes }
		copy(out[out_pos:], wide_buf[offset_within_block:offset_within_block + bytes])
		out_pos += bytes
		remaining -= bytes
		output_block_counter += 1
	}

	full_blocks := remaining / 64
	for i := 0; i < full_blocks; i += 1 {
		compress_xof(&self.input_cv, self.block[:], self.block_len, output_block_counter + u64(i), self.flags | ROOT, out[out_pos + i * 64:])
	}
	output_block_counter += u64(full_blocks)
	out_pos += full_blocks * 64
	remaining -= full_blocks * 64

	if remaining > 0 {
		compress_xof(&self.input_cv, self.block[:], self.block_len, output_block_counter, self.flags | ROOT, wide_buf[:])
		copy(out[out_pos:], wide_buf[:remaining])
	}
}

parent_output :: proc "contextless" (block: []byte, key: [8]u32, flags: u8) -> Output {
	return make_output(key, block, BLOCK_LEN, 0, flags | PARENT)
}

left_subtree_len :: proc "contextless" (input_len: int) -> int {
	full_chunks := u64((input_len - 1) / CHUNK_LEN)
	return int(round_down_to_power_of_2(full_chunks)) * CHUNK_LEN
}

compress_chunks_parallel :: proc "contextless" (input: []byte, key: [8]u32, chunk_counter: u64, flags: u8, out: []byte) -> int {
	input := input
	chunks_count := 0

	for len(input) >= CHUNK_LEN {
		hash_one(input, CHUNK_LEN / BLOCK_LEN, key, chunk_counter + u64(chunks_count), flags, CHUNK_START, CHUNK_END, out[chunks_count * OUT_LEN:])
		input = input[CHUNK_LEN:]
		chunks_count += 1
	}

	if len(input) > 0 {
		counter := chunk_counter + u64(chunks_count)
		cs: Chunk_State
		chunk_state_init(&cs, key, flags)
		cs.chunk_counter = counter
		chunk_state_update(&cs, input)
		chunk_state_chaining_value(&cs, out[chunks_count * OUT_LEN:])
		return chunks_count + 1
	}

	return chunks_count
}

compress_parents_parallel :: proc "contextless" (child_cvs: []byte, key: [8]u32, flags: u8, out: []byte) -> int {
	num_cvs := len(child_cvs) / OUT_LEN
	parents_count := 0

	for num_cvs - 2 * parents_count >= 2 {
		parent_block := child_cvs[2 * parents_count * OUT_LEN:]
		hash_one(parent_block, 1, key, 0, flags | PARENT, 0, 0, out[parents_count * OUT_LEN:])
		parents_count += 1
	}

	if num_cvs > 2 * parents_count {
		copy(out[parents_count * OUT_LEN:], child_cvs[2 * parents_count * OUT_LEN:])
		return parents_count + 1
	}

	return parents_count
}

compress_subtree_wide :: proc "contextless" (input: []byte, key: [8]u32, chunk_counter: u64, flags: u8, out: []byte) -> int {
	if len(input) <= SIMD_DEGREE * CHUNK_LEN {
		return compress_chunks_parallel(input, key, chunk_counter, flags, out)
	}

	left_len := left_subtree_len(len(input))
	right_len := len(input) - left_len
	right_chunk_counter := chunk_counter + u64(left_len / CHUNK_LEN)

	cv_array: [2 * SIMD_DEGREE_OR_2 * OUT_LEN]byte
	degree := SIMD_DEGREE
	if left_len > CHUNK_LEN && degree == 1 {
		degree = 2
	}
	right_cvs_offset := degree * OUT_LEN

	left_n := compress_subtree_wide(input[:left_len], key, chunk_counter, flags, cv_array[:])
	right_n := compress_subtree_wide(input[left_len:], key, right_chunk_counter, flags, cv_array[right_cvs_offset:])

	if left_n == 1 {
		copy(out, cv_array[:2 * OUT_LEN])
		return 2
	}

	num_cvs := left_n + right_n
	return compress_parents_parallel(cv_array[:num_cvs * OUT_LEN], key, flags, out)
}

compress_subtree_to_parent_node :: proc "contextless" (input: []byte, key: [8]u32, chunk_counter: u64, flags: u8, out: []byte) {
	compress_subtree_wide(input, key, chunk_counter, flags, out)
}

hasher_init_base :: proc "contextless" (self: ^Hasher, key: [8]u32, flags: u8) {
	self.key = key
	chunk_state_init(&self.chunk, key, flags)
	self.cv_stack_len = 0
}

init :: proc "contextless" (self: ^Hasher) {
	hasher_init_base(self, IV, 0)
}

init_keyed :: proc "contextless" (self: ^Hasher, key: [KEY_LEN]byte) {
	key_copy := key
	key_words := load_key_words(key_copy[:])
	hasher_init_base(self, key_words, KEYED_HASH)
}

init_derive_key_raw :: proc "contextless" (self: ^Hasher, ctx: []byte) {
	context_hasher: Hasher
	hasher_init_base(&context_hasher, IV, DERIVE_KEY_CONTEXT)
	update(&context_hasher, ctx)
	context_key: [KEY_LEN]byte
	finalize(&context_hasher, context_key[:])
	context_key_words := load_key_words(context_key[:])
	hasher_init_base(self, context_key_words, DERIVE_KEY_MATERIAL)
}

init_derive_key :: proc "contextless" (self: ^Hasher, ctx: string) {
	init_derive_key_raw(self, transmute([]byte)ctx)
}

hasher_merge_cv_stack :: proc "contextless" (self: ^Hasher, total_len: u64) {
	post_merge_stack_len := u8(popcnt(total_len))
	for self.cv_stack_len > post_merge_stack_len {
		parent_node := self.cv_stack[(int(self.cv_stack_len) - 2) * OUT_LEN:]
		parent_chaining_value(parent_node, &self.key, self.chunk.flags, parent_node)
		self.cv_stack_len -= 1
	}
}

hasher_push_cv :: proc "contextless" (self: ^Hasher, new_cv: []byte, chunk_counter: u64) {
	hasher_merge_cv_stack(self, chunk_counter)
	copy(self.cv_stack[int(self.cv_stack_len) * OUT_LEN:], new_cv)
	self.cv_stack_len += 1
}

update :: proc "contextless" (self: ^Hasher, input: []byte) {
	if len(input) == 0 { return }

	input := input

	if chunk_state_len(&self.chunk) > 0 {
		take := CHUNK_LEN - chunk_state_len(&self.chunk)
		if take > len(input) {
			take = len(input)
		}
		chunk_state_update(&self.chunk, input[:take])
		input = input[take:]
		if len(input) > 0 {
			chunk_cv: [OUT_LEN]byte
			chunk_state_chaining_value(&self.chunk, chunk_cv[:])
			hasher_push_cv(self, chunk_cv[:], self.chunk.chunk_counter)
			chunk_state_reset(&self.chunk, self.key, self.chunk.chunk_counter + 1)
		} else {
			return
		}
	}

	for len(input) > CHUNK_LEN {
		subtree_len := round_down_to_power_of_2(u64(len(input)))
		count_so_far := self.chunk.chunk_counter * u64(CHUNK_LEN)
		for ((subtree_len - 1) & count_so_far) != 0 {
			subtree_len /= 2
		}
		subtree_chunks := subtree_len / u64(CHUNK_LEN)
		if subtree_len <= u64(CHUNK_LEN) {
			cs: Chunk_State
			chunk_state_init(&cs, self.key, self.chunk.flags)
			cs.chunk_counter = self.chunk.chunk_counter
			chunk_state_update(&cs, input[:int(subtree_len)])
			cv: [OUT_LEN]byte
			chunk_state_chaining_value(&cs, cv[:])
			hasher_push_cv(self, cv[:], cs.chunk_counter)
		} else {
			cv_pair: [2 * OUT_LEN]byte
			compress_subtree_to_parent_node(input[:int(subtree_len)], self.key,
				self.chunk.chunk_counter, self.chunk.flags, cv_pair[:])
			hasher_push_cv(self, cv_pair[:], self.chunk.chunk_counter)
			hasher_push_cv(self, cv_pair[OUT_LEN:],
				self.chunk.chunk_counter + (subtree_chunks / 2))
		}
		self.chunk.chunk_counter += subtree_chunks
		input = input[int(subtree_len):]
	}

	if len(input) > 0 {
		chunk_state_update(&self.chunk, input)
		hasher_merge_cv_stack(self, self.chunk.chunk_counter)
	}
}

finalize :: proc "contextless" (self: ^Hasher, out: []byte) {
	finalize_seek(self, 0, out)
}

finalize_seek :: proc "contextless" (self: ^Hasher, seek: u64, out: []byte) {
	out_len := len(out)
	if out_len == 0 { return }

	if self.cv_stack_len == 0 {
		output := chunk_state_output(&self.chunk)
		output_root_bytes(&output, seek, out)
		return
	}

	output: Output
	cvs_remaining: int
	if chunk_state_len(&self.chunk) > 0 {
		cvs_remaining = int(self.cv_stack_len)
		output = chunk_state_output(&self.chunk)
	} else {
		cvs_remaining = int(self.cv_stack_len) - 2
		output = parent_output(self.cv_stack[cvs_remaining * OUT_LEN:], self.key, self.chunk.flags)
	}

	for cvs_remaining > 0 {
		cvs_remaining -= 1
		parent_block: [BLOCK_LEN]byte
		copy(parent_block[:OUT_LEN], self.cv_stack[cvs_remaining * OUT_LEN:])
		output_chaining_value(&output, parent_block[32:])
		output = parent_output(parent_block[:], self.key, self.chunk.flags)
	}

	output_root_bytes(&output, seek, out)
}

reset :: proc "contextless" (self: ^Hasher) {
	chunk_state_reset(&self.chunk, self.key, 0)
	self.cv_stack_len = 0
}
