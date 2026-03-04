# Certora Formal Verification: Suilend Liquid Staking

This directory contains Certora's formal verification of the Suilend liquid staking protocol, written in Move on Sui.

## Directory Structure

### `spec/`

The primary verification package. Contains all specification files (written in Move using the `cvlm` framework), per-rule configuration files, and package metadata.

- `spec/sources/`:Specification modules. Each `.move` file encodes one or more verifiable properties as rules.
- `spec/confs/`:Per-rule Certora Prover configuration files (`.conf`), one per property group.
- `spec/Move.toml`:Package manifest for spec sources. References the `liquid_staking` contract, the `cvlm` (Certora Verification Language for Move) library, Certora Sui framework summaries, and overrides for Sui system packages.

### `munges/`

Code modification scripts and patch files. These make internal functions accessible to the Prover by widening their visibility, and reduce `MAX_VALIDATORS` to make verification tractable.

- `munge.sh`:Applies all patches before running verification.
- `unmunge.sh`:Reverts all patches.
- `record_patches.sh`:Regenerates patch files from current working-directory diffs against HEAD.
- `fees.patch`:Makes `validate_fees()` public.
- `storage.patch`:Widens visibility of view functions and internal helpers; reduces `MAX_VALIDATORS` from 50 to 5.

> [!NOTE]
> The patches are applied as git patches and must be kept in sync with the source code. If the patched files change, `munge.sh` will fail to apply and verification will not run. Use `record_patches.sh` to regenerate the patches after updating the source.

### `assumptions/`

A separate package that verifies assumptions made by summaries in the main spec. Currently contains one rule proving that `liquid_staking::storage::get_sui_amount` is equivalent to `sui_system::staking_pool::get_sui_amount`.

- `assumptions/sources/assumptions.move`:Assumption validation rules.
- `assumptions/Move.toml`:Package manifest.
- `Assumptions.conf`:Prover configuration for running assumption checks.

## Certora Prover

The Certora Prover is a formal verification tool for smart contracts. It statically proves or disproves properties expressed as rules in the Certora Verification Language for Move.

## Running Instructions

0. Install the latest certora prover by following the [installation guide](https://docs.certora.com/en/latest/docs/user-guide/install.html).

1. From the repository root, apply the munges:

    ```sh
    sh certora/munges/munge.sh
    ```

    This only needs to be done once per working copy. **Do not commit the munged files.**

2. Change into the `certora/spec/` directory and run the desired verification job (see table below for all scripts). Example:

    ```sh
    certoraRun confs/solvency.conf
    ```

    Note that `certora/spec/` must be the working directory for `certoraRun`, otherwise it will fail to compile.

3. To revert munges:

    ```sh
    sh certora/munges/unmunge.sh
    ```

## High-Level Properties

See the doc-comments in each spec file for detailed descriptions of individual rules.

- **Solvency and Exchange Rate Monotonicity** (`solvency.move`, `solvency.conf`, `solvency_monotonicity.conf`): `total_sui_supply >= total_lst_supply` always holds; SUI/LST exchange rate is non-decreasing
- **Total SUI Supply Accounting** (`accounting_total_sui_supply.move`, `accounting_total_sui_supply.conf`): `total_sui_supply` equals the sum of the liquid SUI pool, active stake (via exchange rate), and inactive stake principal
- **Token Supply Initialization Invariants** (`accounting_no_lst_no_sui.move`, `accounting_no_lst_no_sui.conf`): zero LST implies zero SUI backing and vice versa
- **Value Conservation** (`accounting_value_conservation.move`, `accounting_value_conservation.conf`): no value is created or destroyed; on `mint`, deposited SUI equals backing increase plus fees; on `redeem`, SUI decrease equals SUI returned plus fees
- **Fee Accounting Integrity** (`fees.move`, `fees.conf`): accrued fees never exceed total SUI supply, grow monotonically except during collection, and never fully consume a deposit or redemption
- **Supply Control Authorization** (`supply_control.move`, `supply_control_decreases.conf`, `supply_control_increases_p1/p2.conf`): only `mint` can increase supplies; only `redeem`/`custom_redeem` can decrease them
- **No Arbitrage** (`no_arbitrage.move`, `no_arbitrage.conf`): a back-to-back `mint` then `redeem` never yields more SUI than was deposited
- **Validator Registry Consistency** (`validators_consistency.move`, `validators_consistency_p1/p2.conf`): no duplicate validators, registry never exceeds `MAX_VALIDATORS`, no-stake validators have zero `total_sui_amount`
- **Validator Registry Integrity** (`validators_integrity.move`, `validators_integrity.conf`): validators added only by authorized operations, removed only by `refresh`, at most one per call; `refresh` leaves no inactive stake or empty validators
- **Assumption Validation** (`assumptions/sources/assumptions.move`, `Assumptions.conf`): validates assumptions made in summaries

## General Assumptions

- **Loop unrolling.** All specs use `optimistic_loop: true`. `loop_iter` is set to 2 for most validator-list rules and 6 for `validators_upper_bound_step` (one above the munged `MAX_VALIDATORS = 5`).
- **Validator count reduction.** `storage.patch` reduces `MAX_VALIDATORS` from 50 to 5. Several inductive step rules further restrict to 1 validator for tractability.
- **`setup_fresh` precondition.** Most inductive steps model a post-`refresh` state: no inactive stake, all validators have active stake with matching pool IDs and up-to-date exchange rates, `total_sui_supply` is correct, and `last_refresh_epoch == ctx.epoch()`. Each assumption is justified by a separately verified rule.
- **Solvent exchange rates.** `summaries.move` assumes `sui_amount >= pool_token_amount` for all exchange rates, reflecting Sui system-level pool solvency.
- **`redeem_fungible_staked_sui` summary.** The full proportional split between principal and rewards is simplified to `get_sui_amount(er, value)`. An internal `cvlm_assert` checks this is an underapproximation of the actual withdrawal.
