module v3_core_move::pool;

use sui::balance::{Self, Balance};
use sui::event;
use v3_core_move::config::Config;
use v3_core_move::full_math_u128;
use v3_core_move::i128::{Self, I128};
use v3_core_move::i32::{Self, I32};
use v3_core_move::i64::{Self, I64};
use v3_core_move::liquidity_math;
use v3_core_move::position::{Self, Position};
use v3_core_move::sqrt_price_math;
use v3_core_move::swap_math;
use v3_core_move::tick_bitmap::{Self, TickBitmap};
use v3_core_move::tick_math;
use v3_core_move::ticks::{Self, Ticks};

// Errors

#[error]
const E_POOL_PAUSED: vector<u8> = b"Pool is paused";
#[error]
const E_POOL_ID_MISMATCH: vector<u8> = b"Pool id mismatch";
#[error]
const E_AMOUNT_INCORRECT: vector<u8> = b"Amount incorrect";
#[error]
const E_PROTOCOL_FEE_RATE_RANGE: vector<u8> = b"Protocol fee rate range error";
#[error]
const E_LIQUIDITY_NOT_ENOUGH: vector<u8> = b"Liquidity not enough";
#[error]
const E_FEE_NOT_ENOUGH: vector<u8> = b"Protocol fee not enough";
#[error]
const E_PRICE_SPAN_TOO_LARGE: vector<u8> = b"Price span too large";
#[error]
const E_LIQUIDITY_DATA_ERROR: vector<u8> = b"Liquidity data error";

public struct Pool<phantom CoinA, phantom CoinB> has key, store {
    id: UID,
    coin_a: Balance<CoinA>,
    coin_b: Balance<CoinB>,
    tick_spacing: I32,
    fee_rate: u64,
    // 变量
    current_tick: I32,
    sqrt_price: u128,
    // 高4位是b的协议费用，低4位是a的协议费用
    // 协议费用的比例是：4,5,6,7,8,9,10
    // 换算成分数就是 1/4，1/5，1/6，1/7，1/8，1/9，1/10
    fee_protocol: u8,
    fee_growth_global_a: u128,
    fee_growth_global_b: u128,
    protocol_fee_a: u64,
    protocol_fee_b: u64,
    liquidity: u128,
    ticks: Ticks,
    tick_bitmap: TickBitmap,
    is_pause: bool,
}

// Hot Potato

public struct AddLiquidityReceipt<phantom CoinA, phantom CoinB> {
    pool_id: ID,
    position_id: ID,
    amount_a: u64,
    amount_b: u64,
}

public struct SwapReceipt<phantom CoinA, phantom CoinB> {
    pool_id: ID,
    zero_for_one: bool,
    amount_a: u64,
    amount_b: u64,
}

// temp struct

public struct SwapCache has copy, drop {
    fee_protocol: u64,
    liquidity_start: u128,
}

public struct SwapState has copy, drop {
    amount_specified_remaining: I64,
    amount_calculated: I64,
    sqrt_price: u128,
    current_tick: I32,
    fee_growth_global: u128,
    protocol_fee: u64,
    liquidity: u128,
}

public struct StepComputations has copy, drop {
    sqrt_price_start: u128,
    tick_next: I32,
    initialized: bool,
    sqrt_price_next: u128,
    amount_in: u64,
    amount_out: u64,
    fee_amount: u64,
}

// Events

public struct OpenedPositionEvent has copy, drop {
    sender: address,
    pool_id: ID,
    position_id: ID,
    tick_lower: u32,
    tick_upper: u32,
}

public struct AddLiquidityEvent has copy, drop {
    sender: address,
    pool_id: ID,
    position_id: ID,
    tick_lower: u32,
    tick_upper: u32,
    liquidity: u128,
    amount_a: u64,
    amount_b: u64,
}

public struct RemoveLiquidityEvent has copy, drop {
    sender: address,
    pool_id: ID,
    position_id: ID,
    tick_lower: u32,
    tick_upper: u32,
    liquidity: u128,
    amount_a: u64,
    amount_b: u64,
}

public struct CollectFeeEvent has copy, drop {
    sender: address,
    pool_id: ID,
    position_id: ID,
    amount_a: u64,
    amount_b: u64,
}

