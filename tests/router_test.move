#[test_only]
module v3_core_move::router_test;

use sui::balance;
use sui::coin;
use sui::test_scenario::{Self, Scenario};
use v3_core_move::config::{Self, Config};
use v3_core_move::factory::{Self, Factory};
use v3_core_move::i32;
use v3_core_move::pool::Pool;
use v3_core_move::position::Position;
use v3_core_move::router;
use v3_core_move::tick_math;

// ============================================
// 测试常量定义
// ============================================

const ADMIN: address = @0x1;
const LP_PROVIDER: address = @0x2;
const SWAPER: address = @0x3;

const SMALL_AMOUNT: u64 = 100;
const MEDIUM_AMOUNT: u64 = 10_000;
const LIQUIDITY_STANDARD: u128 = 1_000_000;

// ============================================
// 测试代币结构定义
// ============================================

public struct USDC {}
public struct WETH {}
public struct DAI {}
public struct USDT {}

// ============================================
// 辅助函数 - 环境初始化
// ============================================

/// 初始化Factory和Config
fun init_factory_and_config(scenario: &mut Scenario) {
    scenario.next_tx(ADMIN);
    {
        factory::init_for_testing(scenario.ctx());
        config::init_for_testing(scenario.ctx());
    };
}

/// 创建单个流动性池并添加流动性
/// 返回Position对象用于后续清理
fun setup_single_pool<CoinA, CoinB>(
    scenario: &mut Scenario,
    init_tick: u32,
    liquidity: u128,
): Position<CoinA, CoinB> {
    // 初始化系统
    init_factory_and_config(scenario);

    // 创建池子
    scenario.next_tx(LP_PROVIDER);
    {
        let mut factory = scenario.take_shared<Factory>();
        let config = scenario.take_shared<Config>();
        let init_sqrt_price = tick_math::get_sqrt_ratio_at_tick(i32::from(init_tick));
        factory.create_pool<CoinA, CoinB>(&config, init_sqrt_price, 500, scenario.ctx());
        test_scenario::return_shared(config);
        test_scenario::return_shared(factory);
    };

    // 添加流动性
    scenario.next_tx(LP_PROVIDER);
    let mut pool = scenario.take_shared<Pool<CoinA, CoinB>>();
    let config = scenario.take_shared<Config>();

    // 创建价格区间
    let tick_lower = i32::neg_from(1000);
    let tick_upper = i32::from(1000);

    let mut position = pool.open_position<CoinA, CoinB>(
        &config,
        tick_lower.as_u32(),
        tick_upper.as_u32(),
        scenario.ctx(),
    );

    // 添加流动性
    let receipt = pool.add_liquidity(&config, &mut position, liquidity, scenario.ctx());
    let amount_a = receipt.add_liquidity_receipt_amount_a();
    let amount_b = receipt.add_liquidity_receipt_amount_b();

    let balance_a = balance::create_for_testing<CoinA>(amount_a);
    let balance_b = balance::create_for_testing<CoinB>(amount_b);

    pool.repay_add_liquidity_receipt(&config, receipt, balance_a, balance_b);

    test_scenario::return_shared(config);
    test_scenario::return_shared(pool);

    position
}

// ============================================
// 单跳交换测试用例
// ============================================

