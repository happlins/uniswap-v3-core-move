module v3_core_move::acl;

use sui::vec_map::{Self, VecMap};

public struct ACL has store {
    permissions: VecMap<address, u128>,
}

public struct Member has copy, drop, store {
    address: address,
    permission: u128,
}

/// @notice Create a new ACL (access control list).
public fun new(): ACL {
    ACL { permissions: vec_map::empty<address, u128>() }
}

/// @notice Check if a member has a role in the ACL.
public fun has_role(self: &ACL, member: address, role: u8): bool {
    assert!(role < 128, 0);
    self.permissions.contains(&member) &&
        self.permissions[&member] & (1 << role) > 0
}

/// @notice Set all roles for a member in the ACL.
/// @param permissions Permissions for a member, represented as a `u128` with each bit representing the presence of (or lack of) each role.
public fun set_roles(self: &mut ACL, member: address, permissions: u128) {
    if (self.permissions.contains(&member)) {
        *&mut self.permissions[&member] = permissions
    } else {
        self.permissions.insert(member, permissions)
    }
}

/// @notice Add a role for a member in the ACL.
public fun add_role(self: &mut ACL, member: address, role: u8) {
    assert!(role < 128, 0);
    if (self.permissions.contains(&member)) {
        *&mut self.permissions[&member] = self.permissions[&member] | 1 << role
    } else {
        self.permissions.insert(member, 1 << role);
    };
}

/// @notice Revoke a role for a member in the ACL.
public fun remove_role(self: &mut ACL, member: address, role: u8) {
    assert!(role < 128, 0);
    if (self.permissions.contains(&member)) {
        *&mut self.permissions[&member] = self.permissions[&member] - (1 << role)
    }
}

/// Remove all roles of member.
public fun remove_member(self: &mut ACL, member: address) {
    if (self.permissions.contains(&member)) {
        (_, _) = self.permissions.remove(&member)
    }
}

/// Get all members.
public fun get_members(self: &ACL): vector<Member> {
    let mut result = vector::empty<Member>();
    let accounts = self.permissions.keys();
    let mut i = 0;
    while (i < accounts.length()) {
        let permission = self.permissions[&accounts[i]];
        let member = Member {
            `address`: accounts[i],
            permission,
        };
        result.push_back(member);
        i = i + 1;
    };
    result
}

/// Get all address by role.
public fun get_address(self: &ACL, role: u8): vector<address> {
    let mut result = vector::empty<address>();
    let accounts = self.permissions.keys();
    let mut i = 0;
    while (i < accounts.length()) {
        let permission = self.permissions[&accounts[i]];
        if (permission & (1 << role) > 0) {
            result.push_back(accounts[i]);
        };
        i = i + 1;
    };
    result
}

/// Get the permission of member by addresss.
public fun get_permission(self: &ACL, account: address): u128 {
    self.permissions[&account]
}
