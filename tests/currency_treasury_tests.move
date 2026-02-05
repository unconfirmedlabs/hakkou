// Copyright (c) Unconfirmed Labs, LLC
// SPDX-License-Identifier: Apache-2.0

#[test_only, allow(deprecated_usage)]
module currency_treasury::currency_treasury_tests;

use currency_treasury::currency_treasury::{
    Self,
    CurrencyTreasury,
    CurrencyTreasuryAdminCap,
    EUnauthorizedMintAuthority,
    ENoCoinsToReceive,
    EMintAuthorityAlreadyExists,
    EMintAuthorityNotFound
};
use std::type_name::with_defining_ids;
use std::unit_test::destroy;
use sui::balance;
use sui::coin::{Self, Coin, TreasuryCap};
use sui::event;
use sui::test_scenario::{Self as ts, Scenario};

//=== Test Currency (OTW must match module name in UPPERCASE) ===

/// One-time witness for creating the test currency.
/// Must match the module name in UPPERCASE for coin::create_currency to work.
public struct CURRENCY_TREASURY_TESTS has drop {}

//=== Test Mint Authorities ===

/// A test mint authority witness type.
public struct TestMintAuthority has drop {}

/// Another test mint authority for multi-authority tests.
public struct AnotherMintAuthority has drop {}

/// An unauthorized authority that is never registered.
public struct UnauthorizedAuthority has drop {}

//=== Test Addresses ===

const ADMIN: address = @0xAD;
const USER: address = @0xB0B;
const MINTER: address = @0xC0DE;

//=== Helper Functions ===

/// Creates a test TreasuryCap for CURRENCY_TREASURY_TESTS.
fun create_test_treasury_cap(ctx: &mut TxContext): TreasuryCap<CURRENCY_TREASURY_TESTS> {
    let (treasury_cap, metadata) = coin::create_currency(
        CURRENCY_TREASURY_TESTS {},
        9, // decimals
        b"TEST",
        b"Test Currency",
        b"A test currency for unit tests",
        option::none(),
        ctx,
    );
    destroy(metadata);
    treasury_cap
}

/// Sets up a new test scenario with a CurrencyTreasury.
fun setup_treasury(
    ts: &mut Scenario,
): (CurrencyTreasury<CURRENCY_TREASURY_TESTS>, CurrencyTreasuryAdminCap<CURRENCY_TREASURY_TESTS>) {
    let treasury_cap = create_test_treasury_cap(ts.ctx());
    currency_treasury::new(treasury_cap, ts.ctx())
}

//=== Creation Tests ===

#[test]
/// Test that a new CurrencyTreasury can be created successfully.
fun test_new_creates_treasury() {
    let mut ts = ts::begin(ADMIN);

    let (treasury, admin_cap) = setup_treasury(&mut ts);

    // Verify the treasury starts with no mint authorities
    assert!(treasury.mint_authorities().length() == 0);

    // Verify treasury cap is accessible
    assert!(treasury.treasury_cap().total_supply() == 0);

    destroy(treasury);
    destroy(admin_cap);
    ts.end();
}

#[test]
/// Test that multiple treasuries can be created independently.
fun test_new_creates_independent_treasuries() {
    let mut ts = ts::begin(ADMIN);

    let (treasury1, admin_cap1) = setup_treasury(&mut ts);
    let (treasury2, admin_cap2) = setup_treasury(&mut ts);

    // Verify they have different IDs
    assert!(treasury1.id() != treasury2.id());

    destroy(treasury1);
    destroy(admin_cap1);
    destroy(treasury2);
    destroy(admin_cap2);
    ts.end();
}

//=== Destroy Tests ===

#[test]
/// Test that destroy returns the underlying TreasuryCap.
fun test_destroy_returns_treasury_cap() {
    let mut ts = ts::begin(ADMIN);

    let (mut treasury, admin_cap) = setup_treasury(&mut ts);

    // Add an authority and mint some tokens first
    currency_treasury::add_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
        &mut treasury,
        &admin_cap,
    );

    let balance = currency_treasury::mint(
        &mut treasury,
        TestMintAuthority {},
        1000,
        ts.ctx(),
    );

    // Destroy the treasury
    let treasury_cap = currency_treasury::destroy(treasury, admin_cap);

    // Verify we got the treasury cap back with the correct supply
    assert!(treasury_cap.total_supply() == 1000);

    destroy(balance);
    destroy(treasury_cap);
    ts.end();
}

