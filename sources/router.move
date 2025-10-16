module v3_core_move::router;

use sui::balance;
use sui::coin::{Self, Coin};
use v3_core_move::config::Config;
use v3_core_move::pool::Pool;

// Constant
#[error]
const E_INSUFFICIENT_OUTPUT_AMOUNT: vector<u8> = b"Insufficient output amount";

public entry fun swap<CoinA, CoinB>(
    pool: &mut Pool<CoinA, CoinB>,
    config: &Config,
    mut coin_a: Coin<CoinA>,
    mut coin_b: Coin<CoinB>,
    zero_for_one: bool,
    by_amount_in: bool,
    amount: u64,
    sqrt_price_limit: u128,
    ctx: &mut TxContext,
) {
    let (balance_a, balance_b, recipient) = pool.swap(
        config,
        zero_for_one,
        by_amount_in,
        amount,
        sqrt_price_limit,
        ctx,
    );

    if (zero_for_one) {
        // 偿还输入代币
        let amount_in = coin_a.split(recipient.swap_receipt_amount_a(), ctx).into_balance();
        pool.repay_swap(config, amount_in, balance::zero(), recipient);
        coin_b.join(balance_b.into_coin(ctx));
        balance_a.destroy_zero();
    } else {
        let amount_in = coin_b.split(recipient.swap_receipt_amount_b(), ctx).into_balance();
        // 偿还输出代币
        pool.repay_swap(config, balance::zero(), amount_in, recipient);
        coin_a.join(balance_a.into_coin(ctx));
        balance_b.destroy_zero();
    };

    if (coin_a.value() > 0) {
        transfer::public_transfer(coin_a, ctx.sender());
    } else {
        coin_a.destroy_zero();
    };

    if (coin_b.value() > 0) {
        transfer::public_transfer(coin_b, ctx.sender());
    } else {
        coin_b.destroy_zero();
    };
}

// ============================================
// 公共Entry函数 - 双跳交换
// ============================================

/// 双跳交换: A→B→C (第一跳池: A/B, 第二跳池: B/C)
///
/// 路径: CoinA → CoinB → CoinC
/// 池子配置: Pool<CoinA, CoinB> + Pool<CoinB, CoinC>
///
/// 参数:
/// - pool_ab: 第一跳流动性池
/// - pool_bc: 第二跳流动性池
/// - config: 全局配置对象
/// - coin_a: 起始代币
/// - amount_c_out_min: 最终输出最小值
/// - sqrt_price_limit_1: 第一跳价格限制
/// - sqrt_price_limit_2: 第二跳价格限制
/// - ctx: 交易上下文
public entry fun swap_ab_bc<CoinA, CoinB, CoinC>(
    pool_ab: &mut Pool<CoinA, CoinB>,
    pool_bc: &mut Pool<CoinB, CoinC>,
    config: &Config,
    coin_a: Coin<CoinA>,
    amount_c_out_min: u64,
    sqrt_price_limit_1: u128,
    sqrt_price_limit_2: u128,
    ctx: &mut TxContext,
) {
    let amount_a_in = coin_a.value();

    // 第一跳: A → B (在Pool<A,B>中, zero_for_one=true)
    let balance_a = coin_a.into_balance();
    let (balance_a_out1, balance_b_out1, receipt1) = pool_ab.swap<CoinA, CoinB>(
        config,
        true, // zero_for_one: A → B
        true, // by_amount_in
        amount_a_in,
        sqrt_price_limit_1,
        ctx,
    );

    // 偿还第一跳
    pool_ab.repay_swap(
        config,
        balance_a,
        balance::zero<CoinB>(),
        receipt1,
    );
    balance::destroy_zero(balance_a_out1);

    // 将中间代币B转换为Coin再转换为Balance用于第二跳
    let amount_b = balance_b_out1.value();

    // 第二跳: B → C (在Pool<B,C>中, zero_for_one=true)
    let (balance_b_out2, balance_c_out2, receipt2) = pool_bc.swap<CoinB, CoinC>(
        config,
        true, // zero_for_one: B → C
        true, // by_amount_in
        amount_b,
        sqrt_price_limit_2,
        ctx,
    );

    // 偿还第二跳
    pool_bc.repay_swap(
        config,
        balance_b_out1,
        balance::zero<CoinC>(),
        receipt2,
    );
    balance_b_out2.destroy_zero();

    // 检查最终输出的滑点保护
    assert!(balance_c_out2.value() >= amount_c_out_min, E_INSUFFICIENT_OUTPUT_AMOUNT);

    // 转移最终输出代币
    let coin_c = coin::from_balance(balance_c_out2, ctx);
    transfer::public_transfer(coin_c, ctx.sender());
}

