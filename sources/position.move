module v3_core_move::position;

use v3_core_move::full_math_u128;
use v3_core_move::i128::{Self, I128};
use v3_core_move::i32::{Self, I32};
use v3_core_move::tick_math;

#[error]
const E_LIQUIDITY_GT_ZERO: vector<u8> = b"Liquidity must be greater than 0";

public struct Position<phantom CoinA, phantom CoinB> has key, store {
    id: UID,
    pool: ID,
    tick_lower: I32,
    tick_upper: I32,
    liquidity: u128,
    fee_growth_inside0: u128,
    fee_growth_inside1: u128,
    tokens_owed0: u64,
    tokens_owed1: u64,
}

public(package) fun new<CoinA, CoinB>(
    pool_id: ID,
    tick_spacing: I32,
    tick_lower: I32,
    tick_upper: I32,
    ctx: &mut TxContext,
): Position<CoinA, CoinB> {
    check_position_tick_range(tick_lower, tick_upper, tick_spacing);

    Position<CoinA, CoinB> {
        id: object::new(ctx),
        pool: pool_id,
        tick_lower: tick_lower,
        tick_upper: tick_upper,
        liquidity: 0,
        fee_growth_inside0: 0,
        fee_growth_inside1: 0,
        tokens_owed0: 0,
        tokens_owed1: 0,
    }
}

public(package) fun update<CoinA, CoinB>(
    self: &mut Position<CoinA, CoinB>,
    liquidity: I128,
    fee_growth_inside0: u128,
    fee_growth_inside1: u128,
) {
    let liquidity_next = if (liquidity == i128::zero()) {
        // 不允许对0流动性仓位进行poke操作
        assert!(self.liquidity > 0, E_LIQUIDITY_GT_ZERO);
        self.liquidity
    } else {
        let result = liquidity.add(i128::from(self.liquidity));
        // 不能为负数
        assert!(!result.is_neg(), E_LIQUIDITY_GT_ZERO);
        result.abs_u128()
    };

    let tokensOwed0 =
        full_math_u128::mul_div_floor(
            fee_growth_inside0 - self.fee_growth_inside0,
            self.liquidity,
            1<<64,
        ) as u64;

    let tokensOwed1 =
        full_math_u128::mul_div_floor(
            fee_growth_inside1 - self.fee_growth_inside1,
            self.liquidity,
            1<<64,
        ) as u64;

    if (!liquidity.eq(i128::zero())) {
        self.liquidity = liquidity_next;
    };
    self.fee_growth_inside0 = fee_growth_inside0;
    self.fee_growth_inside1 = fee_growth_inside1;
    if (tokensOwed0 > 0 || tokensOwed1 > 0) {
        self.tokens_owed0 = self.tokens_owed0 + tokensOwed0;
        self.tokens_owed1 = self.tokens_owed1 + tokensOwed1;
    };
}

public(package) fun reset_fee<CoinA, CoinB>(self: &mut Position<CoinA, CoinB>): (u64, u64) {
    let (tokensOwed0, tokensOwed1) = (self.tokens_owed0, self.tokens_owed1);
    self.tokens_owed0 = 0;
    self.tokens_owed1 = 0;
    (tokensOwed0, tokensOwed1)
}

public fun pool_id<CoinA, CoinB>(self: &Position<CoinA, CoinB>): ID {
    self.pool
}

public fun liquidity<CoinA, CoinB>(self: &Position<CoinA, CoinB>): u128 {
    self.liquidity
}

public fun tick_range<CoinA, CoinB>(self: &Position<CoinA, CoinB>): (I32, I32) {
    (self.tick_lower, self.tick_upper)
}

public fun fee<CoinA, CoinB>(self: &Position<CoinA, CoinB>): (u64, u64) {
    (self.tokens_owed0, self.tokens_owed1)
}

public(package) fun destroy<CoinA, CoinB>(self: Position<CoinA, CoinB>) {
    let Position {
        id,
        pool: _,
        tick_lower: _,
        tick_upper: _,
        liquidity: _,
        fee_growth_inside0: _,
        fee_growth_inside1: _,
        tokens_owed0: _,
        tokens_owed1: _,
    } = self;
    object::delete(id);
}

public fun check_position_tick_range(tick_lower: I32, tick_upper: I32, tick_spacing: I32) {
    assert!(
        tick_lower.lt(tick_upper) && 
        tick_lower.gte(tick_math::min_tick()) && 
        tick_upper.lte(tick_math::max_tick()) && 
        tick_lower.mod(tick_spacing) == i32::zero() &&
        tick_upper.mod(tick_spacing) == i32::zero(),
        0,
    );
}