//=== Mint Authority Management Tests ===

#[test]
/// Test adding a mint authority.
fun test_add_mint_authority() {
    let mut ts = ts::begin(ADMIN);

    let (mut treasury, admin_cap) = setup_treasury(&mut ts);

    // Initially no authorities
    assert!(treasury.mint_authorities().length() == 0);

    // Add an authority
    currency_treasury::add_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
        &mut treasury,
        &admin_cap,
    );

    // Verify authority was added
    assert!(treasury.mint_authorities().length() == 1);
    assert!(treasury.mint_authorities().contains(&with_defining_ids<TestMintAuthority>()));

    destroy(treasury);
    destroy(admin_cap);
    ts.end();
}

#[test]
/// Test adding multiple mint authorities.
fun test_add_multiple_mint_authorities() {
    let mut ts = ts::begin(ADMIN);

    let (mut treasury, admin_cap) = setup_treasury(&mut ts);

    // Add first authority
    currency_treasury::add_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
        &mut treasury,
        &admin_cap,
    );

    // Add second authority
    currency_treasury::add_mint_authority<CURRENCY_TREASURY_TESTS, AnotherMintAuthority>(
        &mut treasury,
        &admin_cap,
    );

    // Verify both authorities were added
    assert!(treasury.mint_authorities().length() == 2);
    assert!(treasury.mint_authorities().contains(&with_defining_ids<TestMintAuthority>()));
    assert!(treasury.mint_authorities().contains(&with_defining_ids<AnotherMintAuthority>()));

    destroy(treasury);
    destroy(admin_cap);
    ts.end();
}

#[test]
#[expected_failure(abort_code = EMintAuthorityAlreadyExists)]
/// Test that adding the same authority twice fails.
fun test_add_mint_authority_already_exists() {
    let mut ts = ts::begin(ADMIN);

    let (mut treasury, admin_cap) = setup_treasury(&mut ts);

    // Add authority once
    currency_treasury::add_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
        &mut treasury,
        &admin_cap,
    );

    // Adding again should fail
    currency_treasury::add_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
        &mut treasury,
        &admin_cap,
    );

    destroy(treasury);
    destroy(admin_cap);
    ts.end();
}

#[test]
/// Test removing a mint authority.
fun test_remove_mint_authority() {
    let mut ts = ts::begin(ADMIN);

    let (mut treasury, admin_cap) = setup_treasury(&mut ts);

    // Add then remove authority
    currency_treasury::add_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
        &mut treasury,
        &admin_cap,
    );

    assert!(treasury.mint_authorities().length() == 1);

    currency_treasury::remove_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
        &mut treasury,
        &admin_cap,
    );

    // Verify authority was removed
    assert!(treasury.mint_authorities().length() == 0);
    assert!(!treasury.mint_authorities().contains(&with_defining_ids<TestMintAuthority>()));

    destroy(treasury);
    destroy(admin_cap);
    ts.end();
}

#[test]
#[expected_failure(abort_code = EMintAuthorityNotFound)]
/// Test that removing a non-existent authority fails.
fun test_remove_mint_authority_not_found() {
    let mut ts = ts::begin(ADMIN);

    let (mut treasury, admin_cap) = setup_treasury(&mut ts);

    // Try to remove an authority that was never added
    currency_treasury::remove_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
        &mut treasury,
        &admin_cap,
    );

    destroy(treasury);
    destroy(admin_cap);
    ts.end();
}