public struct ClosePositionEvent has copy, drop {
    sender: address,
    pool_id: ID,
    position_id: ID,
}

public struct SwapEvent has copy, drop {
    sender: address,
    pool_id: ID,
    zero_for_one: bool,
    by_amount_in: bool,
    amount: u64,
    sqrt_price_limit: u128,
    sqrt_price_after: u128,
    amount_in: u64,
    amount_out: u64,
    sqrt_price_before: u128,
}

public(package) fun new<CoinA, CoinB>(
    sqrt_price: u128,
    tick_spacing: I32,
    fee_rate: u64,
    fee_protocol: u8,
    ctx: &mut TxContext,
): Pool<CoinA, CoinB> {
    assert!(sqrt_price > 0, 0);

    let tick = tick_math::get_tick_at_sqrt_ratio(sqrt_price);

    Pool {
        id: object::new(ctx),
        coin_a: balance::zero(),
        coin_b: balance::zero(),
        tick_spacing,
        fee_rate,
        current_tick: tick,
        sqrt_price,
        fee_protocol,
        fee_growth_global_a: 0,
        fee_growth_global_b: 0,
        protocol_fee_a: 0,
        protocol_fee_b: 0,
        liquidity: 0,
        ticks: ticks::new(ctx),
        tick_bitmap: tick_bitmap::new(tick_spacing, ctx),
        is_pause: false,
    }
}

public fun open_position<CoinA, CoinB>(
    self: &mut Pool<CoinA, CoinB>,
    config: &Config,
    tick_lower: u32,
    tick_upper: u32,
    ctx: &mut TxContext,
): Position<CoinA, CoinB> {
    config.check_package_version();
    assert!(!self.is_pause, E_POOL_PAUSED);

    let tick_lower = i32::from_u32(tick_lower);
    let tick_upper = i32::from_u32(tick_upper);

    let pool_id = object::id(self);

    let position = position::new(
        pool_id,
        self.tick_spacing,
        tick_lower,
        tick_upper,
        ctx,
    );
    let opened_position_event = OpenedPositionEvent {
        sender: ctx.sender(),
        pool_id,
        position_id: object::id(&position),
        tick_lower: tick_lower.as_u32(),
        tick_upper: tick_upper.as_u32(),
    };
    event::emit(opened_position_event);

    position
}

public fun add_liquidity<CoinA, CoinB>(
    self: &mut Pool<CoinA, CoinB>,
    config: &Config,
    position_nft: &mut Position<CoinA, CoinB>,
    liquidity: u128,
    ctx: &TxContext,
): AddLiquidityReceipt<CoinA, CoinB> {
    config.check_package_version();
    assert!(!self.is_pause, E_POOL_PAUSED);
    assert!(object::id(self) == position_nft.pool_id(), E_POOL_ID_MISMATCH);

    let liquidity_delta = i128::from(liquidity);
    let (amount_a, amount_b) = self.modify_position_internal(position_nft, liquidity_delta);
    let (tick_lower, tick_upper) = position_nft.tick_range();

    let add_liquidity_event = AddLiquidityEvent {
        sender: ctx.sender(),
        pool_id: position_nft.pool_id(),
        position_id: object::id(position_nft),
        tick_lower: tick_lower.as_u32(),
        tick_upper: tick_upper.as_u32(),
        liquidity,
        amount_a,
        amount_b,
    };
    event::emit(add_liquidity_event);
    (
        AddLiquidityReceipt {
            pool_id: position_nft.pool_id(),
            position_id: object::id(position_nft),
            amount_a,
            amount_b,
        },
    )
}

public fun repay_add_liquidity_receipt<CoinA, CoinB>(
    self: &mut Pool<CoinA, CoinB>,
    config: &Config,
    receipt: AddLiquidityReceipt<CoinA, CoinB>,
    balance_a: Balance<CoinA>,
    balance_b: Balance<CoinB>,
) {
    config.check_package_version();
    let AddLiquidityReceipt {
        pool_id,
        position_id: _position_id,
        amount_a,
        amount_b,
    } = receipt;
    assert!(pool_id == object::id(self), E_POOL_ID_MISMATCH);
    assert!(balance_a.value() == amount_a, E_AMOUNT_INCORRECT);
    assert!(balance_b.value() == amount_b, E_AMOUNT_INCORRECT);

    self.coin_a.join(balance_a);
    self.coin_b.join(balance_b);
}

