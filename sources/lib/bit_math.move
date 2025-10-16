module v3_core_move::bit_math;

use std::u16;
use std::u32;
use std::u64;
use std::u8;

// ============ Errors ============
#[error]
const E_MUST_GT_ZERO: vector<u8> = b"Must be greater than zero";

public fun most_significant_bit(mut x: u128): (u8) {
    assert!(x > 0, E_MUST_GT_ZERO);

    // 这里采用的是二分法来查找最高位
    // 思路：现在有一个值是 104(001101000)
    // 我们从大往小进行
    // 第一步：比较 2^8，小于，则最高位小于8
    // 第二步：比较 2^4，大于，则最高位大于4，同时往右移4位(00110)
    // 第三步：比较 2^2，大于，则最高位大于2（4+2因为上面已经大于了4），同时往右移动2位(001)
    // 第四步：比较 2^1，小于，则最高位小于1
    // 这样就找了当前x的最高位为6(bits位，也就是2^6)

    let mut r: u8 = 0;
    // 判断是大于2^64，如果大于表示最少的高位64,同时右移64位
    if (x >= 0x10000000000000000) {
        x = x >>64;
        r = r+ 64;
    };

    if (x >= 0x100000000) {
        x = x >> 32;
        r = r + 32;
    };
    if (x >= 0x10000) {
        x = x>>16;
        r = r+ 16;
    };
    if (x >= 0x100) {
        x = x >> 8;
        r = r+ 8;
    };
    if (x >= 0x10) {
        x = x>> 4;
        r = r + 4;
    };
    if (x >= 0x4) {
        x = x>> 2;
        r = r+ 2;
    };
    if (x >= 0x2) r = r+ 1;
    r
}

public fun least_significant_bit(mut x: u128): (u8) {
    assert!(x > 0, E_MUST_GT_ZERO);

    // 查找最低位，则是通过判断低位是否有值来处理
    // 同样采用二分法，逐步递进

    // 判断低64位中bit位有为1的
    // 其实就是与低64全1，如果有1，则大于0表示低64位有值，
    // 等于0表示低64位没有值，所以右移64位，来处理高64位

    // u128.max = 2^128 - 1

    let mut r: u8 = 127;

    // type(uint64).max = 2^64- 1
    if (x & (u64::max_value!() as u128) > 0) {
        // 判断低64位是否有值
        // 有值，表示低位64位有值
        r = r - 64
    } else {
        // 表示低64位中bit没有为1的
        // 所有移动到高64位
        x = x >> 64;
    };

    // 2^32-1
    if (x & (u32::max_value!() as u128) > 0) {
        r = r - 32;
    } else {
        x = x >> 32;
    };

    // 2^16 -1
    if (x & (u16::max_value!() as u128) > 0) {
        r = r - 16;
    } else {
        x = x >> 16;
    };

    // 2^8 - 1
    if (x & (u8::max_value!() as u128) > 0) {
        r = r - 8;
    } else {
        x = x >> 8;
    };

    // 2^4 - 1
    if (x & 0xf > 0) {
        r = r - 4;
    } else {
        x = x >> 4;
    };

    // 2^2 - 1
    if (x & 0x3 > 0) {
        r = r - 2;
    } else {
        x = x >> 2;
    };

    // 2 - 1
    if (x & 0x1 > 0) {
        r = r - 1;
    };

    r
}