#[test]
/// Test that an authority can be re-added after removal.
fun test_readd_removed_authority() {
    let mut ts = ts::begin(ADMIN);

    let (mut treasury, admin_cap) = setup_treasury(&mut ts);

    // Add, remove, then add again
    currency_treasury::add_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
        &mut treasury,
        &admin_cap,
    );

    currency_treasury::remove_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
        &mut treasury,
        &admin_cap,
    );

    currency_treasury::add_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
        &mut treasury,
        &admin_cap,
    );

    // Verify authority is back
    assert!(treasury.mint_authorities().length() == 1);
    assert!(treasury.mint_authorities().contains(&with_defining_ids<TestMintAuthority>()));

    destroy(treasury);
    destroy(admin_cap);
    ts.end();
}

//=== Minting Tests ===

#[test]
/// Test minting with an authorized authority.
fun test_mint() {
    let mut ts = ts::begin(ADMIN);

    let (mut treasury, admin_cap) = setup_treasury(&mut ts);

    // Add authority
    currency_treasury::add_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
        &mut treasury,
        &admin_cap,
    );

    // Mint tokens
    let balance = currency_treasury::mint(
        &mut treasury,
        TestMintAuthority {},
        1000,
        ts.ctx(),
    );

    // Verify minted amount
    assert!(balance.value() == 1000);
    assert!(treasury.treasury_cap().total_supply() == 1000);

    destroy(balance);
    destroy(treasury);
    destroy(admin_cap);
    ts.end();
}

#[test]
/// Test minting zero value.
fun test_mint_zero_value() {
    let mut ts = ts::begin(ADMIN);

    let (mut treasury, admin_cap) = setup_treasury(&mut ts);

    currency_treasury::add_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
        &mut treasury,
        &admin_cap,
    );

    let balance = currency_treasury::mint(
        &mut treasury,
        TestMintAuthority {},
        0,
        ts.ctx(),
    );

    assert!(balance.value() == 0);
    assert!(treasury.treasury_cap().total_supply() == 0);

    destroy(balance);
    destroy(treasury);
    destroy(admin_cap);
    ts.end();
}

#[test]
/// Test minting multiple times accumulates supply.
fun test_mint_multiple_times() {
    let mut ts = ts::begin(ADMIN);

    let (mut treasury, admin_cap) = setup_treasury(&mut ts);

    currency_treasury::add_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
        &mut treasury,
        &admin_cap,
    );

    let balance1 = currency_treasury::mint(
        &mut treasury,
        TestMintAuthority {},
        100,
        ts.ctx(),
    );

    let balance2 = currency_treasury::mint(
        &mut treasury,
        TestMintAuthority {},
        200,
        ts.ctx(),
    );

    let balance3 = currency_treasury::mint(
        &mut treasury,
        TestMintAuthority {},
        300,
        ts.ctx(),
    );

    // Verify total supply
    assert!(treasury.treasury_cap().total_supply() == 600);

    destroy(balance1);
    destroy(balance2);
    destroy(balance3);
    destroy(treasury);
    destroy(admin_cap);
    ts.end();
}

#[test]
/// Test minting with different authorized authorities.
fun test_mint_with_multiple_authorities() {
    let mut ts = ts::begin(ADMIN);

    let (mut treasury, admin_cap) = setup_treasury(&mut ts);

    // Add both authorities
    currency_treasury::add_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
        &mut treasury,
        &admin_cap,
    );
    currency_treasury::add_mint_authority<CURRENCY_TREASURY_TESTS, AnotherMintAuthority>(
        &mut treasury,
        &admin_cap,
    );

    // Mint with first authority
    let balance1 = currency_treasury::mint(
        &mut treasury,
        TestMintAuthority {},
        100,
        ts.ctx(),
    );

    // Mint with second authority
    let balance2 = currency_treasury::mint(
        &mut treasury,
        AnotherMintAuthority {},
        200,
        ts.ctx(),
    );

    assert!(balance1.value() == 100);
    assert!(balance2.value() == 200);
    assert!(treasury.treasury_cap().total_supply() == 300);

    destroy(balance1);
    destroy(balance2);
    destroy(treasury);
    destroy(admin_cap);
    ts.end();
}