/// 双跳交换: A→B→C (第一跳池: A/B, 第二跳池: C/B)
///
/// 路径: CoinA → CoinB → CoinC
/// 池子配置: Pool<CoinA, CoinB> + Pool<CoinC, CoinB>
///
/// 与swap_ab_bc的差异: 第二个池子的代币顺序为C/B(而非B/C)
public entry fun swap_ab_cb<CoinA, CoinB, CoinC>(
    pool_ab: &mut Pool<CoinA, CoinB>,
    pool_cb: &mut Pool<CoinC, CoinB>,
    config: &Config,
    coin_a: Coin<CoinA>,
    amount_c_out_min: u64,
    sqrt_price_limit_1: u128,
    sqrt_price_limit_2: u128,
    ctx: &mut TxContext,
) {
    let amount_a_in = coin::value(&coin_a);

    // 第一跳: A → B (在Pool<A,B>中, zero_for_one=true)
    let balance_a = coin::into_balance(coin_a);
    let (balance_a_out1, balance_b_out1, receipt1) = pool_ab.swap<CoinA, CoinB>(
        config,
        true, // zero_for_one: A → B
        true, // by_amount_in
        amount_a_in,
        sqrt_price_limit_1,
        ctx,
    );

    // 偿还第一跳
    pool_ab.repay_swap(config, balance_a, balance::zero<CoinB>(), receipt1);
    balance_a_out1.destroy_zero();

    // 将中间代币B转换为Coin再转换为Balance用于第二跳
    let amount_b = balance_b_out1.value();

    // 第二跳: B → C (在Pool<C,B>中, zero_for_one=false)
    let (balance_c_out2, balance_b_out2, receipt2) = pool_cb.swap<CoinC, CoinB>(
        config,
        false, // zero_for_one=false: B → C (在C/B池中)
        true, // by_amount_in
        amount_b,
        sqrt_price_limit_2,
        ctx,
    );

    // 偿还第二跳
    pool_cb.repay_swap(config, balance::zero<CoinC>(), balance_b_out1, receipt2);
    balance_b_out2.destroy_zero();

    // 检查最终输出的滑点保护
    assert!(balance_c_out2.value() >= amount_c_out_min, E_INSUFFICIENT_OUTPUT_AMOUNT);

    // 转移最终输出代币
    let coin_c = coin::from_balance(balance_c_out2, ctx);
    transfer::public_transfer(coin_c, ctx.sender());
}

