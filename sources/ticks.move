module v3_core_move::ticks;

use sui::table::{Self, Table};
use v3_core_move::i128::{Self, I128};
use v3_core_move::i32::I32;
use v3_core_move::liquidity_math;

public struct Ticks has store {
    ticks: Table<u32, Tick>,
}

public struct Tick has copy, drop, store {
    index: I32,
    liquidity_gross: u128,
    liquidity_net: I128,
    fee_growth_outside_0x64: u128,
    fee_growth_outside_1x64: u128,
    initialized: bool,
}

public(package) fun new(ctx: &mut TxContext): Ticks {
    Ticks {
        ticks: table::new(ctx),
    }
}

public fun get_fee_growth_inside(
    self: &Ticks,
    tick_current: I32,
    tick_lower: I32,
    tick_upper: I32,
    fee_growth_global_0x64: u128,
    fee_growth_global_1x64: u128,
): (u128, u128) {
    let tick_lower = self.get_tick_at_default(tick_lower);
    let tick_upper = self.get_tick_at_default(tick_upper);

    let (feeGrowThBelow0X64, feeGrowThBelow1X64) = if (tick_current.gt(tick_lower.index)) {
        (tick_lower.fee_growth_outside_0x64, tick_lower.fee_growth_outside_1x64)
    } else {
        (
            fee_growth_global_0x64 - tick_lower.fee_growth_outside_0x64,
            fee_growth_global_1x64 - tick_lower.fee_growth_outside_1x64,
        )
    };

    let (feeGrowthAbove0X64, feeGrowthAbove1X64) = if (tick_current.lt(tick_upper.index)) {
        (tick_upper.fee_growth_outside_0x64, tick_upper.fee_growth_outside_1x64)
    } else {
        (
            fee_growth_global_0x64 - tick_upper.fee_growth_outside_0x64,
            fee_growth_global_1x64 - tick_upper.fee_growth_outside_1x64,
        )
    };

    (
        fee_growth_global_0x64 - feeGrowThBelow0X64 - feeGrowthAbove0X64,
        fee_growth_global_1x64 - feeGrowThBelow1X64 - feeGrowthAbove1X64,
    )
}

public(package) fun update(
    self: &mut Ticks,
    current_tick: I32,
    tick_current: I32,
    liquidity_delta: I128,
    fee_growth_global_0x64: u128,
    fee_growth_global_1x64: u128,
    upper: bool,
): bool {
    let tick = self.get_tick_mut(current_tick);
    let liquidity_gross_before = tick.liquidity_gross;
    let liquidity_gross_after = liquidity_math::add_delta(liquidity_gross_before, liquidity_delta);
    let flipped = (liquidity_gross_after == 0) != (liquidity_gross_before == 0);

    if (liquidity_gross_before == 0) {
        if (tick.index.lt(tick_current)) {
            tick.fee_growth_outside_0x64 = fee_growth_global_0x64;
            tick.fee_growth_outside_1x64 = fee_growth_global_1x64;
        };
        tick.initialized = true;
    };

    tick.liquidity_gross = liquidity_gross_after;
    tick.liquidity_net = if (upper) {
        tick.liquidity_net.sub(liquidity_delta)
    } else {
        tick.liquidity_net.add(liquidity_delta)
    };

    flipped
}

public(package) fun cross(
    self: &mut Ticks,
    current_tick: I32,
    fee_growth_global_0x64: u128,
    fee_growth_global_1x64: u128,
): I128 {
    let tick = self.get_tick_mut(current_tick);
    tick.fee_growth_outside_0x64 = fee_growth_global_0x64 - tick.fee_growth_outside_0x64;
    tick.fee_growth_outside_1x64 = fee_growth_global_1x64 - tick.fee_growth_outside_1x64;

    tick.liquidity_net
}

public(package) fun clear(self: &mut Ticks, tick: I32) {
    self.ticks.remove(tick.as_u32());
}

fun get_tick_at_default(self: &Ticks, tick: I32): Tick {
    if (!self.ticks.contains(tick.as_u32())) {
        Tick {
            index: tick,
            liquidity_gross: 0,
            liquidity_net: i128::zero(),
            fee_growth_outside_0x64: 0,
            fee_growth_outside_1x64: 0,
            initialized: false,
        }
    } else {
        self.ticks[tick.as_u32()]
    }
}

fun get_tick_mut(self: &mut Ticks, tick: I32): &mut Tick {
    if (!self.ticks.contains(tick.as_u32())) {
        self
            .ticks
            .add(
                tick.as_u32(),
                Tick {
                    index: tick,
                    liquidity_gross: 0,
                    liquidity_net: i128::zero(),
                    fee_growth_outside_0x64: 0,
                    fee_growth_outside_1x64: 0,
                    initialized: false,
                },
            );
    };
    self.ticks.borrow_mut(tick.as_u32())
}