#[test]
#[expected_failure(abort_code = EUnauthorizedMintAuthority)]
/// Test that minting with an unauthorized authority fails.
fun test_mint_unauthorized() {
    let mut ts = ts::begin(ADMIN);

    let (mut treasury, admin_cap) = setup_treasury(&mut ts);

    // Don't add any authority, try to mint
    let balance = currency_treasury::mint(
        &mut treasury,
        TestMintAuthority {},
        1000,
        ts.ctx(),
    );

    destroy(balance);
    destroy(treasury);
    destroy(admin_cap);
    ts.end();
}

#[test]
#[expected_failure(abort_code = EUnauthorizedMintAuthority)]
/// Test that minting with a removed authority fails.
fun test_mint_after_authority_removed() {
    let mut ts = ts::begin(ADMIN);

    let (mut treasury, admin_cap) = setup_treasury(&mut ts);

    // Add then remove authority
    currency_treasury::add_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
        &mut treasury,
        &admin_cap,
    );

    currency_treasury::remove_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
        &mut treasury,
        &admin_cap,
    );

    // Try to mint with removed authority
    let balance = currency_treasury::mint(
        &mut treasury,
        TestMintAuthority {},
        1000,
        ts.ctx(),
    );

    destroy(balance);
    destroy(treasury);
    destroy(admin_cap);
    ts.end();
}

#[test]
#[expected_failure(abort_code = EUnauthorizedMintAuthority)]
/// Test that minting with a different unauthorized authority fails even when others are authorized.
fun test_mint_wrong_authority() {
    let mut ts = ts::begin(ADMIN);

    let (mut treasury, admin_cap) = setup_treasury(&mut ts);

    // Add TestMintAuthority but try to mint with UnauthorizedAuthority
    currency_treasury::add_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
        &mut treasury,
        &admin_cap,
    );

    let balance = currency_treasury::mint(
        &mut treasury,
        UnauthorizedAuthority {},
        1000,
        ts.ctx(),
    );

    destroy(balance);
    destroy(treasury);
    destroy(admin_cap);
    ts.end();
}

//=== Burn Tests ===

#[test]
/// Test that burn emits an event and decreases supply for nonzero balances.
fun test_burn_nonzero_balance() {
    let mut ts = ts::begin(ADMIN);

    let (mut treasury, admin_cap) = setup_treasury(&mut ts);
    currency_treasury::add_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
        &mut treasury,
        &admin_cap,
    );

    let balance = currency_treasury::mint(
        &mut treasury,
        TestMintAuthority {},
        100,
        ts.ctx(),
    );

    assert!(
        event::events_by_type<
            currency_treasury::CurrencyBurnedEvent<CURRENCY_TREASURY_TESTS>,
        >().is_empty(),
    );

    currency_treasury::burn(&mut treasury, balance, ts.ctx());

    assert!(treasury.treasury_cap().total_supply() == 0);
    let burned = event::events_by_type<
        currency_treasury::CurrencyBurnedEvent<CURRENCY_TREASURY_TESTS>,
    >();
    assert!(burned.length() == 1);

    destroy(treasury);
    destroy(admin_cap);
    ts.end();
}

#[test]
/// Test that burn ignores zero-value balances and emits no burn event.
fun test_burn_zero_balance() {
    let mut ts = ts::begin(ADMIN);

    let (mut treasury, admin_cap) = setup_treasury(&mut ts);
    currency_treasury::add_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
        &mut treasury,
        &admin_cap,
    );

    let balance = currency_treasury::mint(
        &mut treasury,
        TestMintAuthority {},
        0,
        ts.ctx(),
    );

    currency_treasury::burn(&mut treasury, balance, ts.ctx());

    assert!(treasury.treasury_cap().total_supply() == 0);
    assert!(
        event::events_by_type<
            currency_treasury::CurrencyBurnedEvent<CURRENCY_TREASURY_TESTS>,
        >().is_empty(),
    );

    destroy(treasury);
    destroy(admin_cap);
    ts.end();
}

//=== Receive and Burn Tests ===