public fun remove_liquidity<CoinA, CoinB>(
    self: &mut Pool<CoinA, CoinB>,
    config: &Config,
    position_nft: &mut Position<CoinA, CoinB>,
    liquidity: u128,
    ctx: &TxContext,
): (Balance<CoinA>, Balance<CoinB>) {
    config.check_package_version();
    assert!(!self.is_pause, E_POOL_PAUSED);
    let liquidity_delta = i128::neg_from(liquidity);
    let (amount_a, amount_b) = self.modify_position_internal(position_nft, liquidity_delta);
    let (tick_lower, tick_upper) = position_nft.tick_range();
    let remove_liquidity_event = RemoveLiquidityEvent {
        sender: ctx.sender(),
        pool_id: position_nft.pool_id(),
        position_id: object::id(position_nft),
        tick_lower: tick_lower.as_u32(),
        tick_upper: tick_upper.as_u32(),
        liquidity,
        amount_a,
        amount_b,
    };
    event::emit(remove_liquidity_event);
    (self.coin_a.split(amount_a), self.coin_b.split(amount_b))
}

public fun collect_fees<CoinA, CoinB>(
    self: &mut Pool<CoinA, CoinB>,
    config: &Config,
    position_nft: &mut Position<CoinA, CoinB>,
    ctx: &TxContext,
): (Balance<CoinA>, Balance<CoinB>) {
    config.check_package_version();
    assert!(!self.is_pause, E_POOL_PAUSED);

    if (position_nft.liquidity() > 0) {
        self.modify_position_internal(position_nft, i128::zero());
    };

    // 将手续费置空
    let (tokensOwed0, tokensOwed1) = position_nft.reset_fee();

    let collect_fee_event = CollectFeeEvent {
        sender: ctx.sender(),
        pool_id: position_nft.pool_id(),
        position_id: object::id(position_nft),
        amount_a: tokensOwed0,
        amount_b: tokensOwed1,
    };
    event::emit(collect_fee_event);

    (self.coin_a.split(tokensOwed0), self.coin_b.split(tokensOwed1))
}

public fun close_position<CoinA, CoinB>(
    self: &mut Pool<CoinA, CoinB>,
    config: &Config,
    position_nft: Position<CoinA, CoinB>,
    ctx: &TxContext,
) {
    config.check_package_version();
    assert!(object::id(self) == position_nft.pool_id(), E_POOL_ID_MISMATCH);
    let (tokensOwed0, tokensOwed1) = position_nft.fee();
    // 必须流动性为0
    assert!(position_nft.liquidity() == 0, E_LIQUIDITY_NOT_ENOUGH);
    // 同时手续费领取完毕
    assert!(tokensOwed0 == 0 && tokensOwed1 == 0, E_FEE_NOT_ENOUGH);

    let close_position_event = ClosePositionEvent {
        sender: ctx.sender(),
        pool_id: position_nft.pool_id(),
        position_id: object::id(&position_nft),
    };
    event::emit(close_position_event);

    position_nft.destroy();
}

/// swap
/// zero_for_one: true 表示输入CoinA，输出CoinB,false 表示输入CoinB，输出CoinA
/// by_amount_in 表示amount，true: 表示amount为输入金额，false: 表示amount为输出金额
/// amount: 根据by_amount_in决定
/// sqrt_price_limit:价格滑点控制
public fun swap<CoinA, CoinB>(
    self: &mut Pool<CoinA, CoinB>,
    config: &Config,
    zero_for_one: bool,
    by_amount_in: bool,
    amount: u64,
    sqrt_price_limit: u128,
    ctx: &TxContext,
): (Balance<CoinA>, Balance<CoinB>, SwapReceipt<CoinA, CoinB>) {
    config.check_package_version();
    assert!(amount > 0, 0);
    assert!(!self.is_pause, E_POOL_PAUSED);
    let sqrt_price_after = self.sqrt_price;

    let (balance_a, balance_b, receipt) = self.swap_internal(
        zero_for_one,
        by_amount_in,
        amount,
        sqrt_price_limit,
    );

    let sqrt_price_before = sqrt_price_after;

    let swap_event = SwapEvent {
        sender: ctx.sender(),
        pool_id: object::id(self),
        zero_for_one,
        by_amount_in,
        amount,
        sqrt_price_limit,
        sqrt_price_after,
        sqrt_price_before,
        amount_in: receipt.amount_a,
        amount_out: receipt.amount_b,
    };
    event::emit(swap_event);

    (balance_a, balance_b, receipt)
}

