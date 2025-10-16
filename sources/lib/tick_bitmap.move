module v3_core_move::tick_bitmap;

use std::u128;
use sui::dynamic_field as df;
use v3_core_move::bit_math;
use v3_core_move::i32::{Self, I32};

public struct TickBitmap has key, store {
    id: UID,
    tick_spacing: I32,
}

public(package) fun new(tick_spacing: I32, ctx: &mut TxContext): TickBitmap {
    TickBitmap {
        id: object::new(ctx),
        tick_spacing,
    }
}

public fun position(tick: I32): (u32, u8) {
    // bit_pos在uniswap中是%,然后强制转换为uint8时，(正数的原码和补码相同)
    // 如果tick为负数,则会取bit_pos的补码来表示
    // 同样，i32也是存储的补码格式，当tick为负数时，结果和uniswap的一致

    // 字位置： tick右移7位，每个127tick共享一个字
    let word_pos: u32 = tick.shr(7).as_u32();
    // 这里和uniswap的实现差不多，只是这里采用&的方式来保留低7位的方式
    let bit_pos: u8 = (tick.as_u32() & 0x7F) as u8;

    (word_pos, bit_pos)
}

public fun flip_tick(self: &mut TickBitmap, tick: I32) {
    assert!(tick.mod(self.tick_spacing).as_u32() == 0, 0);
    let (word_pos, bit_pos) = position(tick.div(self.tick_spacing));

    let mask: u128 = 1 << bit_pos;

    if (!self.contains(word_pos)) {
        self.add(word_pos, 0);
    };

    *&mut self[word_pos] = self[word_pos] ^ mask;
}

public fun next_initialized_tick_with_in_one_word(
    self: &mut TickBitmap,
    tick: I32,
    lte: bool,
): (I32, bool) {
    let mut compressed = tick.div(self.tick_spacing);

    if (tick.lt(i32::from(0)) && !tick.mod(self.tick_spacing).eq(i32::from(0))) {
        compressed = compressed.sub(i32::from(1));
    };

    if (lte) {
        let (word_pos, bit_pos) = position(compressed);

        let word = if (!self.contains(word_pos)) {
            0
        } else {
            self[word_pos]
        };

        let mask = (1<<bit_pos) - 1 + (1 << bit_pos);
        let masked = word & mask;
        let initialized = masked != 0;

        let next = if (initialized) {
            let msbit = i32::from(bit_math::most_significant_bit(masked) as u32);
            compressed.add(msbit).sub(i32::from(bit_pos as u32)).mul(self.tick_spacing)
        } else {
            compressed.sub(i32::from(bit_pos as u32)).mul(self.tick_spacing)
        };
        (next, initialized)
    } else {
        let (word_pos, bit_pos) = position(compressed.add(i32::from(1)));
        let word = if (!self.contains(word_pos)) {
            0
        } else {
            self[word_pos]
        };
        // 这里通过异或全1来完成按位取反的逻辑
        let mask = u128::max_value!() ^ ((1<<bit_pos) - 1);
        let masked = word & mask;
        let initialized = masked != 0;

        let next = if (initialized) {
            let lsbit = i32::from(bit_math::least_significant_bit(masked) as u32);
            compressed
                .add(i32::from(1))
                .add(lsbit.sub(i32::from(bit_pos as u32)))
                .mul(self.tick_spacing)
        } else {
            // 这里为什么是127
            // 因为bit_pos是7位，所以Max = uint7.max = 0x7f
            let tmp = i32::from(127).sub(i32::from(bit_pos as u32));
            compressed.add(i32::from(1)).add(tmp).mul(self.tick_spacing)
        };
        (next, initialized)
    }
}

#[syntax(index)]
public fun borrow_mut(self: &mut TickBitmap, k: u32): &mut u128 {
    df::borrow_mut(&mut self.id, k)
}

#[syntax(index)]
public fun borrow(self: &TickBitmap, k: u32): &u128 {
    df::borrow(&self.id, k)
}