#[test]
#[expected_failure(abort_code = ENoCoinsToReceive)]
/// Test that receive_and_burn fails with empty vector.
fun test_receive_and_burn_empty_vector() {
    let mut ts = ts::begin(ADMIN);

    let (mut treasury, admin_cap) = setup_treasury(&mut ts);

    // Try to burn with empty vector
    currency_treasury::receive_and_burn(
        &mut treasury,
        vector[],
        ts.ctx(),
    );

    destroy(treasury);
    destroy(admin_cap);
    ts.end();
}

#[test]
/// Test that receive_and_burn burns a single received coin and emits an event.
fun test_receive_and_burn_single_coin() {
    let mut ts = ts::begin(ADMIN);

    // Transaction 1: Create treasury, add authority, mint, and transfer coin to treasury address
    {
        let (mut treasury, admin_cap) = setup_treasury(&mut ts);
        currency_treasury::add_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
            &mut treasury,
            &admin_cap,
        );

        let balance = currency_treasury::mint(
            &mut treasury,
            TestMintAuthority {},
            1000,
            ts.ctx(),
        );
        let coin = coin::from_balance(balance, ts.ctx());
        let treasury_addr = object::id_to_address(&treasury.id());
        transfer::public_transfer(coin, treasury_addr);

        transfer::public_share_object(treasury);
        transfer::public_transfer(admin_cap, ADMIN);
    };

    // Transaction 2: Receive and burn the coin
    ts.next_tx(ADMIN);
    {
        let mut treasury = ts.take_shared<CurrencyTreasury<CURRENCY_TREASURY_TESTS>>();
        let ticket = ts::most_recent_receiving_ticket<Coin<CURRENCY_TREASURY_TESTS>>(
            &treasury.id(),
        );

        assert!(
            event::events_by_type<
                currency_treasury::CurrencyBurnedEvent<CURRENCY_TREASURY_TESTS>,
            >().is_empty(),
        );

        currency_treasury::receive_and_burn(
            &mut treasury,
            vector[ticket],
            ts.ctx(),
        );

        assert!(treasury.treasury_cap().total_supply() == 0);
        let burned = event::events_by_type<
            currency_treasury::CurrencyBurnedEvent<CURRENCY_TREASURY_TESTS>,
        >();
        assert!(burned.length() == 1);

        ts::return_shared(treasury);
    };

    ts.end();
}

#[test]
/// Test that receive_and_burn ignores zero-value coins and emits no burn event.
fun test_receive_and_burn_zero_value_coin() {
    let mut ts = ts::begin(ADMIN);

    // Transaction 1: Create treasury and transfer a zero-value coin to treasury address
    {
        let (mut treasury, admin_cap) = setup_treasury(&mut ts);
        currency_treasury::add_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
            &mut treasury,
            &admin_cap,
        );

        let balance = currency_treasury::mint(
            &mut treasury,
            TestMintAuthority {},
            0,
            ts.ctx(),
        );
        let coin = coin::from_balance(balance, ts.ctx());
        let treasury_addr = object::id_to_address(&treasury.id());
        transfer::public_transfer(coin, treasury_addr);

        transfer::public_share_object(treasury);
        transfer::public_transfer(admin_cap, ADMIN);
    };

    // Transaction 2: Receive and burn the zero-value coin
    ts.next_tx(ADMIN);
    {
        let mut treasury = ts.take_shared<CurrencyTreasury<CURRENCY_TREASURY_TESTS>>();
        let ticket = ts::most_recent_receiving_ticket<Coin<CURRENCY_TREASURY_TESTS>>(
            &treasury.id(),
        );

        currency_treasury::receive_and_burn(
            &mut treasury,
            vector[ticket],
            ts.ctx(),
        );

        assert!(treasury.treasury_cap().total_supply() == 0);
        assert!(
            event::events_by_type<
                currency_treasury::CurrencyBurnedEvent<CURRENCY_TREASURY_TESTS>,
            >().is_empty(),
        );

        ts::return_shared(treasury);
    };

    ts.end();
}

