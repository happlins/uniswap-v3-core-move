module v3_core_move::swap_math;

use v3_core_move::full_math_u64;
use v3_core_move::i64::I64;
use v3_core_move::sqrt_price_math;

// ============ Constants ============
const FEE_RATE_DENOMINATOR: u64 = 1000000;

public fun compute_swap_step(
    sqrt_ratio_current_x64: u128,
    sqrt_ratio_target_x64: u128,
    liquidity: u128,
    amount_remaining: I64,
    fee_pips: u64,
): (u128, u64, u64, u64) {
    let sqrt_ratio_next_x64: u128;
    let mut amount_in: u64 = 0;
    let mut amount_out: u64 = 0;

    // 判断交换方向：true表示token0换token1（价格下降），false表示token1换token0（价格上升）
    let zero_for_one = sqrt_ratio_current_x64 > sqrt_ratio_target_x64;

    // 判断是否为精确输入模式：true表示指定输入金额，false表示指定输出金额
    let exact_in = !amount_remaining.is_neg();

    if (exact_in) {
        // 精确输入模式：扣除手续费后的实际可用输入金额
        // 在交易之前，先计算当价格移动到交易区间边界时，所需要的手续费
        // 即此步骤最多需要的手续费数额
        let amount_remaining_less_fee = full_math_u64::mul_div_floor(
            amount_remaining.abs_u64(),
            FEE_RATE_DENOMINATOR - fee_pips,
            FEE_RATE_DENOMINATOR,
        );
        // 计算达到目标价格所需的输入金额
        amount_in = if (zero_for_one) {
            sqrt_price_math::get_delta_amount0_unsigned(
                sqrt_ratio_target_x64,
                sqrt_ratio_current_x64,
                liquidity,
                true,
            )
        } else {
            sqrt_price_math::get_delta_amount1_unsigned(
                sqrt_ratio_current_x64,
                sqrt_ratio_target_x64,
                liquidity,
                true,
            )
        };

        // 表示在当前价格和流动性情况下，最大的amountIn不足以支付amountRemainingLessFee
        sqrt_ratio_next_x64 = if (amount_remaining_less_fee >= amount_in) {
            sqrt_ratio_target_x64
        } else {
            // 否则根据实际可用金额计算新价格
            sqrt_price_math::get_next_sqrt_price_from_input(
                sqrt_ratio_current_x64,
                liquidity,
                amount_remaining_less_fee,
                zero_for_one,
            )
        };
    } else {
        // 精确输出模式：计算达到目标价格能获得的输出金额
        amount_out = if (zero_for_one) {
            sqrt_price_math::get_delta_amount1_unsigned(
                sqrt_ratio_target_x64,
                sqrt_ratio_current_x64,
                liquidity,
                false,
            )
        } else {
            sqrt_price_math::get_delta_amount0_unsigned(
                sqrt_ratio_current_x64,
                sqrt_ratio_target_x64,
                liquidity,
                false,
            )
        };

        // 如果所需输出金额不超过剩余金额，则使用目标价格
        sqrt_ratio_next_x64 = if (amount_remaining.abs_u64() >= amount_out) {
            sqrt_ratio_target_x64
        } else {
            // 否则根据实际所需输出金额计算新价格
            sqrt_price_math::get_next_sqrt_price_from_output(
                sqrt_ratio_current_x64,
                liquidity,
                amount_remaining.abs_u64(),
                zero_for_one,
            )
        };
    };
    // 检查是否达到了目标价格（是否完全消耗了流动
    let max = sqrt_ratio_target_x64  == sqrt_ratio_next_x64;

    // 计算实际的输入/输出金额
    if (zero_for_one) {
        // token0换token1的情况
        amount_in = if (max && exact_in) {
            // 如果达到目标且为精确输入，使用之前计算的金额
            amount_in
        } else {
            sqrt_price_math::get_delta_amount0_unsigned(
                sqrt_ratio_next_x64,
                sqrt_ratio_current_x64,
                liquidity,
                true,
            )
        };
        amount_out = if (max && !exact_in) {
            // 如果达到目标且为精确输出，使用之前计算的金额
            amount_out
        } else {
            sqrt_price_math::get_delta_amount1_unsigned(
                sqrt_ratio_next_x64,
                sqrt_ratio_current_x64,
                liquidity,
                false,
            )
        };
    } else {
        // token1换token0的情况
        amount_in = if (max && exact_in) {
            amount_in
        } else {
            sqrt_price_math::get_delta_amount1_unsigned(
                sqrt_ratio_current_x64,
                sqrt_ratio_next_x64,
                liquidity,
                true,
            )
        };
        amount_out = if (max && !exact_in) {
            amount_out
        } else {
            sqrt_price_math::get_delta_amount0_unsigned(
                sqrt_ratio_current_x64,
                sqrt_ratio_next_x64,
                liquidity,
                false,
            )
        };
    };

    // 限制输出金额不超过剩余输出金额（仅适用于精确输出模式）
    if (!exact_in && amount_out > amount_remaining.abs_u64()) {
        amount_out = amount_remaining.abs_u64();
    };

    let fee_amount = if (exact_in && sqrt_ratio_next_x64 != sqrt_ratio_target_x64) {
        // 在精确输入模式下，如果没有达到目标价格，则将剩余的最大输入作为费用
        amount_remaining.abs_u64() - amount_in
    } else {
        // 否则根据输入金额和费率计算手续费（向上舍入）
        full_math_u64::mul_div_ceil(amount_in, fee_pips, FEE_RATE_DENOMINATOR - fee_pips)
    };

    (sqrt_ratio_next_x64, amount_in, amount_out, fee_amount)
}

#[test]
fun test_compute_swap_step() {
    use v3_core_move::i64;
    let (current_sqrt_price, target_sqrt_price, liquidity, amount, fee_rate) = (
        1u128 << 64,
        2u128 << 64,
        1000u128 << 32,
        20000,
        1000u64,
    );
    let (next_sqrt_price, amount_in, amount_out, fee_amount) = compute_swap_step(
        current_sqrt_price,
        target_sqrt_price,
        liquidity,
        i64::neg_from(amount),
        fee_rate,
    );
    assert!(amount_in == 20001, 0);
    assert!(amount_out == 20000, 0);
    assert!(next_sqrt_price == 18446744159608897937, 0);
    assert!(fee_amount == 21, 0);

    let (next_sqrt_price, amount_in, amount_out, fee_amount) = compute_swap_step(
        current_sqrt_price,
        target_sqrt_price,
        liquidity,
        i64::from(amount),
        fee_rate,
    );

    assert!(amount_in == 19980, 0);
    assert!(amount_out == 19979, 0);
    assert!(next_sqrt_price == 18446744159522998190, 0);
    assert!(fee_amount == 20, 0);
}
