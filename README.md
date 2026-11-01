# Simdlaunch (SIMD)

An immutable ERC-20 token with **1,000,000,000 SIMD**, **18 decimals**, and a single mint of the entire supply to the constructor's caller. The implementation is [src/Simdlaunch.sol](src/Simdlaunch.sol), using the vendored OpenZeppelin Contracts v5.1.0 ERC-20 implementation.

| Deployment parameter | Value |
| --- | --- |
| Solidity contract identifier | `Simdlaunch` |
| Fully qualified contract | `src/Simdlaunch.sol:Simdlaunch` |
| Token name / symbol | `Simdlaunch` / `SIMD` |
| Decimals | `18` |
| Total supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Constructor ETH value | `0` |
| Initial recipient | Immediate deployer, `msg.sender` |
| Launch chain | Ethereum, chain ID `1` |
| Compiler / EVM target | Solidity `0.8.26` / Cancun |
| Optimizer / metadata hash | Enabled, 200 runs / `none` |

## Behavior and assumptions

- `INITIAL_SUPPLY` is a named constant in smallest units. The constructor calls `_mint` exactly once and emits `Transfer(address(0), deployer, INITIAL_SUPPLY)`.
- The fixed supply is interpreted as non-rebasing and non-burnable. There is no external mint, burn, owner, administrator, pause, blacklist, seizure, upgrade, tax, transfer hook, or external dependency at runtime.
- `transfer`, `approve`, and `transferFrom` return `true` on success; invalid operations revert with OpenZeppelin's ERC-6093 errors. Transfers deliver the exact requested amount.
- Zero-value transfers between nonzero addresses succeed and emit `Transfer`. Self-transfers require sufficient balance and preserve that balance. Transfers to the zero address and approvals to a zero spender revert.
- Finite allowances decrease on `transferFrom`; `type(uint256).max` is an unlimited allowance and is not decreased. Even a holder using `transferFrom` on their own balance needs an allowance. Zero-value `transferFrom` does not require a positive allowance.
- `approve` replaces the allowance and emits `Approval`. OpenZeppelin v5 does not emit `Approval` when spending an allowance, so integrations should read `allowance()` for its current value.
- The token does not accept ordinary ETH payments and cannot recover tokens or forced ETH sent to its own address. The token is not a vault or payment receiver.

These choices follow the requested fixed-supply behavior and the [ERC-20 standard](https://eips.ethereum.org/EIPS/eip-20). Dependency provenance and licenses are in [DEPENDENCIES.md](DEPENDENCIES.md).

## Build and checks

Foundry and Solidity `0.8.26` must be installed. All Solidity dependencies are ordinary files in `lib/`; no package install, git submodule, RPC, environment file, FFI, or filesystem cheatcode permission is needed to build or test.

```sh
forge build
FOUNDRY_FUZZ_SEED=0x7da7d5e222322c31dfdc26cf57fe0baef777573de08f381f68a82274e92649ff forge test
forge fmt --check
```

The shell variable above sets only Foundry's fuzz input seed. Test code does not read or write environment variables. The configuration uses 512 runs per fuzz test and 128 runs of depth 64 per stateful invariant. Tests have fresh fixtures per test and require no fork, timer, or shared external state.

The unit and fuzz tests cover constructor issuance and events, direct and CREATE2 factory deployments, exact launch allocation/claim/custody transfers, approvals and revocation, finite and unlimited allowances, self/zero/full-balance transfers, insufficient balance/allowance failures, zero addresses, failure rollback, and attempts to mint, burn, seize, pause, or upgrade. The stateful tests compare balances and allowances against an independent model after mixed transfers, approvals, delegated transfers, and rejected overdrafts.

The local launch-flow test models token custody transfers. It does not execute Uniswap v4 pricing, liquidity, or swaps. The supplied protected integration suite needs the network's launch harness and manifest parameters; it is not part of the standalone local test suite.

Local validation passed with Solidity `0.8.26`: `forge build`, a forced offline rebuild (`forge build --offline --force`), the seeded `forge test`, and `forge fmt --check`. Foundry reported 33 unit/fuzz tests plus one grouped invariant suite, all passing. The invariant suite checked both model properties over 8,192 calls with no unexpected reverts. The compiled token has 2,639 bytes of creation code, 1,752 bytes of runtime code, and no library link references; the runtime also passed the opcode scan used by the supplied protected test. Vendored source hashes were verified against their included checksum files.

## Deployment and responsibilities

The deliverable is the single token contract. Deploy its compiled creation bytecode with no constructor arguments and no ETH. The constructor makes no external calls and requires no pre-existing contract or setup transaction. Bytecode can be inspected without broadcasting:

```sh
forge inspect src/Simdlaunch.sol:Simdlaunch bytecode
forge inspect src/Simdlaunch.sol:Simdlaunch deployedBytecode
forge inspect src/Simdlaunch.sol:Simdlaunch abi
```

For this launch, the network's factory must be the immediate deployer. It receives all `10^27` units, rather than the transaction origin, a helper contract, or a preselected wallet. The tests demonstrate both CREATE and CREATE2. A deployment helper that executes `new Simdlaunch()` will itself receive the supply, so the launch should deploy the token bytecode directly from its factory.

The launch service is responsible for the later manifest, factory deployment, distribution, pool setup, and explorer verification. The token does not implement pool mechanics or allocate supply itself. The supplied launch terms put 10% in the launch distributor, 70% into the pool, and 20% with the supplied remainder recipient; all of these movements occur after the constructor's single mint, through ordinary ERC-20 transfers. No application contracts or launch manifest are included here.

After deployment, the launch service should verify the source using the pinned compiler settings, metadata, total supply, initial `Transfer` event, and the factory's distribution receipts. No live deployment or transaction is performed by this project.

## After launch

There are no settings, owner-only setters, initialization calls, minting keys, or maintenance jobs. The deployer has the same token rights as every other holder once balances have been distributed. Holders are responsible for their keys, destination addresses, and spender approvals. Approve only the required amount where possible and revoke unused allowances. When replacing a nonzero allowance, applications should first set it to zero and confirm that transaction before granting the new amount; this mitigates the standard ERC-20 allowance replacement race but cannot undo spending already confirmed.

## Security review scope

The local review uses the supplied security checklist for supply units, authorization, input validation, and balance conservation. The token introduces no custom transfer arithmetic and makes no external calls during construction or transfers, so it has no callback reentrancy path. Internal OpenZeppelin mint/burn functions are unreachable through the deployed token's public interface after construction. There are no proxies, linked libraries, signatures, oracle inputs, or admin recovery paths.

Build, unit tests, deterministic fuzz tests, and stateful invariants are the local checks. Slither, Mythril, the protected network integration suite, and an independent security audit are not claimed as local validation. Independent review and launch verification remain the network's release responsibilities.