#[test]
/// Test that receive_and_burn burns multiple received coins and sums correctly.
fun test_receive_and_burn_multiple_coins() {
    let mut ts = ts::begin(ADMIN);

    // Transaction 1: Create treasury, mint multiple coins, transfer to treasury address
    {
        let (mut treasury, admin_cap) = setup_treasury(&mut ts);
        currency_treasury::add_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
            &mut treasury,
            &admin_cap,
        );

        let balance1 = currency_treasury::mint(
            &mut treasury,
            TestMintAuthority {},
            100,
            ts.ctx(),
        );
        let balance2 = currency_treasury::mint(
            &mut treasury,
            TestMintAuthority {},
            200,
            ts.ctx(),
        );
        let coin1 = coin::from_balance(balance1, ts.ctx());
        let coin2 = coin::from_balance(balance2, ts.ctx());
        let treasury_addr = object::id_to_address(&treasury.id());
        transfer::public_transfer(coin1, treasury_addr);
        transfer::public_transfer(coin2, treasury_addr);

        transfer::public_share_object(treasury);
        transfer::public_transfer(admin_cap, ADMIN);
    };

    // Transaction 2: Receive and burn both coins
    ts.next_tx(ADMIN);
    {
        let mut treasury = ts.take_shared<CurrencyTreasury<CURRENCY_TREASURY_TESTS>>();
        let mut ids = ts::receivable_object_ids_for_owner_id<
            Coin<CURRENCY_TREASURY_TESTS>,
        >(treasury.id());
        assert!(ids.length() == 2);
        let id1 = vector::pop_back(&mut ids);
        let id2 = vector::pop_back(&mut ids);
        let ticket1 = ts::receiving_ticket_by_id<Coin<CURRENCY_TREASURY_TESTS>>(id1);
        let ticket2 = ts::receiving_ticket_by_id<Coin<CURRENCY_TREASURY_TESTS>>(id2);

        currency_treasury::receive_and_burn(
            &mut treasury,
            vector[ticket1, ticket2],
            ts.ctx(),
        );

        assert!(treasury.treasury_cap().total_supply() == 0);
        let burned = event::events_by_type<
            currency_treasury::CurrencyBurnedEvent<CURRENCY_TREASURY_TESTS>,
        >();
        assert!(burned.length() == 1);

        ts::return_shared(treasury);
    };

    ts.end();
}

//=== Redeem and Burn Tests ===

#[test]
/// Test redeem_and_burn burns from the treasury's funds accumulator.
fun test_redeem_and_burn_partial_and_full() {
    let mut ts = ts::begin(ADMIN);

    // Transaction 1: Create treasury, mint balance, and send to treasury's funds accumulator
    {
        let (mut treasury, admin_cap) = setup_treasury(&mut ts);
        currency_treasury::add_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
            &mut treasury,
            &admin_cap,
        );

        let balance = currency_treasury::mint(
            &mut treasury,
            TestMintAuthority {},
            500,
            ts.ctx(),
        );
        let treasury_addr = object::id_to_address(&treasury.id());
        balance::send_funds(balance, treasury_addr);

        transfer::public_share_object(treasury);
        transfer::public_transfer(admin_cap, ADMIN);
    };

    // Transaction 2: Redeem and burn in two steps
    ts.next_tx(ADMIN);
    {
        let mut treasury = ts.take_shared<CurrencyTreasury<CURRENCY_TREASURY_TESTS>>();

        currency_treasury::redeem_and_burn(&mut treasury, 200, ts.ctx());
        assert!(treasury.treasury_cap().total_supply() == 300);

        currency_treasury::redeem_and_burn(&mut treasury, 300, ts.ctx());
        assert!(treasury.treasury_cap().total_supply() == 0);

        let burned = event::events_by_type<
            currency_treasury::CurrencyBurnedEvent<CURRENCY_TREASURY_TESTS>,
        >();
        assert!(burned.length() == 2);

        ts::return_shared(treasury);
    };

    ts.end();
}

//=== Accessor Tests ===