public fun add(self: &mut TickBitmap, k: u32, v: u128) {
    df::add(&mut self.id, k, v);
}

public fun remove(self: &mut TickBitmap, k: u32): u128 {
    df::remove(&mut self.id, k)
}

public fun contains(self: &TickBitmap, k: u32): bool {
    df::exists_with_type<u32, u128>(&self.id, k)
}

#[test_only]
fun is_initialized(self: &mut TickBitmap, tick: I32): bool {
    let (next, initialized) = self.next_initialized_tick_with_in_one_word(tick, true);
    if (next == tick) {
        initialized
    } else {
        false
    }
}

#[test]
fun test_initialized() {
    use sui::test_scenario;
    let sender: address = @0x1;

    let mut ts = test_scenario::begin(sender);
    {
        let mut tick_bitmap = new(i32::from(1), ts.ctx());

        tick_bitmap.flip_tick(i32::neg_from(115));

        assert!(tick_bitmap.is_initialized(i32::neg_from(115)), 0);
        assert!(!tick_bitmap.is_initialized(i32::neg_from(116)), 0);
        assert!(!tick_bitmap.is_initialized(i32::neg_from(114)), 0);

        assert!(!tick_bitmap.is_initialized(i32::neg_from(115).add(i32::from(128))), 0);
        assert!(!tick_bitmap.is_initialized(i32::neg_from(115).sub(i32::neg_from(128))), 0);

        tick_bitmap.flip_tick(i32::neg_from(115));
        assert!(!tick_bitmap.is_initialized(i32::neg_from(115)), 0);
        assert!(!tick_bitmap.is_initialized(i32::neg_from(116)), 0);
        assert!(!tick_bitmap.is_initialized(i32::neg_from(114)), 0);
        assert!(!tick_bitmap.is_initialized(i32::neg_from(115).add(i32::from(128))), 0);
        assert!(!tick_bitmap.is_initialized(i32::neg_from(115).sub(i32::neg_from(128))), 0);

        transfer::transfer(tick_bitmap, sender);
    };
    ts.end();
}

#[test]
fun test_next_initialized_tick_with_in_one_word_at_lte_false() {
    use sui::test_scenario;
    let sender: address = @0x1;
    let initTicks: vector<I32> = vector[
        i32::neg_from(100),
        i32::neg_from(28),
        i32::neg_from(2),
        i32::from(35),
        i32::from(39),
        i32::from(42),
        i32::from(70),
        i32::from(120),
        i32::from(268),
    ];

    let mut ts = test_scenario::begin(sender);
    {
        let mut tick_bitmap = new(i32::from(1), ts.ctx());
        initTicks.do!(|tick| {
            tick_bitmap.flip_tick(tick);
        });

        let (next, initialized) = tick_bitmap.next_initialized_tick_with_in_one_word(
            i32::from(39),
            false,
        );
        assert!(next == i32::from(42), 0);
        assert!(initialized, 0);

        let (next, initialized) = tick_bitmap.next_initialized_tick_with_in_one_word(
            i32::neg_from(28),
            false,
        );
        assert!(next == i32::neg_from(2), 0);
        assert!(initialized, 0);

        let (next, initialized) = tick_bitmap.next_initialized_tick_with_in_one_word(
            i32::from(38),
            false,
        );
        assert!(next == i32::from(39), 0);
        assert!(initialized, 0);

        let (next, initialized) = tick_bitmap.next_initialized_tick_with_in_one_word(
            i32::neg_from(29),
            false,
        );
        assert!(next == i32::neg_from(28), 0);
        assert!(initialized, 0);

        let (next, initialized) = tick_bitmap.next_initialized_tick_with_in_one_word(
            i32::from(127),
            false,
        );
        assert!(next == i32::from(255), 0);
        assert!(!initialized, 0);

        let (next, initialized) = tick_bitmap.next_initialized_tick_with_in_one_word(
            i32::neg_from(129),
            false,
        );
        assert!(next == i32::neg_from(100), 0);
        assert!(initialized, 0);

        tick_bitmap.flip_tick(i32::from(170));
        let (next, initialized) = tick_bitmap.next_initialized_tick_with_in_one_word(
            i32::from(164),
            false,
        );
        assert!(next == i32::from(170), 0);
        assert!(initialized, 0);
        tick_bitmap.flip_tick(i32::from(170));

        let (next, initialized) = tick_bitmap.next_initialized_tick_with_in_one_word(
            i32::from(254),
            false,
        );
        assert!(next == i32::from(255), 0);
        assert!(!initialized, 0);

        let (next, initialized) = tick_bitmap.next_initialized_tick_with_in_one_word(
            i32::from(127),
            false,
        );
        assert!(next == i32::from(255), 0);
        assert!(!initialized, 0);

        let (next, initialized) = tick_bitmap.next_initialized_tick_with_in_one_word(
            i32::from(192),
            false,
        );
        assert!(next == i32::from(255), 0);
        assert!(!initialized, 0);

        transfer::transfer(tick_bitmap, sender);
    };

    ts.end();
}

