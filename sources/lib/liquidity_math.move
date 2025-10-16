module v3_core_move::liquidity_math;

use v3_core_move::i128::I128;

// ============ Errors ============

#[error]
const E_LS: vector<u8> = b"LS";
#[error]
const E_LA: vector<u8> = b"LA";

public fun add_delta(x: u128, y: I128): u128 {
    if (y.is_neg()) {
        let z = x - y.abs_u128();
        assert!(z < x, E_LS);
        z
    } else {
        let z = x + y.abs_u128();
        assert!(z >= x, E_LA);
        z
    }
}
