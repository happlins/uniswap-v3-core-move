module v3_core_move::sqrt_price_math;

use v3_core_move::full_math_u128;
use v3_core_move::i128::I128;
use v3_core_move::math_u128;
use v3_core_move::math_u256;

public fun get_next_sqrt_price_from_amount0_rounding_up(
    sqrt_price_x64: u128,
    liquidity: u128,
    amount: u64,
    add: bool,
): u128 {
    // amount = delta(1 / sqrt(p)) * L
    // amount = (1 / sqrt(b) - 1 / sqrt(a)) * L
    // amount =  L * ((sqrt(a) - sqrt(b)) / sqrt(a) * sqrt(b))

    // amount * (P_a ^ 2 * P_b ^ 2) / (P_b ^ 2 - P_a ^ 2) = L
    // amount * P_a ^ 2 * P_b ^ 2 = L * P_b ^ 2 - L * P_a ^ 2

    // 加入token0,价格P_b -> P_a价格降低
    // amount * P_a ^ 2 * P_b ^ 2 + L * P_a ^ 2 = L * P_b ^ 2
    // P_a ^ 2 * ( amount * P_b ^ 2 + L) = L * P_b ^ 2
    // P_a ^ 2 = L * P_b ^ 2 / (amount * P_b ^ 2 + L)
    // sqrtP_next = (L * sqrtP) / (L + Δx * sqrtP)
    // 在溢出时,因为有乘法
    // P_a ^ 2 = L / amount + P_b ^ 2
    // P_a ^ 2 = L / (L / P_b ^ 2 + amount)
    // sqrtP_next = L / (L / sqrtP + Δx)
    // 移除token0,价格P_a -> P_b价格上升
    // L * P_b ^ 2 - amount * P_a ^ 2 * P_b ^ 2 = L * P_a ^ 2
    // P_b ^ 2 * (L - amount * P_a ^ 2) = L * P_a  ^ 2
    // P_b ^ 2 = L * P_a ^ 2 / (L - amount * P_a ^ 2)
    // sqrtP_next = (L * sqrtP) / (L - Δx * sqrtP)

    if (amount == 0) return sqrt_price_x64;

    let (numberator1, overflowing) = math_u256::checked_shlw(
        full_math_u128::full_mul(sqrt_price_x64, liquidity),
    );
    assert!(!overflowing, 0);

    let liquidity_shl_64 = (liquidity as u256) << 64;
    let product = full_math_u128::full_mul(amount as u128, sqrt_price_x64);

    if (add) {
        if (product / (amount as u256) == sqrt_price_x64 as u256) {
            let denominator: u256 = liquidity_shl_64 + product;
            if (denominator >= liquidity_shl_64) {
                // liquidity * sqrtPX96 / (liquidity + amount * sqrtPX96)
                return math_u256::div_round(numberator1, denominator, true) as u128;
            };
        };
        // liquidity / ((liquidity / sqrtPX96) + amount)
        math_u256::div_round(
            liquidity_shl_64,
            (liquidity_shl_64 / (sqrt_price_x64 as u256) + (amount as u256)),
            true,
        ) as u128
    } else {
        assert!(
            product / (amount as u256) == sqrt_price_x64 as u256 && liquidity_shl_64 >= product,
            0,
        );
        let denominator: u256 = liquidity_shl_64 - product;
        // liquidity * sqrtPX96 / (liquidity - amount * sqrtPX96)
        math_u256::div_round(numberator1, denominator, true) as u128
    }
}

public fun get_next_sqrt_price_from_amount1_rounding_down(
    sqrt_price_x64: u128,
    liquidity: u128,
    amount: u64,
    add: bool,
): u128 {
    // amount = delta(sqrt(p)) * L
    // amount = (sqrt(b) - sqrt(a)) * L

    // amount / (P_b ^ 2 - P_a ^ 2) = L
    // amount = L * P_b ^ 2 - L * P_a ^ 2

    // 加入token1时，价格升高 P_a -> P_b
    // L * P_b ^ 2 = amount + L * P_a ^ 2
    // P_b ^ 2 = amount / L + P_a ^ 2
    // 移除token1时，价格降低 P_b -> P_a
    // L * P_a ^ 2  = L * P_b ^ 2 - amount
    // P_a ^ 2 = P_b ^ 2 - amount / L

    // 如果我们要添加（减去），向下舍入需要将商向下（向上）舍入

    let delta_sqrt_price = math_u128::checked_div_round((amount as u128) << 64, liquidity, !add);

    if (add) {
        sqrt_price_x64 + delta_sqrt_price
    } else {
        sqrt_price_x64 - delta_sqrt_price
    }
}

public fun get_next_sqrt_price_from_input(
    sqrt_price_x64: u128,
    liquidity: u128,
    amount: u64,
    zero_for_one: bool,
): u128 {
    assert!(sqrt_price_x64 > 0, 0);
    assert!(liquidity > 0, 0);
    if (zero_for_one) {
        get_next_sqrt_price_from_amount0_rounding_up(sqrt_price_x64, liquidity, amount, true)
    } else {
        get_next_sqrt_price_from_amount1_rounding_down(sqrt_price_x64, liquidity, amount, true)
    }
}

public fun get_next_sqrt_price_from_output(
    sqrt_price_x64: u128,
    liquidity: u128,
    amount: u64,
    zero_for_one: bool,
): u128 {
    assert!(sqrt_price_x64 > 0, 0);
    assert!(liquidity > 0, 0);
    if (zero_for_one) {
        get_next_sqrt_price_from_amount1_rounding_down(sqrt_price_x64, liquidity, amount, false)
    } else {
        get_next_sqrt_price_from_amount0_rounding_up(sqrt_price_x64, liquidity, amount, false)
    }
}