/// 测试:精确输入的单跳交换(A→B方向)
#[test]
fun test_swap_exact_input_a_to_b() {
    let mut scenario = test_scenario::begin(ADMIN);
    // 注意:WETH > USDC (字典序),所以Pool<WETH, USDC>
    let position = setup_single_pool<WETH, USDC>(&mut scenario, 0, LIQUIDITY_STANDARD);

    // 执行交换
    scenario.next_tx(SWAPER);
    {
        let mut pool = scenario.take_shared<Pool<WETH, USDC>>();
        let config = scenario.take_shared<Config>();

        let sqrt_price_before = pool.sqrt_price();

        // 创建输入代币
        let coin_weth = coin::mint_for_testing<WETH>(MEDIUM_AMOUNT, scenario.ctx());

        // 执行Router swap: WETH → USDC
        router::swap<WETH, USDC>(
            &mut pool,
            &config,
            coin_weth,
            coin::zero(scenario.ctx()),
            true,
            true,
            MEDIUM_AMOUNT - 1000, // 允许一些滑点
            tick_math::min_sqrt_price_x64() + 1,
            scenario.ctx(),
        );

        // 验证价格下降
        let sqrt_price_after = pool.sqrt_price();
        assert!(sqrt_price_after < sqrt_price_before, 0);

        test_scenario::return_shared(config);
        test_scenario::return_shared(pool);
    };

    // 验证SWAPER收到了USDC
    scenario.next_tx(SWAPER);
    {
        assert!(test_scenario::has_most_recent_for_address<coin::Coin<USDC>>(SWAPER), 1);
        let coin_usdc = scenario.take_from_address<coin::Coin<USDC>>(SWAPER);
        assert!(coin::value(&coin_usdc) > 0, 2);
        test_scenario::return_to_address(SWAPER, coin_usdc);
    };

    transfer::public_transfer(position, LP_PROVIDER);
    scenario.end();
}

/// 测试:精确输入的单跳交换(B→A方向)
#[test]
fun test_swap_exact_input_b_to_a() {
    let mut scenario = test_scenario::begin(ADMIN);
    let position = setup_single_pool<WETH, USDC>(&mut scenario, 0, LIQUIDITY_STANDARD);

    // 执行交换
    scenario.next_tx(SWAPER);
    {
        let mut pool = scenario.take_shared<Pool<WETH, USDC>>();
        let config = scenario.take_shared<Config>();

        let sqrt_price_before = pool.sqrt_price();

        // 创建输入代币
        let coin_usdc = coin::mint_for_testing<USDC>(SMALL_AMOUNT, scenario.ctx());

        // 执行Router swap: USDC → WETH
        router::swap<WETH, USDC>(
            &mut pool,
            &config,
            coin::zero(scenario.ctx()),
            coin_usdc,
            false,
            true,
            SMALL_AMOUNT,
            tick_math::max_sqrt_price_x64() - 1,
            scenario.ctx(),
        );

        // 验证价格上升
        let sqrt_price_after = pool.sqrt_price();
        assert!(sqrt_price_after > sqrt_price_before, 0);

        test_scenario::return_shared(config);
        test_scenario::return_shared(pool);
    };

    // 验证SWAPER收到了WETH
    scenario.next_tx(SWAPER);
    {
        assert!(test_scenario::has_most_recent_for_address<coin::Coin<WETH>>(SWAPER), 1);
        let coin_weth = scenario.take_from_address<coin::Coin<WETH>>(SWAPER);
        assert!(coin::value(&coin_weth) > 0, 2);
        test_scenario::return_to_address(SWAPER, coin_weth);
    };

    transfer::public_transfer(position, LP_PROVIDER);
    scenario.end();
}

// ============================================
// 双跳交换测试用例 - AB_BC路径
// ============================================

