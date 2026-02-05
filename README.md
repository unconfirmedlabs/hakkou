# Currency Treasury

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Sui](https://img.shields.io/badge/Sui-Move-6fbcf0)](https://sui.io)

A secure, flexible treasury wrapper for Sui Move currencies that provides controlled minting through an authority-based permission system.

## Overview

Currency Treasury wraps a `TreasuryCap` to provide fine-grained control over currency minting operations. Instead of directly exposing the treasury capability, it introduces a witness-based authority system where only registered authority types can mint new tokens.

This pattern is useful for:

- **Multi-party minting**: Allow multiple contracts or modules to mint tokens without sharing the raw `TreasuryCap`
- **Revocable permissions**: Add or remove minting authorities dynamically
- **Auditable operations**: All minting and burning operations emit events for on-chain tracking
- **Safe treasury management**: The underlying `TreasuryCap` remains protected inside the wrapper

## Features

- **Authority-based minting**: Register witness types as mint authorities; only holders of those witnesses can mint
- **Admin capability**: Separate admin cap for managing authorities and accessing the underlying treasury
- **Burn operations**: Receive coins sent to the treasury and burn them atomically
- **Event emissions**: Comprehensive events for treasury creation, destruction, minting, burning, and authority changes
- **Full lifecycle support**: Create, use, and destroy treasuries while maintaining access to the underlying cap

## Installation

Add the dependency to your `Move.toml`:

```toml
[dependencies]
CurrencyTreasury = { git = "https://github.com/unconfirmed-labs/currency_treasury.git", subdir = ".", rev = "main" }
```

## Usage

### Creating a Treasury

```move
use currency_treasury::currency_treasury;

// In your module's init function or elsewhere
public fun setup(treasury_cap: TreasuryCap<MY_COIN>, ctx: &mut TxContext) {
    let (treasury, admin_cap) = currency_treasury::new(treasury_cap, ctx);

    // Share or transfer as needed
    transfer::public_share_object(treasury);
    transfer::public_transfer(admin_cap, ctx.sender());
}
```

### Adding Mint Authorities

```move
// Define a witness type in your module
public struct MyMintAuthority has drop {}

// Add it as an authorized minter (requires admin cap)
public fun authorize_minter(
    treasury: &mut CurrencyTreasury<MY_COIN>,
    admin_cap: &CurrencyTreasuryAdminCap<MY_COIN>,
) {
    currency_treasury::add_mint_authority<MY_COIN, MyMintAuthority>(treasury, admin_cap);
}
```

### Minting with Authority

```move
public fun mint_tokens(
    treasury: &mut CurrencyTreasury<MY_COIN>,
    amount: u64,
    ctx: &TxContext,
): Balance<MY_COIN> {
    // Create the witness (only possible within the defining module)
    let authority = MyMintAuthority {};

    currency_treasury::mint(treasury, authority, amount, ctx)
}
```

### Burning Tokens

```move
// Receive and burn coins sent to the treasury address
public fun burn_received(
    treasury: &mut CurrencyTreasury<MY_COIN>,
    coins: vector<Receiving<Coin<MY_COIN>>>,
    ctx: &TxContext,
) {
    currency_treasury::receive_and_burn(treasury, coins, ctx);
}
```

### Destroying the Treasury

```move
// Returns the underlying TreasuryCap
public fun unwrap_treasury(
    treasury: CurrencyTreasury<MY_COIN>,
    admin_cap: CurrencyTreasuryAdminCap<MY_COIN>,
): TreasuryCap<MY_COIN> {
    currency_treasury::destroy(treasury, admin_cap)
}
```

## API Reference

### Structs

| Struct | Description |
|--------|-------------|
| `CurrencyTreasury<Currency>` | Wrapper around a `TreasuryCap` with authority-based minting |
| `CurrencyTreasuryAdminCap<Currency>` | Admin capability for managing the treasury |

### Functions

| Function | Description |
|----------|-------------|
| `new` | Create a new treasury by wrapping a `TreasuryCap` |
| `destroy` | Destroy the treasury and return the underlying `TreasuryCap` |
| `mint` | Mint tokens using an authorized witness |
| `add_mint_authority` | Register a new mint authority type |
| `remove_mint_authority` | Revoke a mint authority type |
| `receive_and_burn` | Receive coins sent to treasury and burn them |
| `redeem_and_burn` | Redeem funds from balance accumulators and burn |
| `id` | Get the treasury's object ID |
| `mint_authorities` | Get the set of registered authorities |
| `treasury_cap` | Get a read-only reference to the underlying cap |
| `treasury_cap_mut` | Get a mutable reference (requires admin cap) |

### Events

| Event | Emitted When |
|-------|--------------|
| `CurrencyTreasuryCreatedEvent` | A new treasury is created |
| `CurrencyTreasuryDestroyedEvent` | A treasury is destroyed |
| `CurrencyMintedEvent` | Tokens are minted |
| `CurrencyBurnedEvent` | Tokens are burned |
| `MintAuthorityAddedEvent` | An authority is registered |
| `MintAuthorityRemovedEvent` | An authority is revoked |

### Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| 0 | `EUnauthorizedMintAuthority` | Authority type not registered for minting |
| 1 | `ENoCoinsToReceive` | Empty vector passed to receive_and_burn |
| 2 | `EMintAuthorityAlreadyExists` | Authority already registered |
| 3 | `EMintAuthorityNotFound` | Authority not found for removal |

## Development

### Prerequisites

- [Sui CLI](https://docs.sui.io/build/install) installed

### Building

```bash
sui move build
```

### Testing

```bash
sui move test
```

### Test Coverage

```bash
sui move test --coverage
sui move coverage source --module currency_treasury
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

Built with [Sui Move](https://sui.io) by [Unconfirmed Labs](https://unconfirmed.com).
