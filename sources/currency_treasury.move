// Copyright (c) Unconfirmed Labs, LLC
// SPDX-License-Identifier: Apache-2.0

module hakkou::currency_treasury;

use std::type_name::{TypeName, with_defining_ids};
use sui::balance::{Self, Balance};
use sui::coin::{Coin, TreasuryCap};
use sui::event::emit;
use sui::transfer::Receiving;
use sui::vec_set::{Self, VecSet};

//=== Structs ===

/// Wraps a TreasuryCap to provide controlled minting and burning operations.
/// The treasury tracks which Authority types are permitted to mint.
public struct CurrencyTreasury<phantom Currency> has key, store {
    id: UID,
    /// The TreasuryCap wrapped by this CurrencyTreasury.
    treasury_cap: TreasuryCap<Currency>,
    /// Set of authorized mint authority types (stored as TypeName with defining IDs)
    mint_authorities: VecSet<TypeName>,
}

/// Capability granting admin control over a CurrencyTreasury.
/// Required to add/remove mint authorities and destroy the treasury.
public struct CurrencyTreasuryAdminCap<phantom Currency> has key, store {
    id: UID,
}

//=== Events ===

/// Emitted when a new CurrencyTreasury is created.
public struct CurrencyTreasuryCreatedEvent<phantom Currency> has copy, drop, store {
    treasury_id: ID,
}

/// Emitted when a CurrencyTreasury is destroyed and the TreasuryCap is returned.
public struct CurrencyTreasuryDestroyedEvent<phantom Currency> has copy, drop, store {
    treasury_id: ID,
}

/// Emitted when currency is burned through the treasury.
public struct CurrencyBurnedEvent<phantom Currency> has copy, drop, store {
    treasury_id: ID,
    value: u64,
    burned_by: address,
}

/// Emitted when currency is minted by an authorized authority.
public struct CurrencyMintedEvent<phantom Currency, phantom Authority: drop> has copy, drop, store {
    treasury_id: ID,
    value: u64,
    minted_by: address,
}

/// Emitted when a mint authority is added to the treasury.
public struct MintAuthorityAddedEvent<
    phantom Currency,
    phantom Authority: drop,
> has copy, drop, store {
    treasury_id: ID,
}

/// Emitted when a mint authority is removed from the treasury.
public struct MintAuthorityRemovedEvent<
    phantom Currency,
    phantom Authority: drop,
> has copy, drop, store {
    treasury_id: ID,
}

//=== Errors ===

/// The provided Authority type is not registered as a mint authority.
const EUnauthorizedMintAuthority: u64 = 0;
/// The coins_to_receive vector cannot be empty.
const ENoCoinsToReceive: u64 = 1;
/// The Authority type is already registered as a mint authority.
const EMintAuthorityAlreadyExists: u64 = 2;
/// The Authority type is not registered as a mint authority.
const EMintAuthorityNotFound: u64 = 3;

//=== Public Functions ===

/// Creates a new CurrencyTreasury by wrapping a TreasuryCap.
///
/// Returns the treasury and an admin capability. The admin cap is required
/// to add/remove mint authorities and to destroy the treasury.
///
/// Initially, no mint authorities are registered - they must be added
/// explicitly using `add_mint_authority`.
public fun new<Currency>(
    treasury_cap: TreasuryCap<Currency>,
    ctx: &mut TxContext,
): (CurrencyTreasury<Currency>, CurrencyTreasuryAdminCap<Currency>) {
    let currency_treasury = CurrencyTreasury {
        id: object::new(ctx),
        treasury_cap: treasury_cap,
        mint_authorities: vec_set::empty(),
    };

    let currency_treasury_admin_cap = CurrencyTreasuryAdminCap {
        id: object::new(ctx),
    };

    emit(CurrencyTreasuryCreatedEvent<Currency> {
        treasury_id: currency_treasury.id(),
    });

    (currency_treasury, currency_treasury_admin_cap)
}

/// Destroys the CurrencyTreasury and returns the underlying TreasuryCap.
///
/// Requires the admin capability, which is also consumed.
/// Any registered mint authorities are discarded.
public fun destroy<Currency>(
    self: CurrencyTreasury<Currency>,
    cap: CurrencyTreasuryAdminCap<Currency>,
): TreasuryCap<Currency> {
    let CurrencyTreasury { id, treasury_cap, .. } = self;

    emit(CurrencyTreasuryDestroyedEvent<Currency> {
        treasury_id: id.to_inner(),
    });

    id.delete();

    let CurrencyTreasuryAdminCap { id } = cap;
    id.delete();

    treasury_cap
}

/// Mints new currency using an authorized witness type.
///
/// The caller must provide a witness instance of the Authority type, proving
/// they control the module that defines it. The Authority must have been
/// previously registered via `add_mint_authority`.
///
/// # Aborts
///
/// Aborts with `EUnauthorizedMintAuthority` if the Authority type is not registered.
public fun mint<Currency, Authority: drop>(
    self: &mut CurrencyTreasury<Currency>,
    _: Authority,
    value: u64,
    ctx: &TxContext,
): Balance<Currency> {
    assert!(
        self.mint_authorities.contains(&with_defining_ids<Authority>()),
        EUnauthorizedMintAuthority,
    );

    emit(CurrencyMintedEvent<Currency, Authority> {
        treasury_id: self.id(),
        value,
        minted_by: ctx.sender(),
    });

    self.treasury_cap.mint_balance(value)
}

