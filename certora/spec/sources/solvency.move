/// Property: Protocol Solvency and Exchange Rate Monotonicity
/// Description: Verifies that the liquid staking protocol maintains solvency throughout its lifecycle,
/// ensuring that the SUI backing always meets or exceeds the LST supply (maintaining an exchange rate >= 1).
/// Additionally, this property verifies that the SUI/LST exchange rate is non-decreasing across operations,
/// protecting users from value dilution. Solvency is established at initialization and preserved through
/// induction across all state-modifying operations. The monotonic exchange rate ensures that LST tokens
/// never lose purchasing power relative to SUI over time.

module spec::solvency;

use cvlm::asserts::{cvlm_assert, cvlm_assume_msg};
use cvlm::function::Function;
use cvlm::ghost::ghost_destroy;
use cvlm::manifest::{target, invoker, rule};
use cvlm::nondet::nondet;
use liquid_staking::fees::validate_fees;
use liquid_staking::liquid_staking::{Self, LiquidStakingInfo};
use spec::dummy::DummyToken;
use sui_system::sui_system::SuiSystemState;
use spec::common::setup_fresh;
use spec::accounting_total_sui_supply::total_supply_correct;

public fun cvlm_manifest() {
    // Public mut functions

    target(@spec, b"dummy", b"mint");
    target(@spec, b"dummy", b"redeem");
    target(@spec, b"dummy", b"custom_redeem_request");
    target(@spec, b"dummy", b"custom_redeem");
    target(@spec, b"dummy", b"change_validator_priority");
    target(@spec, b"dummy", b"increase_validator_stake");
    target(@spec, b"dummy", b"decrease_validator_stake");
    target(@spec, b"dummy", b"collect_fees");
    target(@spec, b"dummy", b"update_fees");
    target(@spec, b"dummy", b"refresh");
    target(@spec, b"dummy", b"update_metadata");

    invoker(b"invoke");

    rule(b"solvency_base");
    rule(b"solvency_base_staker");
    rule(b"solvency_step");
    
    // This rule verifies an upper bound of 1 for insolvency per operation
    // rule(b"insolvency_bound");

    rule(b"monotonicity");
}

const MAX_VALIDATORS: u64 = 1;

native fun invoke(
    target: Function,
    lis: &mut LiquidStakingInfo<DummyToken>,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
);



/// Checks whether the protocol is solvent by verifying that the total SUI backing is at least
/// equal to the total LST supply. This ensures the exchange rate (SUI/LST) is at least 1:1.
/// lsi.total_sui_supply()/lsi.total_lst_supply() >= 1
/// <==> lsi.total_sui_supply() >= lsi.total_lst_supply()
public fun is_solvent<T>(lsi: &LiquidStakingInfo<T>): bool {
    let sui_supply = lsi.total_sui_supply();
    let lst_supply = lsi.total_lst_supply();

    sui_supply >= lst_supply
}

/// Base case: Verifies that newly created empty liquid staking pools are solvent.
/// This establishes the initial solvency invariant at pool creation.
public fun solvency_base<P: drop>() {
    let fee_config = nondet();
    let lst_treasury_cap = nondet();
    let mut ctx = nondet();
    let (cap, lsi) = liquid_staking::create_lst<P>(fee_config, lst_treasury_cap, &mut ctx);

    cvlm_assert(is_solvent(&lsi));

    ghost_destroy(cap);
    ghost_destroy(lsi);
}

/// Base case: Verifies that newly created liquid staking pools initialized with existing stake are solvent.
/// This establishes the initial solvency invariant for pools created with pre-existing staked SUI.
public fun solvency_base_staker<P: drop>() {
    let fee_config = nondet();
    let mut system_state = nondet();
    let lst_treasury_cap = nondet();
    let mut ctx = nondet();
    let fungible_staked_suis = nondet();
    let sui = nondet();
    let (cap, lsi) = liquid_staking::create_lst_with_stake<P>(
        &mut system_state,
        fee_config,
        lst_treasury_cap,
        fungible_staked_suis,
        sui,
        &mut ctx,
    );

    cvlm_assert(is_solvent(&lsi));

    ghost_destroy(cap);
    ghost_destroy(lsi);
    ghost_destroy(system_state);
}


/// Inductive step: Verifies that all state-modifying operations preserve protocol solvency.
/// Assumes the protocol is solvent in the pre-state and proves it remains solvent after the operation.
public fun solvency_step(
    target: Function,
    lsi: &mut LiquidStakingInfo<DummyToken>,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
) {
    cvlm_assume_msg(
        lsi.storage().validators().length() <= MAX_VALIDATORS,
        b"Restrict number of validators",
    );
    setup_fresh(lsi, system_state, ctx);

    cvlm_assume_msg(is_solvent(lsi), b"Assume solvency in pre state");
    cvlm_assume_msg(total_supply_correct(lsi.storage()), b"Correct accounting");

    validate_fees(lsi.fee_config());

    invoke(target, lsi, system_state, ctx);

    cvlm_assert(is_solvent(lsi));
}

public fun insolvency_bound(
    target: Function,
    lsi: &mut LiquidStakingInfo<DummyToken>,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
) {
    cvlm_assume_msg(
        lsi.storage().validators().length() <= MAX_VALIDATORS,
        b"Restrict number of validators",
    );
    setup_fresh(lsi, system_state, ctx);

    cvlm_assume_msg(is_solvent(lsi), b"Assume solvency in pre state");

    validate_fees(lsi.fee_config());

    invoke(target, lsi, system_state, ctx);

    cvlm_assert(lsi.total_lst_supply() +1 >= lsi.total_lst_supply());
}


/// Verifies that the SUI/LST exchange rate is non-decreasing across all operations.
/// This ensures LST holders never experience value dilution, as each LST token can always be
/// redeemed for at least as much SUI as it could previously.
public fun monotonicity(
    target: Function,
    lsi: &mut LiquidStakingInfo<DummyToken>,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
) {
    cvlm_assume_msg(
        lsi.storage().validators().length() <= MAX_VALIDATORS,
        b"Restrict number of validators",
    );
    setup_fresh(lsi, system_state, ctx);
    cvlm_assume_msg(total_supply_correct(lsi.storage()), b"Correct accounting");

    //cvlm_assume_msg(is_solvent(lsi), b"Assume solvency in pre state");

    let lst_pre = lsi.total_lst_supply();
    let sui_pre = lsi.total_sui_supply();

    cvlm_assume_msg(lst_pre > 0 && sui_pre > 0, b"Non-empty reserve");

    invoke(target, lsi, system_state, ctx);

    let lst_post = lsi.total_lst_supply();
    let sui_post = lsi.total_sui_supply();

    // sui_pre/lst_pre <= sui_post/lst_post
    // <==> sui_pre*lst_post <= sui_post*lst_pre

    cvlm_assert(sui_pre*lst_post <= sui_post*lst_pre);
}
