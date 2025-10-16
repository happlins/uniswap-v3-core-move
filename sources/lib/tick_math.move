module v3_core_move::tick_math;

use std::u128;
use v3_core_move::full_math_u128::mul_shr;
use v3_core_move::i128;
use v3_core_move::i32::{Self, I32};

// ============ Constants ============
const TICK_BOUND: u32 = 443636;
const MAX_SQRT_PRICE_X64: u128 = 79226673521066979257578248091;
const MIN_SQRT_PRICE_X64: u128 = 4295048016;

public fun max_sqrt_price_x64(): u128 {
    MAX_SQRT_PRICE_X64
}

public fun min_sqrt_price_x64(): u128 {
    MIN_SQRT_PRICE_X64
}

public fun max_tick(): I32 {
    i32::from(443636)
}

public fun min_tick(): I32 {
    i32::neg_from(443636)
}

public fun get_sqrt_ratio_at_tick(tick: I32): u128 {
    // 先转换为绝对值
    let abs_tick = tick.abs().as_u32();

    // 必须满足 -443636 <= tick <= 443636，也就是价格必须要在[2^-64,2^64]
    assert!(abs_tick <= TICK_BOUND, 0);

    let mut ratio: u128 = if (abs_tick & 0x1 != 0) {
        // (1/sqrt(1.0001)^1) * 2^64
        // new Decimal(1).div(Decimal.sqrt(1.0001)).mul(new Decimal(2).pow(64)).toFixed(0)
        18445821805675392311
    } else {
        // 1 * 2^64
        18446744073709551616
    };

    // 检查第2位 （2^1 = 2），对应 （1/sqrt(1.0001)^2） * 2 ^ 64
    if (abs_tick & 0x2 != 0) {
        ratio = mul_shr(ratio, 18444899583751176498u128, 64u8)
    };
    // 检查第3位 (2^2 = 4）,对应 （1/sqrt(1.0001)^4） * 2 ^ 64
    if (abs_tick & 0x4 != 0) {
        ratio = mul_shr(ratio, 18443055278223354162u128, 64u8);
    };
    // 检查第4位 (2^3 = 8）,对应 （1/sqrt(1.0001)^8） * 2 ^ 64)
    if (abs_tick & 0x8 != 0) {
        ratio = mul_shr(ratio, 18439367220385604838u128, 64u8);
    };
    // 检查第5位 (2^4 = 16），对应 （1/sqrt(1.0001)^16） * 2 ^ 64
    if (abs_tick & 0x10 != 0) {
        ratio = mul_shr(ratio, 18431993317065449817u128, 64u8);
    };
    // 检查第6位 (2^5 = 32），对应 （1/sqrt(1.0001)^32） * 2 ^ 64
    if (abs_tick & 0x20 != 0) {
        ratio = mul_shr(ratio, 18417254355718160513u128, 64u8);
    };
    // 检查第7位 (2^6 = 64），对应 （1/sqrt(1.0001)^64） * 2 ^ 64
    if (abs_tick & 0x40 != 0) {
        ratio = mul_shr(ratio, 18387811781193591352u128, 64u8);
    };
    // 检查第8位 (2^7 = 128），对应 （1/sqrt(1.0001)^128） * 2 ^ 64)
    if (abs_tick & 0x80 != 0) {
        ratio = mul_shr(ratio, 18329067761203520168u128, 64u8);
    };
    // 检查第9位 (2^8 = 256），对应 （1/sqrt(1.0001)^256） * 2 ^ 64)
    if (abs_tick & 0x100 != 0) {
        ratio = mul_shr(ratio, 18212142134806087854u128, 64u8);
    };
    // 检查第10位 (2^9 = 512），对应 （1/sqrt(1.0001)^512） * 2 ^ 64)
    if (abs_tick & 0x200 != 0) {
        ratio = mul_shr(ratio, 17980523815641551639u128, 64u8);
    };
    // 检查第11位 (2^10 = 1024），对应 （1/sqrt(1.0001)^1024） * 2 ^ 64)
    if (abs_tick & 0x400 != 0) {
        ratio = mul_shr(ratio, 17526086738831147013u128, 64u8);
    };
    // 检查第12位 (2^11 = 2048），对应 （1/sqrt(1.0001)^2048） * 2 ^ 64
    if (abs_tick & 0x800 != 0) {
        ratio = mul_shr(ratio, 16651378430235024244u128, 64u8);
    };
    // 检查第13位 (2^12 = 4096），对应 （1/sqrt(1.0001)^4096） * 2 ^ 64
    if (abs_tick & 0x1000 != 0) {
        ratio = mul_shr(ratio, 15030750278693429944u128, 64u8);
    };
    // 检查第14位 (2^13 = 8192），对应 （1/sqrt(1.0001)^8192） * 2 ^ 64)
    if (abs_tick & 0x2000 != 0) {
        ratio = mul_shr(ratio, 12247334978882834399u128, 64u8);
    };
    // 检查第15位 (2^14 = 16384），对应 （1/sqrt(1.0001)^16384） * 2 ^ 64
    if (abs_tick & 0x4000 != 0) {
        ratio = mul_shr(ratio, 8131365268884726200u128, 64u8);
    };
    // 检查第16位 (2^15 = 32768），对应 （1/sqrt(1.0001)^32768） * 2 ^ 64)
    if (abs_tick & 0x8000 != 0) {
        ratio = mul_shr(ratio, 3584323654723342297u128, 64u8);
    };
    // 检查第17位 (2^16 = 32768），对应 （1/sqrt(1.0001)^32768） * 2 ^ 64)
    if (abs_tick & 0x10000 != 0) {
        ratio = mul_shr(ratio, 696457651847595233u128, 64u8);
    };
    // 检查第18位 (2^17 = 65536），对应 （1/sqrt(1.0001)^65536） * 2 ^ 64)
    if (abs_tick & 0x20000 != 0) {
        ratio = mul_shr(ratio, 26294789957452057u128, 64u8);
    };
    // 检查第18位 (2^18 = 131072），对应 （1/sqrt(1.0001)^131072） * 2 ^ 64)
    if (abs_tick & 0x40000 != 0) {
        ratio = mul_shr(ratio, 37481735321082u128, 64u8);
    };

    // (2 ^ 64 / ratio) * 2 ^ 64

    // 最后如果，tick是正数，我们需要在计算的结尾计算 sqrt P_{i} = 1 / sqrt P_{-i}
    // 因为ratio是Q64.64值，所有需要先乘2^64将分母的2^64去掉，然后在乘2^64转为Q64.64
    // (2 ^ 64 / ratio ) * 2 ^ 64 ==> 2 ^ 128/ ratio
    // type(uint128).max == 1<< 128
    if (!tick.is_neg()) {
        ratio = u128::max_value!() / ratio;
    };

    ratio
}