public fun repay_swap<CoinA, CoinB>(
    self: &mut Pool<CoinA, CoinB>,
    config: &Config,
    coin_a: Balance<CoinA>,
    coin_b: Balance<CoinB>,
    recipient: SwapReceipt<CoinA, CoinB>,
) {
    config.check_package_version();
    let SwapReceipt {
        pool_id,
        zero_for_one,
        amount_a,
        amount_b,
    } = recipient;

    assert!(pool_id == object::id(self), E_POOL_ID_MISMATCH);

    if (zero_for_one) {
        assert!(coin_a.value() == amount_a, E_AMOUNT_INCORRECT);
        self.coin_a.join(coin_a);
        coin_b.destroy_zero();
    } else {
        assert!(coin_b.value() == amount_b, E_AMOUNT_INCORRECT);
        self.coin_b.join(coin_b);
        coin_a.destroy_zero();
    };
}

public fun collect_protocol_fess<CoinA, CoinB>(
    self: &mut Pool<CoinA, CoinB>,
    config: &Config,
    ctx: &mut TxContext,
): (Balance<CoinA>, Balance<CoinB>) {
    config.check_package_version();
    config.check_acl_claim_protocol_fee_role(ctx.sender());
    // TODO add role check
    let fee_protocol_a = self.protocol_fee_a;
    let fee_protocol_b = self.protocol_fee_b;

    self.protocol_fee_a = 0;
    self.protocol_fee_b = 0;

    // TODO add event

    (self.coin_a.split(fee_protocol_a), self.coin_b.split(fee_protocol_b))
}

public fun set_protocol_fee_rate<CoinA, CoinB>(
    self: &mut Pool<CoinA, CoinB>,
    config: &Config,
    fee_protocol_rate0: u8,
    fee_protocol_rate1: u8,
    ctx: &mut TxContext,
) {
    config.check_package_version();
    config.check_acl_protocol_fee_rate_role(ctx.sender());
    assert!(
        (fee_protocol_rate0 == 0 || (fee_protocol_rate0 >= 4 && fee_protocol_rate0 <= 10)) &&
        (fee_protocol_rate1 == 0 || (fee_protocol_rate1 >= 4 && fee_protocol_rate1 <= 10)),
        E_PROTOCOL_FEE_RATE_RANGE,
    );
    self.fee_protocol = fee_protocol_rate0 + (fee_protocol_rate1 << 4);
}

public fun tick_spacing<CoinA, CoinB>(self: &Pool<CoinA, CoinB>): I32 {
    self.tick_spacing
}

public fun add_liquidity_receipt_amount_a<CoinA, CoinB>(
    receipt: &AddLiquidityReceipt<CoinA, CoinB>,
): u64 {
    receipt.amount_a
}

public fun add_liquidity_receipt_amount_b<CoinA, CoinB>(
    receipt: &AddLiquidityReceipt<CoinA, CoinB>,
): u64 {
    receipt.amount_b
}

/// 获取池子的当前流动性
public fun liquidity<CoinA, CoinB>(self: &Pool<CoinA, CoinB>): u128 {
    self.liquidity
}

/// 获取池子的当前tick
public fun current_tick<CoinA, CoinB>(self: &Pool<CoinA, CoinB>): I32 {
    self.current_tick
}

/// 获取池子的sqrt_price
public fun sqrt_price<CoinA, CoinB>(self: &Pool<CoinA, CoinB>): u128 {
    self.sqrt_price
}

public fun swap_receipt_amount_a<CoinA, CoinB>(receipt: &SwapReceipt<CoinA, CoinB>): u64 {
    receipt.amount_a
}

public fun swap_receipt_amount_b<CoinA, CoinB>(receipt: &SwapReceipt<CoinA, CoinB>): u64 {
    receipt.amount_b
}

public fun swap_receipt_zero_for_one<CoinA, CoinB>(receipt: &SwapReceipt<CoinA, CoinB>): bool {
    receipt.zero_for_one
}