/// 测试:标准AB→BC双跳路径
/// 路径: WETH → USDC → DAI
/// 池子1: WETH/USDC (WETH > USDC)
/// 池子2: USDC/DAI (USDC > DAI)
#[test]
fun test_swap_ab_bc_standard_path() {
    let mut scenario = test_scenario::begin(ADMIN);

    // 初始化系统
    init_factory_and_config(&mut scenario);

    // 创建第一个池子: Pool<WETH, USDC>
    scenario.next_tx(LP_PROVIDER);
    {
        let mut factory = scenario.take_shared<Factory>();
        let config = scenario.take_shared<Config>();
        let init_sqrt_price = tick_math::get_sqrt_ratio_at_tick(i32::from(0));
        factory.create_pool<WETH, USDC>(&config, init_sqrt_price, 500, scenario.ctx());
        test_scenario::return_shared(config);
        test_scenario::return_shared(factory);
    };

    // 添加流动性到第一个池子
    scenario.next_tx(LP_PROVIDER);
    let mut pool1 = scenario.take_shared<Pool<WETH, USDC>>();
    let config = scenario.take_shared<Config>();

    let tick_lower = i32::neg_from(1000);
    let tick_upper = i32::from(1000);

    let mut position1 = pool1.open_position<WETH, USDC>(
        &config,
        tick_lower.as_u32(),
        tick_upper.as_u32(),
        scenario.ctx(),
    );

    let receipt1 = pool1.add_liquidity(&config, &mut position1, LIQUIDITY_STANDARD, scenario.ctx());
    let amount_w = receipt1.add_liquidity_receipt_amount_a();
    let amount_u = receipt1.add_liquidity_receipt_amount_b();

    let balance_w = balance::create_for_testing<WETH>(amount_w);
    let balance_u = balance::create_for_testing<USDC>(amount_u);

    pool1.repay_add_liquidity_receipt(&config, receipt1, balance_w, balance_u);

    test_scenario::return_shared(config);
    test_scenario::return_shared(pool1);

    // 创建第二个池子: Pool<USDC, DAI>
    scenario.next_tx(LP_PROVIDER);
    {
        let mut factory = scenario.take_shared<Factory>();
        let config = scenario.take_shared<Config>();
        let init_sqrt_price = tick_math::get_sqrt_ratio_at_tick(i32::from(0));
        factory.create_pool<USDC, DAI>(&config, init_sqrt_price, 500, scenario.ctx());
        test_scenario::return_shared(config);
        test_scenario::return_shared(factory);
    };

    // 添加流动性到第二个池子
    scenario.next_tx(LP_PROVIDER);
    let mut pool2 = scenario.take_shared<Pool<USDC, DAI>>();
    let config = scenario.take_shared<Config>();

    let mut position2 = pool2.open_position<USDC, DAI>(
        &config,
        tick_lower.as_u32(),
        tick_upper.as_u32(),
        scenario.ctx(),
    );

    let receipt2 = pool2.add_liquidity(&config, &mut position2, LIQUIDITY_STANDARD, scenario.ctx());
    let amount_u2 = receipt2.add_liquidity_receipt_amount_a();
    let amount_d2 = receipt2.add_liquidity_receipt_amount_b();

    let balance_u2 = balance::create_for_testing<USDC>(amount_u2);
    let balance_d2 = balance::create_for_testing<DAI>(amount_d2);

    pool2.repay_add_liquidity_receipt(&config, receipt2, balance_u2, balance_d2);

    test_scenario::return_shared(config);
    test_scenario::return_shared(pool2);

    // 执行双跳交换: WETH → USDC → DAI
    scenario.next_tx(SWAPER);
    {
        let mut pool_ab = scenario.take_shared<Pool<WETH, USDC>>();
        let mut pool_bc = scenario.take_shared<Pool<USDC, DAI>>();
        let config = scenario.take_shared<Config>();

        let coin_weth = coin::mint_for_testing<WETH>(MEDIUM_AMOUNT, scenario.ctx());

        // 执行Router双跳swap: WETH → USDC → DAI
        router::swap_ab_bc<WETH, USDC, DAI>(
            &mut pool_ab,
            &mut pool_bc,
            &config,
            coin_weth,
            MEDIUM_AMOUNT - 2000, // 允许双跳的滑点
            tick_math::min_sqrt_price_x64() + 1,
            tick_math::min_sqrt_price_x64() + 1,
            scenario.ctx(),
        );

        test_scenario::return_shared(config);
        test_scenario::return_shared(pool_bc);
        test_scenario::return_shared(pool_ab);
    };

    // 验证SWAPER收到了DAI
    scenario.next_tx(SWAPER);
    {
        assert!(test_scenario::has_most_recent_for_address<coin::Coin<DAI>>(SWAPER), 0);
        let coin_dai = scenario.take_from_address<coin::Coin<DAI>>(SWAPER);
        let amount_dai = coin::value(&coin_dai);
        assert!(amount_dai > 0, 1);
        assert!(amount_dai >= MEDIUM_AMOUNT - 2000, 2);
        test_scenario::return_to_address(SWAPER, coin_dai);
    };

    transfer::public_transfer(position1, LP_PROVIDER);
    transfer::public_transfer(position2, LP_PROVIDER);
    scenario.end();
}
