module v3_core_move::config;

use sui::event;
use sui::vec_map::{Self, VecMap};
use v3_core_move::acl::{Self, ACL};

// Constants
const VERSION: u64 = 1;

// Roles
const ACL_POOL_MANAGER: u8 = 0;
const ACL_FEE_TICK_SPACING: u8 = 1;
const ACL_PROTOCOL_FEE_RATE: u8 = 2;
const ACL_CLAIM_PROTOCOL_FEE: u8 = 3;

// Errors
#[error]
const E_NO_POOL_MANAGER_ROLE: vector<u8> = b"No pool manager role";
#[error]
const E_NO_FEE_TICK_SPACING_ROLE: vector<u8> = b"No fee tick spacing role";
#[error]
const E_NO_PROTOCOL_FEE_RATE_ROLE: vector<u8> = b"No protocol fee rate role";
#[error]
const E_NO_CLAIM_PROTOCOL_FEE_ROLE: vector<u8> = b"No claim protocol fee role";
#[error]
const E_NOT_SUPPORT_VERSION: vector<u8> = b"Not support package version";
#[error]
const E_FEE_RATE_TOO_LARGE: vector<u8> = b"Fee rate too large";
#[error]
const E_TICK_SPACING_RANGE: vector<u8> = b"Tick spacing range error";
#[error]
const E_FEE_RATE_EXIST: vector<u8> = b"Fee rate already exists";
#[error]
const E_FEE_RATE_NOT_EXIST: vector<u8> = b"Fee rate not exists";
#[error]
const E_PROTOCOL_FEE_RATE_RANGE: vector<u8> = b"Protocol fee rate range error";

// Structs
public struct AdminCap has key, store {
    id: UID,
}

public struct Config has key, store {
    id: UID,
    acl: ACL,
    protocole_fee_rate: u8,
    fee_tick_spacing: VecMap<u64, u32>,
    package_version: u64,
}

// Events

public struct InitEvent has copy, drop {
    config_id: ID,
    admin_cap_id: ID,
}

public struct UpdateFeeAmountEvent has copy, drop {
    operator: address,
    fee: u64,
    tick_spacing: u32,
    add: bool,
}

public struct UpdateDefaultProtocolFeeRateEvent has copy, drop {
    operator: address,
    old_protocol_fee_rate: u8,
    new_protocol_fee_rate: u8,
}

fun init(ctx: &mut TxContext) {
    let mut config = Config {
        id: object::new(ctx),
        acl: acl::new(),
        protocole_fee_rate: 0,
        fee_tick_spacing: vec_map::empty(),
        package_version: VERSION,
    };

    // init fee_tick_spacing fee->tick_spacing
    config.fee_tick_spacing.insert(100, 2);
    config.fee_tick_spacing.insert(500, 10);
    config.fee_tick_spacing.insert(2500, 60);
    config.fee_tick_spacing.insert(10000, 200);

    // init roles

    config
        .acl
        .set_roles(
            ctx.sender(),
            0 | 1 << ACL_POOL_MANAGER | 1 << ACL_FEE_TICK_SPACING | 1 << ACL_PROTOCOL_FEE_RATE | 1 << ACL_CLAIM_PROTOCOL_FEE,
        );

    let admin_cap = AdminCap {
        id: object::new(ctx),
    };

    let init_event = InitEvent {
        config_id: object::id(&config),
        admin_cap_id: object::id(&admin_cap),
    };

    transfer::transfer(admin_cap, ctx.sender());
    transfer::share_object(config);

    event::emit(init_event);
}

public fun enable_fee_amount(self: &mut Config, fee: u64, tick_spacing: u32, ctx: &mut TxContext) {
    self.check_acl_fee_tick_spacing_role(ctx.sender());
    assert!(fee < 1000000, E_FEE_RATE_TOO_LARGE);
    assert!(tick_spacing > 0 && tick_spacing < 8192, E_TICK_SPACING_RANGE);
    assert!(!self.fee_tick_spacing.contains(&fee), E_FEE_RATE_EXIST);
    self.fee_tick_spacing.insert(fee, tick_spacing);

    let update_event = UpdateFeeAmountEvent {
        operator: ctx.sender(),
        fee: fee,
        tick_spacing: tick_spacing,
        add: true,
    };
    event::emit(update_event);
}