/// ==== internal functions ====

fun default_step(): StepComputations {
    StepComputations {
        sqrt_price_start: 0,
        tick_next: i32::zero(),
        initialized: false,
        sqrt_price_next: 0,
        amount_in: 0,
        amount_out: 0,
        fee_amount: 0,
    }
}

fun swap_internal<CoinA, CoinB>(
    self: &mut Pool<CoinA, CoinB>,
    zero_for_one: bool, // 这个表示
    by_amount_in: bool,
    amount: u64,
    sqrt_price_limit: u128,
): (Balance<CoinA>, Balance<CoinB>, SwapReceipt<CoinA, CoinB>) {
    if (zero_for_one) {
        assert!(
            sqrt_price_limit < self.sqrt_price && sqrt_price_limit > tick_math::min_sqrt_price_x64(),
            E_PRICE_SPAN_TOO_LARGE,
        )
    } else {
        assert!(
            sqrt_price_limit > self.sqrt_price && sqrt_price_limit < tick_math::max_sqrt_price_x64(),
            E_PRICE_SPAN_TOO_LARGE,
        )
    };

    // 根据by_amount_in来处理输入和输出
    let amount_specified = if (by_amount_in) {
        i64::from(amount)
    } else {
        i64::neg_from(amount)
    };

    let cache = SwapCache {
        // 因为这个存储了两个手续费，也就是低位是tokenA，高位时tokenB
        fee_protocol: if (zero_for_one) (self.fee_protocol % 16) as u64
        else (self.fee_protocol >> 4) as u64,
        liquidity_start: self.liquidity,
    };

    // 保存交易过程中计算所需的中间变量，这些值在交易的步骤中可能会发生变化
    let mut state = SwapState {
        amount_specified_remaining: amount_specified,
        amount_calculated: i64::zero(),
        sqrt_price: self.sqrt_price,
        current_tick: self.current_tick,
        fee_growth_global: if (zero_for_one) self.fee_growth_global_a else self.fee_growth_global_b,
        protocol_fee: 0,
        liquidity: cache.liquidity_start,
    };

    // 只要 tokenIn
    // 因为只存储了tokenA的价格
    while (
        !state.amount_specified_remaining.eq(i64::zero()) && 
        state.sqrt_price != sqrt_price_limit
    ) {
        let mut step = default_step();
        // 交易的起始价格
        step.sqrt_price_start = state.sqrt_price;

        // 通过位图找到下一个可以选的交易价格，这里可能是下一个流动性的边界，也可能还是在本流动性中
        let (tick_next, initialized) = self
            .tick_bitmap
            .next_initialized_tick_with_in_one_word(
                state.current_tick,
                zero_for_one,
            );
        step.tick_next = tick_next;
        step.initialized = initialized;

        if (step.tick_next.lt(tick_math::min_tick())) {
            step.tick_next = tick_math::min_tick();
        } else if (step.tick_next.gt(tick_math::max_tick())) {
            step.tick_next = tick_math::max_tick();
        };

        // 从 tick index 计算 sqrt(price)
        step.sqrt_price_next = tick_math::get_sqrt_ratio_at_tick(step.tick_next);

        // 根据zero_for_one
        let sqrt_tratio_target = if (zero_for_one) {
            // 如果是输入tokenA，输出tokenB，那么sqrt_price_limit就是sqrt_price_next，表示sqrt_price变小
            if (step.sqrt_price_next < sqrt_price_limit) {
                sqrt_price_limit
            } else {
                // 或者是当前tick的sqrt_price
                step.sqrt_price_next
            }
        } else {
            // 如果是输入tokenB，输出tokenA，那么sqrt_price_limit就是sqrt_price_next，表示sqrt_price变大
            if (step.sqrt_price_next > sqrt_price_limit) {
                sqrt_price_limit
            } else {
                // 或者是当前tick的sqrt_price
                step.sqrt_price_next
            }
        };

        // 计算当价格到达下一个交易价格时，tokenIn 是否被耗尽，如果被耗尽，则交易结束，还需要重新计算出 tokenIn 耗尽时的价格
        // 如果没被耗尽，那么还需要继续进入下一个循环
        let (sqrt_price, amount_in, amount_out, fee_amount) = swap_math::compute_swap_step(
            state.sqrt_price,
            sqrt_tratio_target,
            state.liquidity,
            state.amount_specified_remaining,
            self.fee_rate,
        );
        state.sqrt_price = sqrt_price;
        step.amount_in = amount_in;
        step.amount_out = amount_out;
        step.fee_amount = fee_amount;

        // 更新 tokenIn 的余额，以及 tokenOut 数量，注意当指定 tokenIn 的数量进行交易时，这里的 tokenOut 是负数
        if (by_amount_in) {
            state.amount_specified_remaining =
                state
                    .amount_specified_remaining
                    .sub(i64::from_u64(step.amount_in + step.fee_amount));
            state.amount_calculated = state.amount_calculated.sub(i64::from_u64(step.amount_out));
        } else {
            state.amount_specified_remaining =
                state.amount_specified_remaining.add(i64::from_u64(step.amount_out));
            state.amount_calculated =
                state.amount_calculated.add(i64::from_u64(step.amount_in + step.fee_amount));
        };

        // 计算协议手续费
        if (cache.fee_protocol > 0) {
            let delta = step.fee_amount / cache.fee_protocol;
            step.fee_amount = step.fee_amount -  delta;
            state.protocol_fee = state.protocol_fee + delta;
        };

        // 计算每个流动性分配的手续费
        if (state.liquidity > 0)
            state.fee_growth_global =
                state.fee_growth_global + full_math_u128::mul_div_floor(step.fee_amount as u128, 1<<64, state.liquidity);

        // 按需决定是否需要更新流动性 L 的值
        if (state.sqrt_price == step.sqrt_price_next) {
            // 检查 tick index 是否为另一个流动性的边界
            if (step.initialized) {
                let mut liquidity_net = self
                    .ticks
                    .cross(
                        step.tick_next,
                        if (zero_for_one) state.fee_growth_global else self.fee_growth_global_a,
                        if (zero_for_one) self.fee_growth_global_b else state.fee_growth_global,
                    );
                // 根据价格增加/减少，即向左或向右移动，增加/减少相应的流动性
                if (zero_for_one) liquidity_net = liquidity_net.neg();

                state.liquidity = liquidity_math::add_delta(state.liquidity, liquidity_net);
            };
            // 在这里更 tick 的值，使得下一次循环时让 tickBitmap 进入下一个 word 中查询
            if (zero_for_one) {
                state.current_tick = step.tick_next.sub(i32::from(1));
            } else {
                state.current_tick = step.tick_next;
            };
        } else if (state.sqrt_price != step.sqrt_price_start) {
            // 如果 tokenIn 被耗尽，那么计算当前价格对应的 tick
            state.current_tick = tick_math::get_tick_at_sqrt_ratio(state.sqrt_price);
        };
    };

    if (!state.current_tick.eq(self.current_tick)) {
        self.sqrt_price = state.sqrt_price;
        self.current_tick = state.current_tick;
    } else {
        self.sqrt_price = state.sqrt_price;
    };

    if (cache.liquidity_start != state.liquidity) {
        self.liquidity = state.liquidity;
    };

    if (zero_for_one) {
        self.fee_growth_global_a = state.fee_growth_global;
        if (state.protocol_fee > 0) self.protocol_fee_a = self.protocol_fee_a + state.protocol_fee;
    } else {
        self.fee_growth_global_b = state.fee_growth_global;
        if (state.protocol_fee > 0) self.protocol_fee_b = self.protocol_fee_b + state.protocol_fee;
    };

    // 确定最终用户支付的 token 数和得到的 token 数
    let (amount_a, amount_b) = if (zero_for_one == by_amount_in) {
        (amount_specified.sub(state.amount_specified_remaining), state.amount_calculated)
    } else {
        (state.amount_calculated, amount_specified.sub(state.amount_specified_remaining))
    };

    let (balance_a, balance_b) = if (zero_for_one) {
        // 这里是输入 tokenA，输出 tokenB
        // 因此amount_b是负数
        let balance_b = if (amount_b.lt(i64::zero())) {
            self.coin_b.split(amount_b.abs_u64())
        } else {
            balance::zero()
        };
        (balance::zero(), balance_b)
    } else {
        // 这里是输入 tokenB，输出 tokenA
        // 因此amount_a是负数
        let balance_a = if (amount_a.lt(i64::zero())) {
            self.coin_a.split(amount_a.abs_u64())
        } else {
            balance::zero()
        };
        (balance_a, balance::zero())
    };

    let recipient = SwapReceipt<CoinA, CoinB> {
        pool_id: object::id(self),
        zero_for_one,
        amount_a: if (zero_for_one) amount_a.abs_u64() else 0,
        amount_b: if (!zero_for_one) amount_b.abs_u64() else 0,
    };

    (balance_a, balance_b, recipient)
}