#[test]
fun test_next_initialized_tick_with_in_one_word_at_lte_true() {
    use sui::test_scenario;
    let sender: address = @0x1;
    let initTicks: vector<I32> = vector[
        i32::neg_from(100),
        i32::neg_from(28),
        i32::neg_from(2),
        i32::from(35),
        i32::from(39),
        i32::from(42),
        i32::from(70),
        i32::from(120),
        i32::from(268),
    ];

    let mut ts = test_scenario::begin(sender);
    {
        let mut tick_bitmap = new(i32::from(1), ts.ctx());
        initTicks.do!(|tick| {
            tick_bitmap.flip_tick(tick);
        });

        let (next, initialized) = tick_bitmap.next_initialized_tick_with_in_one_word(
            i32::from(39),
            true,
        );
        assert!(next == i32::from(39), 0);
        assert!(initialized, 0);

        let (next, initialized) = tick_bitmap.next_initialized_tick_with_in_one_word(
            i32::from(40),
            true,
        );
        assert!(next == i32::from(39), 0);
        assert!(initialized, 0);

        let (next, initialized) = tick_bitmap.next_initialized_tick_with_in_one_word(
            i32::from(129),
            true,
        );
        assert!(next == i32::from(128), 0);
        assert!(!initialized, 0);

        let (next, initialized) = tick_bitmap.next_initialized_tick_with_in_one_word(
            i32::from(128),
            true,
        );
        assert!(next == i32::from(128), 0);
        assert!(!initialized, 0);

        let (next, initialized) = tick_bitmap.next_initialized_tick_with_in_one_word(
            i32::from(36),
            true,
        );
        assert!(next == i32::from(35), 0);
        assert!(initialized, 0);

        let (next, initialized) = tick_bitmap.next_initialized_tick_with_in_one_word(
            i32::neg_from(129),
            true,
        );
        assert!(next == i32::neg_from(256), 0);
        assert!(!initialized, 0);

        let (next, initialized) = tick_bitmap.next_initialized_tick_with_in_one_word(
            i32::from(511),
            true,
        );
        assert!(next == i32::from(384), 0);
        assert!(!initialized, 0);

        let (next, initialized) = tick_bitmap.next_initialized_tick_with_in_one_word(
            i32::from(450),
            true,
        );
        assert!(next == i32::from(384), 0);
        assert!(!initialized, 0);

        tick_bitmap.flip_tick(i32::from(165));
        let (next, initialized) = tick_bitmap.next_initialized_tick_with_in_one_word(
            i32::from(228),
            true,
        );
        assert!(next == i32::from(165), 0);
        assert!(initialized, 0);
        tick_bitmap.flip_tick(i32::from(165));

        transfer::transfer(tick_bitmap, sender);
    };
    ts.end();
}