/// 双跳交换: A→B→C (第一跳池: B/A, 第二跳池: B/C)
///
/// 路径: CoinA → CoinB → CoinC
/// 池子配置: Pool<CoinB, CoinA> + Pool<CoinB, CoinC>
///
/// 特征: 第一个池子的代币顺序为B/A
public entry fun swap_ba_bc<CoinA, CoinB, CoinC>(
    pool_ba: &mut Pool<CoinB, CoinA>,
    pool_bc: &mut Pool<CoinB, CoinC>,
    config: &Config,
    coin_a: Coin<CoinA>,
    amount_c_out_min: u64,
    sqrt_price_limit_1: u128,
    sqrt_price_limit_2: u128,
    ctx: &mut TxContext,
) {
    let amount_a_in = coin_a.value();

    // 第一跳: A → B (在Pool<B,A>中, zero_for_one=false)
    let (balance_b_out1, balance_a_out1, receipt1) = pool_ba.swap<CoinB, CoinA>(
        config,
        false, // zero_for_one=false: A → B (在B/A池中)
        true, // by_amount_in
        amount_a_in,
        sqrt_price_limit_1,
        ctx,
    );

    // 偿还第一跳
    pool_ba.repay_swap(config, balance::zero<CoinB>(), coin_a.into_balance(), receipt1);
    balance_a_out1.destroy_zero();

    // 将中间代币B转换为Coin再转换为Balance用于第二跳
    let amount_b = balance_b_out1.value();

    // 第二跳: B → C (在Pool<B,C>中, zero_for_one=true)
    let (balance_b_out2, balance_c_out2, receipt2) = pool_bc.swap<CoinB, CoinC>(
        config,
        true, // zero_for_one: B → C
        true, // by_amount_in
        amount_b,
        sqrt_price_limit_2,
        ctx,
    );

    // 偿还第二跳
    pool_bc.repay_swap(config, balance_b_out1, balance::zero<CoinC>(), receipt2);
    balance_b_out2.destroy_zero();

    // 检查最终输出的滑点保护
    assert!(balance_c_out2.value() >= amount_c_out_min, E_INSUFFICIENT_OUTPUT_AMOUNT);

    // 转移最终输出代币
    let coin_c = coin::from_balance(balance_c_out2, ctx);
    transfer::public_transfer(coin_c, ctx.sender());
}

/// 双跳交换: A→B→C (第一跳池: B/A, 第二跳池: C/B)
///
/// 路径: CoinA → CoinB → CoinC
/// 池子配置: Pool<CoinB, CoinA> + Pool<CoinC, CoinB>
///
/// 特征: 两个池子的代币顺序都与标准顺序相反
public entry fun swap_ba_cb<CoinA, CoinB, CoinC>(
    pool_ba: &mut Pool<CoinB, CoinA>,
    pool_cb: &mut Pool<CoinC, CoinB>,
    config: &Config,
    coin_a: Coin<CoinA>,
    amount_c_out_min: u64,
    sqrt_price_limit_1: u128,
    sqrt_price_limit_2: u128,
    ctx: &mut TxContext,
) {
    let amount_a_in = coin_a.value();

    // 第一跳: A → B (在Pool<B,A>中, zero_for_one=false)
    let (balance_b_out1, balance_a_out1, receipt1) = pool_ba.swap<CoinB, CoinA>(
        config,
        false, // zero_for_one=false: A → B (在B/A池中)
        true, // by_amount_in
        amount_a_in,
        sqrt_price_limit_1,
        ctx,
    );

    // 偿还第一跳
    pool_ba.repay_swap(config, balance::zero<CoinB>(), coin_a.into_balance(), receipt1);
    balance_a_out1.destroy_zero();

    // 将中间代币B转换为Coin再转换为Balance用于第二跳
    let amount_b = balance_b_out1.value();

    // 第二跳: B → C (在Pool<C,B>中, zero_for_one=false)
    let (balance_c_out2, balance_b_out2, receipt2) = pool_cb.swap<CoinC, CoinB>(
        config,
        false, // zero_for_one=false: B → C (在C/B池中)
        true, // by_amount_in
        amount_b,
        sqrt_price_limit_2,
        ctx,
    );

    // 偿还第二跳
    pool_cb.repay_swap(config, balance::zero<CoinC>(), balance_b_out1, receipt2);
    balance_b_out2.destroy_zero();

    // 检查最终输出的滑点保护
    assert!(balance_c_out2.value() >= amount_c_out_min, E_INSUFFICIENT_OUTPUT_AMOUNT);

    // 转移最终输出代币
    let coin_c = coin::from_balance(balance_c_out2, ctx);
    transfer::public_transfer(coin_c, ctx.sender());
}