public fun disable_fee_amount(self: &mut Config, fee: u64, ctx: &mut TxContext) {
    self.check_acl_fee_tick_spacing_role(ctx.sender());
    assert!(fee < 1000000, E_FEE_RATE_TOO_LARGE);
    assert!(self.fee_tick_spacing.contains(&fee), E_FEE_RATE_NOT_EXIST);
    let (_, tick_sapcing) = self.fee_tick_spacing.remove(&fee);
    let update_event = UpdateFeeAmountEvent {
        operator: ctx.sender(),
        fee: fee,
        tick_spacing: tick_sapcing,
        add: false,
    };
    event::emit(update_event);
}

public fun set_protocol_fee_rate(
    self: &mut Config,
    fee_protocol_rate0: u8,
    fee_protocol_rate1: u8,
    ctx: &mut TxContext,
) {
    self.check_acl_protocol_fee_rate_role(ctx.sender());
    assert!(
        (fee_protocol_rate0 == 0 || (fee_protocol_rate0 >= 4 && fee_protocol_rate0 <= 10)) &&
        (fee_protocol_rate1 == 0 || (fee_protocol_rate1 >= 4 && fee_protocol_rate1 <= 10)),
        E_PROTOCOL_FEE_RATE_RANGE,
    );
    let old_protocol_fee_rate = self.protocole_fee_rate;
    self.protocole_fee_rate = fee_protocol_rate0 + (fee_protocol_rate1 << 4);
    let update_event = UpdateDefaultProtocolFeeRateEvent {
        operator: ctx.sender(),
        old_protocol_fee_rate: old_protocol_fee_rate,
        new_protocol_fee_rate: self.protocole_fee_rate,
    };
    event::emit(update_event);
}

public fun protocol_fee_rate(self: &Config): u8 {
    self.protocole_fee_rate
}

public fun fee_tick_spacing(self: &Config, fee: u64): u32 {
    assert!(fee < 1000000, E_FEE_RATE_TOO_LARGE);
    assert!(self.fee_tick_spacing.contains(&fee), E_FEE_RATE_NOT_EXIST);
    *self.fee_tick_spacing.get(&fee)
}

public fun set_roles(self: &mut Config, _: &AdminCap, member: address, roles: u128) {
    self.check_package_version();
    self.acl.set_roles(member, roles);
}

public fun add_role(self: &mut Config, _: &AdminCap, member: address, role: u8) {
    self.check_package_version();
    self.acl.add_role(member, role);
}

public fun remove_role(self: &mut Config, _: &AdminCap, member: address, role: u8) {
    self.check_package_version();
    self.acl.remove_role(member, role);
}

public fun remove_member(self: &mut Config, _: &AdminCap, member: address) {
    self.check_package_version();
    self.acl.remove_member(member);
}

public fun check_acl_pool_manager_role(self: &Config, member: address) {
    assert!(self.acl.has_role(member, ACL_POOL_MANAGER), E_NO_POOL_MANAGER_ROLE);
}

public fun check_acl_fee_tick_spacing_role(self: &Config, member: address) {
    assert!(self.acl.has_role(member, ACL_FEE_TICK_SPACING), E_NO_FEE_TICK_SPACING_ROLE);
}

public fun check_acl_protocol_fee_rate_role(self: &Config, member: address) {
    assert!(self.acl.has_role(member, ACL_PROTOCOL_FEE_RATE), E_NO_PROTOCOL_FEE_RATE_ROLE);
}

public fun check_acl_claim_protocol_fee_role(self: &Config, member: address) {
    assert!(self.acl.has_role(member, ACL_CLAIM_PROTOCOL_FEE), E_NO_CLAIM_PROTOCOL_FEE_ROLE);
}

public fun update_package_version(self: &mut Config, _: &AdminCap, version: u64) {
    assert!(version > self.package_version, 0);
    self.package_version = version;
}

public fun check_package_version(self: &Config) {
    assert!(VERSION >= self.package_version, E_NOT_SUPPORT_VERSION);
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}