/// Registers a new mint authority type.
///
/// Once added, any caller that can produce an instance of the Authority type
/// can mint currency via `mint`.
///
/// Requires the admin capability.
///
/// # Aborts
///
/// Aborts with `EMintAuthorityAlreadyExists` if the Authority type is already registered.
public fun add_mint_authority<Currency, Authority: drop>(
    self: &mut CurrencyTreasury<Currency>,
    _: &CurrencyTreasuryAdminCap<Currency>,
) {
    let authority = with_defining_ids<Authority>();
    assert!(!self.mint_authorities.contains(&authority), EMintAuthorityAlreadyExists);

    self.mint_authorities.insert(authority);

    emit(MintAuthorityAddedEvent<Currency, Authority> {
        treasury_id: self.id(),
    });
}

/// Removes a mint authority type.
///
/// After removal, the Authority type can no longer be used to mint currency.
///
/// Requires the admin capability.
///
/// # Aborts
///
/// Aborts with `EMintAuthorityNotFound` if the Authority type is not registered.
public fun remove_mint_authority<Currency, Authority: drop>(
    self: &mut CurrencyTreasury<Currency>,
    _: &CurrencyTreasuryAdminCap<Currency>,
) {
    let authority = with_defining_ids<Authority>();
    assert!(self.mint_authorities.contains(&authority), EMintAuthorityNotFound);

    self.mint_authorities.remove(&authority);

    emit(MintAuthorityRemovedEvent<Currency, Authority> {
        treasury_id: self.id(),
    });
}

/// Burns a balance of currency.
public fun burn<Currency>(
    self: &mut CurrencyTreasury<Currency>,
    balance: Balance<Currency>,
    ctx: &TxContext,
) {
    burn_impl(self, balance, ctx);
}

/// Receives coins sent to the treasury's address and burns them immediately.
///
/// Anyone can send coins to the treasury address. The treasury owner then calls
/// this function to receive and burn those coins in a single transaction.
///
/// # Aborts
///
/// Aborts with `ENoCoinsToReceive` if `coins_to_receive` is empty.
public fun receive_and_burn<Currency>(
    self: &mut CurrencyTreasury<Currency>,
    coins_to_receive: vector<Receiving<Coin<Currency>>>,
    ctx: &TxContext,
) {
    assert!(!coins_to_receive.is_empty(), ENoCoinsToReceive);

    let mut total_balance = balance::zero<Currency>();

    coins_to_receive.destroy!(|coin_to_receive| {
        let balance = transfer::public_receive(&mut self.id, coin_to_receive).into_balance();
        total_balance.join(balance);
    });

    burn_impl(self, total_balance, ctx);
}

/// Redeems funds from balance accumulators and burns them immediately.
///
/// Withdraws the specified value from any balance accumulator funds held by
/// this treasury object, then burns the redeemed balance.
public fun redeem_and_burn<Currency>(
    self: &mut CurrencyTreasury<Currency>,
    value: u64,
    ctx: &TxContext,
) {
    let withdrawal = balance::withdraw_funds_from_object(&mut self.id, value);
    let balance = balance::redeem_funds(withdrawal);
    burn_impl(self, balance, ctx);
}

//=== Public View Functions ===

/// Returns the object ID of the treasury.
public fun id<Currency>(self: &CurrencyTreasury<Currency>): ID {
    self.id.to_inner()
}

/// Returns a reference to the set of mint authorities.
public fun mint_authorities<Currency>(self: &CurrencyTreasury<Currency>): &VecSet<TypeName> {
    &self.mint_authorities
}

/// Returns a read-only reference to the underlying TreasuryCap.
public fun treasury_cap<Currency>(self: &CurrencyTreasury<Currency>): &TreasuryCap<Currency> {
    &self.treasury_cap
}

/// Returns a mutable reference to the underlying TreasuryCap.
///
/// Requires the admin capability.
public fun treasury_cap_mut<Currency>(
    self: &mut CurrencyTreasury<Currency>,
    _: &CurrencyTreasuryAdminCap<Currency>,
): &mut TreasuryCap<Currency> {
    &mut self.treasury_cap
}

//=== Private Functions ===

fun burn_impl<Currency>(
    self: &mut CurrencyTreasury<Currency>,
    balance: Balance<Currency>,
    ctx: &TxContext,
) {
    if (balance.value() == 0) {
        balance.destroy_zero();
        return
    };

    emit(CurrencyBurnedEvent<Currency> {
        treasury_id: self.id(),
        value: balance.value(),
        burned_by: ctx.sender(),
    });

    self.treasury_cap.supply_mut().decrease_supply(balance);
}