#[test]
/// Test the id() accessor returns correct ID.
fun test_id_accessor() {
    let mut ts = ts::begin(ADMIN);

    let (treasury, admin_cap) = setup_treasury(&mut ts);

    // Just verify we can get the ID and it's not zero
    let id = treasury.id();
    // ID should be a valid object ID (non-zero)
    assert!(id != object::id_from_address(@0x0));

    destroy(treasury);
    destroy(admin_cap);
    ts.end();
}

#[test]
/// Test the mint_authorities() accessor.
fun test_mint_authorities_accessor() {
    let mut ts = ts::begin(ADMIN);

    let (mut treasury, admin_cap) = setup_treasury(&mut ts);

    // Initially empty
    assert!(treasury.mint_authorities().is_empty());

    // Add authority
    currency_treasury::add_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
        &mut treasury,
        &admin_cap,
    );

    // Now has one
    assert!(treasury.mint_authorities().length() == 1);

    destroy(treasury);
    destroy(admin_cap);
    ts.end();
}

#[test]
/// Test the treasury_cap() accessor.
fun test_treasury_cap_accessor() {
    let mut ts = ts::begin(ADMIN);

    let (mut treasury, admin_cap) = setup_treasury(&mut ts);

    // Verify we can read from treasury cap
    assert!(treasury.treasury_cap().total_supply() == 0);

    // After minting, supply should increase
    currency_treasury::add_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
        &mut treasury,
        &admin_cap,
    );

    let balance = currency_treasury::mint(
        &mut treasury,
        TestMintAuthority {},
        500,
        ts.ctx(),
    );

    assert!(treasury.treasury_cap().total_supply() == 500);

    destroy(balance);
    destroy(treasury);
    destroy(admin_cap);
    ts.end();
}

#[test]
/// Test the treasury_cap_mut() accessor.
fun test_treasury_cap_mut_accessor() {
    let mut ts = ts::begin(ADMIN);

    let (mut treasury, admin_cap) = setup_treasury(&mut ts);

    // Get mutable access to treasury cap
    let treasury_cap_mut = currency_treasury::treasury_cap_mut(&mut treasury, &admin_cap);

    // Mint directly using the mutable cap
    let coin = coin::mint(treasury_cap_mut, 1000, ts.ctx());

    // Verify supply increased
    assert!(treasury.treasury_cap().total_supply() == 1000);

    destroy(coin);
    destroy(treasury);
    destroy(admin_cap);
    ts.end();
}

//=== Integration Tests ===

#[test]
/// Test complete lifecycle: create, add authority, mint, destroy.
fun test_complete_lifecycle() {
    let mut ts = ts::begin(ADMIN);

    // Create treasury
    let (mut treasury, admin_cap) = setup_treasury(&mut ts);

    // Add mint authority
    currency_treasury::add_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
        &mut treasury,
        &admin_cap,
    );

    // Mint some tokens
    let balance = currency_treasury::mint(
        &mut treasury,
        TestMintAuthority {},
        5000,
        ts.ctx(),
    );

    // Verify state
    assert!(treasury.mint_authorities().length() == 1);
    assert!(treasury.treasury_cap().total_supply() == 5000);
    assert!(balance.value() == 5000);

    // Destroy treasury and get cap back
    let treasury_cap = currency_treasury::destroy(treasury, admin_cap);

    // Verify we can still use the treasury cap
    assert!(treasury_cap.total_supply() == 5000);

    destroy(balance);
    destroy(treasury_cap);
    ts.end();
}

#[test]
/// Test authority lifecycle: add, use, remove, re-add, use again.
fun test_authority_lifecycle() {
    let mut ts = ts::begin(ADMIN);

    let (mut treasury, admin_cap) = setup_treasury(&mut ts);

    // Add authority and mint
    currency_treasury::add_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
        &mut treasury,
        &admin_cap,
    );

    let balance1 = currency_treasury::mint(
        &mut treasury,
        TestMintAuthority {},
        100,
        ts.ctx(),
    );

    // Remove authority
    currency_treasury::remove_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
        &mut treasury,
        &admin_cap,
    );

    // Re-add authority
    currency_treasury::add_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
        &mut treasury,
        &admin_cap,
    );

    // Mint again
    let balance2 = currency_treasury::mint(
        &mut treasury,
        TestMintAuthority {},
        200,
        ts.ctx(),
    );

    assert!(treasury.treasury_cap().total_supply() == 300);

    destroy(balance1);
    destroy(balance2);
    destroy(treasury);
    destroy(admin_cap);
    ts.end();
}