public fun get_tick_at_sqrt_ratio(sqrt_price_x64: u128): I32 {
    assert!(sqrt_price_x64>= MIN_SQRT_PRICE_X64&& sqrt_price_x64 < MAX_SQRT_PRICE_X64, 0);

    // 因为sqrt是u128，所以从64(2^6)位开始开始

    let mut r: u128 = sqrt_price_x64;
    let mut msb: u8 = 0;

    // f表示64位
    // 判断当前价格是否大于2^64
    let mut f = shl(gt_as_u8(r, 0x10000000000000000), 6);
    // 把 f 写入 msb（按位或）。因为 f 只可能是 0 或 64（即一个“单一的二次幂”），
    // or 实际效果等价于 msb += f（因为 f 的二进制位与现有已设位不会重叠）。
    // 相当于msb+64
    msb = msb | f;
    // 然后将当前的值右，移动对应的位数（64）
    // 相当于r / 2^64
    r = r >> f;

    // f表示32位
    f = shl(gt_as_u8(r, 0x100000000), 5);
    msb = msb | f;
    r = r >> f;

    // f表示16
    f = shl(gt_as_u8(r, 0x10000), 4);
    msb = msb | f;
    r = r >> f;

    // 8
    f = shl(gt_as_u8(r, 0x100), 3);
    msb = msb | f;
    r = r >> f;

    // 4
    f = shl(gt_as_u8(r, 0x10), 2);
    msb = msb | f;
    r = r >> f;

    // 2
    f = shl(gt_as_u8(r, 0x4), 1);
    msb = msb | f;
    r = r >> f;

    // 1
    f = shl(gt_as_u8(r, 0x2), 0);
    msb = msb | f;

    // 调整r值到[1,2)范围

    // 根据 log_2(x/2^n)

    // 问：不知道为什么是63
    // 答：因为在下面会执行平方，因此小数位63+63 = 126，整数位为2位bit
    // 不然是64的话，64+64=128，这样整数位就被溢出了
    // 因此小数位就是63位

    // x/2^n
    // ratio = ratio >> msb ,ratio << 63

    // msb >= 63,因此 ratio >> (msb - 63)
    r = if (msb >= 64) {
        sqrt_price_x64 >> (msb - 63)
    } else {
        // msb < 64，因此 ratio << (63- msb)
        sqrt_price_x64 << (63 - msb)
    };

    // log_2(m * 2^e) = log_2(m) + e
    // 这里m是[1,2)，所以e一定是加了64的
    // 这里时用x32，因为msb是x64的，所以需要先减去64，得到真实的整数部分
    // 当然可能为负数
    let mut log_2_x32 = i128::shl(i128::sub(i128::from(msb as u128), i128::from(64)), 32);

    let mut shift = 31;

    // 所以  1 <= r*r < 4
    while (shift >= 18) {
        r = ((r * r) >> 63);
        f = ((r >> 64) as u8);
        log_2_x32 = i128::or(log_2_x32, i128::shl(i128::from((f as u128)), shift));
        r = r >> f;
        shift = shift - 1;
    };

    //  log_sqrt1.0001(2)<<32 = 59543866431366u128
    // Decimal.log(2,new Decimal(1.0001).sqrt()).mul(new Decimal(2).pow(32)).toFixed(0)
    let log_sqrt_10001 = i128::mul(log_2_x32, i128::from(59543866431366u128));

    // tick - 0.01
    // new Decimal(0.01).mul(new Decimal(2).pow(64)).toFixed(0)
    let tick_low = i128::as_i32(
        i128::shr(i128::sub(log_sqrt_10001, i128::from(184467440737095516u128)), 64),
    );
    // tick + (2^-14 / log2(√1.0001)) + 0.01
    // new Decimal(2).pow(-14).div(Decimal.log2(new Decimal(1.0001).sqrt())).plus(0.01).mul(new Decimal(2).pow(64)).toFixed(0)
    let tick_high = i128::as_i32(
        i128::shr(i128::add(log_sqrt_10001, i128::from(15793534762490258745u128)), 64),
    );

    // 即为此对数结果附近的两个 tick index，
    // 最后使用 tick index 反向计算出 sqrt(p) 并与输入比较验证，
    // 得出最近的 tick index，并且满足此 tick index 对应的
    if (i32::eq(tick_low, tick_high)) {
        tick_low
    } else if (get_sqrt_ratio_at_tick(tick_high) <= sqrt_price_x64) {
        tick_high
    } else {
        tick_low
    }
}

fun shl(value: u8, shift: u8): u8 {
    value << shift
}

fun gt_as_u8(a: u128, b: u128): u8 {
    if (a >= b) {
        1
    } else {
        0
    }
}

#[test]
fun test_get_sqrt_ration_at_tick() {
    let sqrt_price_x64 = get_sqrt_ratio_at_tick(i32::from(0));
    let _tick = get_tick_at_sqrt_ratio(sqrt_price_x64);

    let _max_sqrt_price_x64 = get_sqrt_ratio_at_tick(i32::from(TICK_BOUND));
    let _min_sqrt_price_x64 = get_sqrt_ratio_at_tick(i32::neg_from(TICK_BOUND));
}
