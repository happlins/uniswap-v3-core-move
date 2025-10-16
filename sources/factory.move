module v3_core_move::factory;

use std::bcs;
use std::type_name::{Self, TypeName};
use sui::event;
use sui::hash;
use sui::table::{Self, Table};
use v3_core_move::config::Config;
use v3_core_move::i32;
use v3_core_move::pool;

#[error]
const E_SAME_COIN_TYPE: vector<u8> = b"same coin type";
#[error]
const E_INVALID_COIN_TYPE_SEQUENCE: vector<u8> = b"invalid coin type sequence";
// pool已存在
#[error]
const E_POOL_EXISTS: vector<u8> = b"pool exists";

public struct PoolSimpleInfo has copy, drop, store {
    pool_id: ID,
    pool_key: ID,
    coin_type_a: TypeName,
    coin_type_b: TypeName,
    tick_spacing: u32,
}

public struct Factory has key, store {
    id: UID,
    pools: Table<ID, PoolSimpleInfo>,
}

// Events

public struct InitEvent has copy, drop {
    factory_id: ID,
}

public struct CreatePoolEvent has copy, drop {
    pool_id: ID,
    pool_key: ID,
    coin_type_a: TypeName,
    coin_type_b: TypeName,
    fee_rate: u64,
    tick_spacing: u32,
}

fun init(ctx: &mut TxContext) {
    let factory = Factory {
        id: object::new(ctx),
        pools: table::new(ctx),
    };
    let init_event = InitEvent {
        factory_id: object::id(&factory),
    };
    transfer::share_object(factory);
    event::emit(init_event);
}

#[allow(lint(share_owned))]
public fun create_pool<CoinA, CoinB>(
    self: &mut Factory,
    config: &Config,
    init_sqrt_price: u128,
    fee_rate: u64,
    ctx: &mut TxContext,
) {
    config.check_package_version();
    let tick_spacing = config.fee_tick_spacing(fee_rate);
    let pool_key = new_pool_key<CoinA, CoinB>(tick_spacing);
    assert!(!self.pools.contains(pool_key), E_POOL_EXISTS);

    let pool = pool::new<CoinA, CoinB>(
        init_sqrt_price,
        i32::from(tick_spacing),
        fee_rate,
        config.protocol_fee_rate(),
        ctx,
    );

    let pool_info = PoolSimpleInfo {
        pool_id: object::id(&pool),
        pool_key,
        coin_type_a: type_name::with_defining_ids<CoinA>(),
        coin_type_b: type_name::with_defining_ids<CoinB>(),
        tick_spacing,
    };

    let create_pool_event = CreatePoolEvent {
        pool_id: object::id(&pool),
        pool_key,
        coin_type_a: type_name::with_defining_ids<CoinA>(),
        coin_type_b: type_name::with_defining_ids<CoinB>(),
        fee_rate,
        tick_spacing,
    };

    self.pools.add(pool_key, pool_info);
    transfer::public_share_object(pool);

    event::emit(create_pool_event);
}

public fun new_pool_key<CoinA, CoinB>(tick_spacing: u32): ID {
    let mut coinAByte = *type_name::with_defining_ids<CoinA>().into_string().as_bytes();
    let coinBByte = *type_name::with_defining_ids<CoinB>().into_string().as_bytes();

    let typeALength = coinAByte.length();
    let typeBLength = coinBByte.length();
    let mut complete = false;

    typeBLength.do!(|index| {
        let bAscii = coinBByte[index];
        if (!complete && index < typeALength) {
            let aAscii = coinAByte[index];
            if (aAscii <  bAscii) {
                abort E_INVALID_COIN_TYPE_SEQUENCE
            };
            if (aAscii > bAscii) {
                complete = true;
            };
        };
        coinAByte.push_back(bAscii);
    });
    if (!complete) {
        if (typeALength < typeBLength) {
            abort E_INVALID_COIN_TYPE_SEQUENCE
        };
        if (typeALength == typeBLength) {
            abort E_SAME_COIN_TYPE
        };
    };

    coinAByte.append(bcs::to_bytes(&tick_spacing));
    object::id_from_bytes(hash::blake2b256(&coinAByte))
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}