fun modify_position_internal<CoinA, CoinB>(
    self: &mut Pool<CoinA, CoinB>,
    position_nft: &mut Position<CoinA, CoinB>,
    liquidity_delta: I128,
): (u64, u64) {
    self.update_position(position_nft, liquidity_delta);

    let (tick_lower, tick_upper) = position_nft.tick_range();
    let (mut amount_a, mut amount_b) = (0, 0);

    if (!liquidity_delta.eq(i128::zero())) {
        if (self.current_tick.lt(tick_lower)) {
            amount_a =
                sqrt_price_math::get_amount0_delta(
                    tick_math::get_sqrt_ratio_at_tick(tick_lower),
                    tick_math::get_sqrt_ratio_at_tick(tick_upper),
                    liquidity_delta,
                );
        } else if (self.current_tick.lt(tick_upper)) {
            let liquidity_before = self.liquidity;
            amount_a =
                sqrt_price_math::get_amount0_delta(
                    self.sqrt_price,
                    tick_math::get_sqrt_ratio_at_tick(tick_upper),
                    liquidity_delta,
                );
            amount_b =
                sqrt_price_math::get_amount1_delta(
                    tick_math::get_sqrt_ratio_at_tick(tick_lower),
                    self.sqrt_price,
                    liquidity_delta,
                );
            let liquidity_after = liquidity_delta.add(i128::from(liquidity_before));
            // 这里必须保证liquidity_after >= 0，理论上不会出现，但是为了安全，这里加上
            assert!(liquidity_after.gte(i128::zero()), E_LIQUIDITY_DATA_ERROR);
            self.liquidity = liquidity_after.as_u128();
        } else {
            amount_b =
                sqrt_price_math::get_amount1_delta(
                    tick_math::get_sqrt_ratio_at_tick(tick_lower),
                    tick_math::get_sqrt_ratio_at_tick(tick_upper),
                    liquidity_delta,
                );
        }
    };
    (amount_a, amount_b)
}

