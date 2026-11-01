# Simdlaunch test coverage

The existing constructor, event, factory, transfer, approval, and administrative-call
tests are retained. `Simdlaunch.boundaries.t.sol` adds 18 unit/property tests.
`Simdlaunch.invariant.t.sol` extends the existing independent balance/allowance model.
No new dependencies are needed.

## Property selection

The five discovery perspectives in the supplied Pashov fizz reference were applied
locally. The Trail of Bits reference informed input bounds, explicit edge examples,
and checks for properties that could pass without exercising the relevant behavior.
These tests use the deployed token's public interface, not a modified token harness.

| Perspective | Property and basis | Coverage |
| --- | --- | --- |
| Conservation | The requested single mint is exactly `10^27` base units; transfers conserve balances and supply (`src/Simdlaunch.sol:12`, `:15`; vendored `ERC20.sol:183`). | Constructor tests and `invariant_SupplyAndBalancesMatchModel`; full-balance, one-unit, and token-address transfers. |
| State transitions | Approval replaces one owner/spender entry; finite spending consumes exactly its amount, unlimited approval persists, and reverts preserve state (`ERC20.sol:127`, `:149`, `:301`). | Complete 4-by-4 allowance model; finite/infinite/revoke handlers; overdraw and zero-recipient rollback; replacement, exhaustion, refund, and retry sequences. |
| Round trips | Ordinary transfers have no fee or conversion: sending an amount and returning it restores balances. Splitting a delegated transfer preserves its final state (`ERC20.sol:104`, `:183`). | Random round trips with intermediate balance checks, repeated-cycle fuzzing, and split-versus-single transfer comparison. |
| Adversarial use | Allowances are scoped to their owner and spender; neither the deployer nor another caller can take tokens without approval. Valid holders retain transfer ability (`ERC20.sol:149`, `:301`). | Existing admin probes; real contract spender, self-approval, approval-isolation, replay tests; post-sequence full-balance transfers by every actor. |
| Token semantics | Zero and self-transfers conserve balances; invalid zero recipients/spenders revert; metadata stays fixed (`src/Simdlaunch.sol:14`; `ERC20.sol:166`, `:183`). | Existing zero/self tests, aliased-role fuzzing, zero-address failure handlers, and metadata invariant. |

These are properties of the requested fixed-supply token and its accepted ERC-20
interface. There are no vault shares, conversions, reward accrual, external pricing,
or liquidation paths to model.

## Stateful campaign

Four actors form a closed set of holders and spenders. Setup mints to actor 0, then
distributes tokens through actual transfers, with finite and unlimited approvals
available from the start. Only the 13 listed handler selectors are targeted.

Expected balances and allowances are updated from successful operations and their
inputs; they are never copied back from token getters. A failed transfer leaves the
model unchanged, including an allowance that was provisioned before the attempted
transfer. The invariants compare every actor's balance and every allowance pair
after each handler call. They also check total supply, metadata, zero-address state,
and that no balance has leaked outside the actor set.

Failure handlers deliberately reach insufficient allowance, insufficient balance,
zero recipient, and zero spender checks. Expected reverts match the complete custom
error and its arguments; unexpected handler reverts fail the campaign. The allowance
overdraw handler selects a funded owner so a balance failure cannot mask its target.
At the end of each sequence, every actor sends its full balance around a ring, with
model checks after each transfer and all supply finally consolidated at actor 0.

Inline settings request 1,000 runs per fuzz property and 256 invariant sequences of
128 calls. Plain tests pin zero, one base unit, full supply, maximum uint256, and
maximum-minus-one approval. Inputs use bounds without discarded assumptions.

## Running

```sh
forge build
FOUNDRY_FUZZ_SEED=0x7da7d5e222322c31dfdc26cf57fe0baef777573de08f381f68a82274e92649ff forge test
```

For the assignment's write restrictions, local checks set
`FOUNDRY_OUT=test/scratch/out` and `FOUNDRY_CACHE_PATH=test/scratch/cache`; these only
relocate generated artifacts. The tests need no RPC, FFI, environment-reading
cheatcodes, or files from `test/scratch/` or `.imd/reads/`.

The supplied protected launch checks were reviewed. The standalone project does not
include their factory, Uniswap v4, ownership-check harness, or launch manifest.
The local launch fixture exercises token transfers; it does not execute those
protected pool/launch integrations. No implementation defect was reproduced during
this test work.
