module v3_core_move::i16;

const EOverflow: u64 = 0;

const MIN_AS_U16: u16 = 1 << 15;
const MAX_AS_U16: u16 = 0x7fff;

const LT: u8 = 0;
const EQ: u8 = 1;
const GT: u8 = 2;

public struct I16 has copy, drop, store {
    bits: u16,
}

public fun zero(): I16 {
    I16 { bits: 0 }
}

public fun from_u16(bits: u16): I16 {
    I16 { bits: bits }
}

public fun from(v: u16): I16 {
    assert!(v <= MAX_AS_U16, EOverflow);
    I16 { bits: v }
}

public fun neg_from(v: u16): I16 {
    assert!(v <= MIN_AS_U16, EOverflow);
    if (v == 0) {
        I16 { bits: v }
    } else {
        I16 { bits: (u16_neg(v)+ 1) | (1 << 15) }
    }
}

public fun wrapping_add(num1: I16, num2: I16): I16 {
    let mut sum = num1.bits + num2.bits;
    let mut carry = (num1.bits ^ num2.bits ^ sum);
    while (carry != 0) {
        let a = sum;
        let b = carry;
        sum = a ^ b;
        carry = (a & b) << 1;
    };
    I16 { bits: sum }
}

public fun add(num1: I16, num2: I16): I16 {
    let sum = wrapping_add(num1, num2);
    let overflow =
        (sign(num1) & sign(num2) & u8_neg(sign(sum))) + 
    (u8_neg(sign(num1)) & u8_neg(sign(num2)) & sign(sum));
    assert!(overflow == 0, EOverflow);
    sum
}

public fun wrapping_sub(num1: I16, num2: I16): I16 {
    let sub_num = wrapping_add(
        I16 { bits: u16_neg(num2.bits) },
        from(1),
    );
    wrapping_add(num1, sub_num)
}

public fun sub(num1: I16, num2: I16): I16 {
    let sub_num = wrapping_add(
        I16 { bits: u16_neg(num2.bits) },
        from(1),
    );
    add(num1, sub_num)
}

public fun mul(num1: I16, num2: I16): I16 {
    let product = abs_u16(num1) * abs_u16(num2);
    if (sign(num1) != sign(num2)) {
        neg_from(product)
    } else {
        from(product)
    }
}

public fun div(num1: I16, num2: I16): I16 {
    let result = abs_u16(num1) / abs_u16(num2);
    if (sign(num1) != sign(num2)) {
        neg_from(result)
    } else {
        from(result)
    }
}

public fun abs(v: I16): I16 {
    if (sign(v) == 0) {
        v
    } else {
        assert!(v.bits > MIN_AS_U16, EOverflow);
        I16 { bits: u16_neg(v.bits - 1) }
    }
}

public fun abs_u16(v: I16): u16 {
    if (sign(v) == 0) {
        v.bits
    } else {
        u16_neg(v.bits - 1)
    }
}

public fun shl(v: I16, shift: u8): I16 {
    I16 { bits: v.bits << shift }
}

public fun shr(v: I16, shift: u8): I16 {
    if (shift == 0) {
        return v
    };
    let mask = 0xffff >> (15 - shift);
    if (sign(v) == 1) {
        I16 { bits: (v.bits >> shift)  | mask }
    } else {
        I16 { bits: (v.bits >> shift) }
    }
}

public fun mod(v: I16, n: I16): I16 {
    if (sign(v) == 1) {
        neg_from((abs_u16(v) % abs_u16(n)))
    } else {
        from((abs_u16(v) % abs_u16(n)))
    }
}

public fun as_u16(v: I16): u16 {
    v.bits
}

public fun sign(v: I16): u8 {
    ((v.bits >> 15) as u8)
}

public fun cmp(num1: I16, num2: I16): u8 {
    if (num1.bits == num2.bits) return EQ;
    if (sign(num1) > sign(num2)) return LT;
    if (sign(num1) < sign(num2)) return GT;
    if (num1.bits > num2.bits) {
        GT
    } else {
        LT
    }
}

public fun eq(num1: I16, num2: I16): bool {
    num1.bits == num2.bits
}

public fun gt(num1: I16, num2: I16): bool {
    cmp(num1, num2) == GT
}

public fun gte(num1: I16, num2: I16): bool {
    cmp(num1, num2) >= EQ
}

public fun lt(num1: I16, num2: I16): bool {
    cmp(num1, num2) == LT
}

public fun lte(num1: I16, num2: I16): bool {
    cmp(num1, num2) <= EQ
}

public fun or(num1: I16, num2: I16): I16 {
    I16 { bits: num1.bits | num2.bits }
}

public fun and(num1: I16, num2: I16): I16 {
    I16 { bits: num1.bits & num2.bits }
}

public fun is_neg(v: I16): bool {
    sign(v) == 1
}

fun u16_neg(v: u16): u16 {
    v ^ 0xffff
}

fun u8_neg(v: u8): u8 {
    v ^ 0xff
}

#[test]
fun test_from_ok() {
    assert!(as_u16(from(0)) == 0, 0);
    assert!(as_u16(from(10)) == 10, 1);
}

#[test]
#[expected_failure]
fun test_from_overflow() {
    as_u16(from(MIN_AS_U16));
    as_u16(from(0xffff));
}

#[test]
fun test_neg_from() {
    assert!(as_u16(neg_from(0)) == 0, 0);
    assert!(as_u16(neg_from(1)) == 0xffff, 1);
    assert!(as_u16(neg_from(0x7fff)) == 0x8001, 2);
    assert!(as_u16(neg_from(MIN_AS_U16)) == MIN_AS_U16, 2)
}

#[test]
#[expected_failure]
fun test_neg_from_overflow() {
    neg_from(0x8001);
}

#[test]
fun test_abs() {
    assert!(as_u16(from(10)) == 10u16, 0);
    assert!(as_u16(abs(neg_from(10))) == 10u16, 1);
    assert!(as_u16(abs(neg_from(0))) == 0u16, 2);
    assert!(as_u16(abs(neg_from(0x7fff))) == 0x7fff, 3);
    assert!(as_u16(neg_from(MIN_AS_U16)) == MIN_AS_U16, 4);
}