fun update_position<CoinA, CoinB>(
    self: &mut Pool<CoinA, CoinB>,
    position_nft: &mut Position<CoinA, CoinB>,
    liquidity_delta: I128,
) {
    let _fee_growth_global_a = self.fee_growth_global_a;
    let _fee_growth_global_b = self.fee_growth_global_b;

    let (mut flipped_lower, mut flipped_upper) = (false, false);
    let (tick_lower, tick_upper) = position_nft.tick_range();

    if (liquidity_delta != i128::zero()) {
        flipped_lower =
            self
                .ticks
                .update(
                    tick_lower,
                    self.current_tick,
                    liquidity_delta,
                    _fee_growth_global_a,
                    _fee_growth_global_b,
                    false,
                );

        flipped_upper =
            self
                .ticks
                .update(
                    tick_upper,
                    self.current_tick,
                    liquidity_delta,
                    _fee_growth_global_a,
                    _fee_growth_global_b,
                    true,
                );

        if (flipped_lower) {
            self.tick_bitmap.flip_tick(tick_lower);
        };
        if (flipped_upper) {
            self.tick_bitmap.flip_tick(tick_upper);
        };
    };

    let (fee_growth_inside_a, fee_growth_inside_b) = self
        .ticks
        .get_fee_growth_inside(
            tick_lower,
            tick_upper,
            self.current_tick,
            _fee_growth_global_a,
            _fee_growth_global_b,
        );

    position_nft.update(
        liquidity_delta,
        fee_growth_inside_a,
        fee_growth_inside_b,
    );

    if (liquidity_delta.lt(i128::zero())) {
        if (flipped_lower) {
            self.ticks.clear(tick_lower);
        };
        if (flipped_upper) {
            self.ticks.clear(tick_upper);
        };
    };
}