//=== Multi-Transaction Tests ===

#[test]
/// Test treasury operations across multiple transactions.
fun test_multi_transaction_minting() {
    let mut ts = ts::begin(ADMIN);

    // Transaction 1: Create treasury and share it
    {
        let (treasury, admin_cap) = setup_treasury(&mut ts);
        transfer::public_share_object(treasury);
        transfer::public_transfer(admin_cap, ADMIN);
    };

    // Transaction 2: Admin adds mint authority
    ts.next_tx(ADMIN);
    {
        let mut treasury = ts.take_shared<CurrencyTreasury<CURRENCY_TREASURY_TESTS>>();
        let admin_cap = ts.take_from_sender<CurrencyTreasuryAdminCap<CURRENCY_TREASURY_TESTS>>();

        currency_treasury::add_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
            &mut treasury,
            &admin_cap,
        );

        ts::return_shared(treasury);
        ts.return_to_sender(admin_cap);
    };

    // Transaction 3: Minter mints tokens
    ts.next_tx(MINTER);
    {
        let mut treasury = ts.take_shared<CurrencyTreasury<CURRENCY_TREASURY_TESTS>>();

        let balance = currency_treasury::mint(
            &mut treasury,
            TestMintAuthority {},
            1000,
            ts.ctx(),
        );

        assert!(balance.value() == 1000);
        assert!(treasury.treasury_cap().total_supply() == 1000);

        // Convert balance to coin and transfer to minter
        let coin = coin::from_balance(balance, ts.ctx());
        transfer::public_transfer(coin, MINTER);

        ts::return_shared(treasury);
    };

    // Transaction 4: Verify minter received the coin
    ts.next_tx(MINTER);
    {
        let coin = ts.take_from_sender<Coin<CURRENCY_TREASURY_TESTS>>();
        assert!(coin.value() == 1000);
        destroy(coin);
    };

    ts.end();
}

#[test]
/// Test that different users can mint with the same authority.
fun test_different_users_same_authority() {
    let mut ts = ts::begin(ADMIN);

    // Setup: Create treasury and add authority
    {
        let (treasury, admin_cap) = setup_treasury(&mut ts);
        transfer::public_share_object(treasury);
        transfer::public_transfer(admin_cap, ADMIN);
    };

    ts.next_tx(ADMIN);
    {
        let mut treasury = ts.take_shared<CurrencyTreasury<CURRENCY_TREASURY_TESTS>>();
        let admin_cap = ts.take_from_sender<CurrencyTreasuryAdminCap<CURRENCY_TREASURY_TESTS>>();

        currency_treasury::add_mint_authority<CURRENCY_TREASURY_TESTS, TestMintAuthority>(
            &mut treasury,
            &admin_cap,
        );

        ts::return_shared(treasury);
        ts.return_to_sender(admin_cap);
    };

    // User 1 mints
    ts.next_tx(USER);
    {
        let mut treasury = ts.take_shared<CurrencyTreasury<CURRENCY_TREASURY_TESTS>>();

        let balance = currency_treasury::mint(
            &mut treasury,
            TestMintAuthority {},
            100,
            ts.ctx(),
        );

        destroy(balance);
        ts::return_shared(treasury);
    };

    // Minter also mints
    ts.next_tx(MINTER);
    {
        let mut treasury = ts.take_shared<CurrencyTreasury<CURRENCY_TREASURY_TESTS>>();

        let balance = currency_treasury::mint(
            &mut treasury,
            TestMintAuthority {},
            200,
            ts.ctx(),
        );

        // Verify total supply from both mints
        assert!(treasury.treasury_cap().total_supply() == 300);

        destroy(balance);
        ts::return_shared(treasury);
    };

    ts.end();
}