public fun get_delta_amount0_unsigned(
    mut sqrt_price0_x64: u128,
    mut sqrt_price1_x64: u128,
    liquidity: u128,
    round_up: bool,
): u64 {
    // 1.当提供/增加流动性时，会使用 RoundUp，这样可以保证增加数量为 L 的流动性时，用户提供足够的 token 到 pool 中
    // 2.当移除/减少流动性时，会使用 RoundDown，这样可以保证减少数量为 L 的流动性时，不会从 pool 中给用户多余的 token

    // amount * (P_a ^ 2 * P_b ^ 2) / (P_b ^ 2 - P_a ^ 2) = L
    // amount = L * (P_b ^ 2 - P_a ^ 2) / (P_a ^ 2 * P_b ^ 2)

    if (sqrt_price0_x64 > sqrt_price1_x64) {
        (sqrt_price0_x64, sqrt_price1_x64) = (sqrt_price1_x64, sqrt_price0_x64)
    };

    assert!(sqrt_price0_x64 > 0, 0);

    let numerator2 = (sqrt_price1_x64 - sqrt_price0_x64);

    let (numberator1, overflowing) = math_u256::checked_shlw(
        full_math_u128::full_mul(liquidity, numerator2),
    );
    assert!(overflowing == false, 0);
    let danominator = full_math_u128::full_mul(sqrt_price0_x64, sqrt_price1_x64);
    math_u256::div_round(numberator1, danominator, round_up) as u64
}

public fun get_delta_amount1_unsigned(
    mut sqrt_price0_x64: u128,
    mut sqrt_price1_x64: u128,
    liquidity: u128,
    round_up: bool,
): u64 {
    //  1.当提供/增加流动性时，会使用 RoundUp，这样可以保证增加数量为 L 的流动性时，用户提供足够的 token 到 pool 中
    //  2.当移除/减少流动性时，会使用 RoundDown，这样可以保证减少数量为 L 的流动性时，不会从 pool 中给用户多余的 token
    // amount / (P_b ^ 2 - P_a ^ 2) = L
    // amount = L * (P_b ^ 2 - P_a ^ 2)

    // 确保 sqrtRatioAX96 是较小的价格（交换A和B以保证顺序）
    if (sqrt_price0_x64 > sqrt_price1_x64) {
        (sqrt_price0_x64, sqrt_price1_x64) = (sqrt_price1_x64, sqrt_price0_x64)
    };
    assert!(sqrt_price0_x64 > 0, 0);

    let diff = (sqrt_price1_x64 - sqrt_price0_x64);

    let numberator = full_math_u128::full_mul(liquidity, diff);

    math_u256::div_round(numberator, 1<<64, round_up) as u64
}

public fun get_amount0_delta(sqrt_price0_x64: u128, sqrt_price1_x64: u128, liquidity: I128): u64 {
    if (liquidity.is_neg()) {
        get_delta_amount0_unsigned(sqrt_price0_x64, sqrt_price1_x64, liquidity.abs_u128(), false)
    } else {
        get_delta_amount0_unsigned(sqrt_price0_x64, sqrt_price1_x64, liquidity.abs_u128(), true)
    }
}

public fun get_amount1_delta(sqrt_price0_x64: u128, sqrt_price1_x64: u128, liquidity: I128): u64 {
    if (liquidity.is_neg()) {
        get_delta_amount1_unsigned(sqrt_price0_x64, sqrt_price1_x64, liquidity.abs_u128(), false)
    } else {
        get_delta_amount1_unsigned(sqrt_price0_x64, sqrt_price1_x64, liquidity.abs_u128(), true)
    }
}

#[test]
fun test_get_amount0_delta() {
    assert!(get_delta_amount0_unsigned(4u128<<64, 2u128<<64, 4, true) == 1, 0);
    assert!(get_delta_amount0_unsigned(4u128<<64, 2u128<<64, 4, false) == 1, 0);

    assert!(get_delta_amount0_unsigned(4 << 64, 4 << 64, 4, true) == 0, 0);
    assert!(get_delta_amount0_unsigned(4 << 64, 4 <<64, 4, false) == 0, 0);
}

#[test]
fun test_get_amount1_delta() {
    assert!(get_delta_amount1_unsigned(4u128<<64, 2u128<<64, 4, true) == 8, 0);
    assert!(get_delta_amount1_unsigned(4u128<<64, 2u128<<64, 4, false) == 8, 0);

    assert!(get_delta_amount1_unsigned(4 <<64, 4 <<64, 4, true) == 0, 0);
    assert!(get_delta_amount1_unsigned(4 <<64, 4 <<64, 4, false) == 0, 0);
}

#[test]
fun test_get_next_sqrt_price_from_amount0_rounding_up() {
    let (sqrt_price, liquidity, amount) = (10u128 << 64, 200u128 << 64, 10000000u64);
    let r1 = get_next_sqrt_price_from_amount0_rounding_up(sqrt_price, liquidity, amount, true);
    // 184467440737090516161u128
    assert!(r1 == 184467440737090516161u128, 0);
    let r2 = get_next_sqrt_price_from_amount0_rounding_up(
        sqrt_price,
        liquidity,
        amount,
        false,
    );
    // 184467440737100516161u128
    assert!(r2 == 184467440737100516161u128, 0);
}

#[test]
fun test_get_next_sqrt_price_from_amount1_down() {
    let (sqrt_price, liquidity, amount, add) = (
        62058032627749460283664515388u128,
        56315830353026631512438212669420532741u128,
        10476203047244913035u64,
        true,
    );
    let r = get_next_sqrt_price_from_amount1_rounding_down(sqrt_price, liquidity, amount, add);
    assert!(62058032627749460283664515391u128 == r, 0);
}
