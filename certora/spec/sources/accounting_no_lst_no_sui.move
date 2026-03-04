/// Property: Token Supply Initialization Invariants
/// Description: Verifies that the liquid staking protocol maintains proper relationships between
/// LST (liquid staking token) and SUI supply. Specifically, this
/// ensures that an empty LST supply implies an empty SUI reserve (preventing orphaned SUI), and
/// conversely, that an empty SUI reserve implies no outstanding LST tokens (preventing unbacked tokens).

module spec::accounting_no_lst_no_sui;

use cvlm::asserts::{cvlm_assert, cvlm_assume_msg};
use cvlm::function::Function;
use cvlm::manifest::{target, invoker, rule};
use liquid_staking::liquid_staking::{LiquidStakingInfo};
use spec::dummy::DummyToken;
use sui_system::sui_system::SuiSystemState;
use spec::common::setup_fresh;
use spec::solvency::is_solvent;
use spec::accounting_total_sui_supply::total_supply_correct;
use cvlm::ghost::ghost_destroy;
use liquid_staking::liquid_staking::create_lst;
use cvlm::nondet::nondet;
use liquid_staking::liquid_staking::create_lst_with_stake;

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

    rule(b"no_lst_no_sui_step");
    rule(b"no_lst_no_sui_base");
    
    rule(b"no_sui_no_lst_base");
    rule(b"no_sui_no_lst_step");
}

const MAX_VALIDATORS: u64 = 1;

native fun invoke(
    target: Function,
    lis: &mut LiquidStakingInfo<DummyToken>,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
);


/// Checks that if there is no LST supply, then there is no SUI supply.
/// This prevents orphaned SUI that cannot be claimed through LST tokens.
public fun no_lst_no_sui<P>(lsi: &LiquidStakingInfo<P>): bool {
  let lst = lsi.total_lst_supply();
  let sui = lsi.total_sui_supply();
  // lst == 0 -> sui == 0 <==> lst != 0 || sui == 0
  lst != 0 || sui == 0
}

/// Checks that if there is no SUI supply, then there is no LST supply.
/// This prevents unbacked LST tokens that cannot be redeemed for SUI.
public fun no_sui_no_lst<P>(lsi: &LiquidStakingInfo<P>): bool {
  let lst = lsi.total_lst_supply();
  let sui = lsi.total_sui_supply();
  // sui == 0 -> lst == 0 <==> sui != 0 || lst == 0
  sui != 0 || lst == 0
}

/// Base case: Verifies that newly created liquid staking pools (both empty and with initial stake)
/// satisfy the invariant that zero LST supply implies zero SUI supply.
public fun no_lst_no_sui_base(
    ctx: &mut TxContext,
) {
    let fee_config = nondet();
    let lst_treasury_cap = nondet();    
    let (_cap, lsi) = create_lst<DummyToken>(fee_config, lst_treasury_cap, ctx);
    cvlm_assert(no_lst_no_sui(&lsi));

    ghost_destroy(lsi);
    ghost_destroy(_cap);

    let fee_config = nondet();
    let lst_treasury_cap = nondet();    
    let mut system_state = nondet();
    let fungible_staked_suis = nondet();
    let sui = nondet();
    let (_cap, lsi) = create_lst_with_stake<DummyToken>(&mut system_state, fee_config, lst_treasury_cap, fungible_staked_suis, sui, ctx);
    cvlm_assert(no_lst_no_sui(&lsi));

    ghost_destroy(lsi);
    ghost_destroy(_cap);
    ghost_destroy(system_state);

}

/// Inductive step: Verifies that all state-modifying operations preserve the invariant that
/// zero LST supply implies zero SUI supply. Assumes the system is solvent and has correct accounting
/// in the pre-state.
public fun no_lst_no_sui_step(
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


    cvlm_assume_msg(no_lst_no_sui(lsi), b"Assume in pre-state");


    invoke(target, lsi, system_state, ctx);



    cvlm_assert(no_lst_no_sui(lsi));
}


/// Base case: Verifies that newly created liquid staking pools (both empty and with initial stake)
/// satisfy the invariant that zero SUI supply implies zero LST supply.
public fun no_sui_no_lst_base(
    ctx: &mut TxContext,
) {
    let fee_config = nondet();
    let lst_treasury_cap = nondet();    
    let (_cap, lsi) = create_lst<DummyToken>(fee_config, lst_treasury_cap, ctx);
    cvlm_assert(no_sui_no_lst(&lsi));

    ghost_destroy(lsi);
    ghost_destroy(_cap);

    let fee_config = nondet();
    let lst_treasury_cap = nondet();    
    let mut system_state = nondet();
    let fungible_staked_suis = nondet();
    let sui = nondet();
    let (_cap, lsi) = create_lst_with_stake<DummyToken>(&mut system_state, fee_config, lst_treasury_cap, fungible_staked_suis, sui, ctx);
    cvlm_assert(no_sui_no_lst(&lsi));

    ghost_destroy(lsi);
    ghost_destroy(_cap);
    ghost_destroy(system_state);

}

/// Inductive step: Verifies that all state-modifying operations preserve the invariant that
/// zero SUI supply implies zero LST supply. Assumes the system is solvent and has correct accounting
/// in the pre-state.
public fun no_sui_no_lst_step(
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


    cvlm_assume_msg(no_sui_no_lst(lsi), b"Assume in pre-state");

    invoke(target, lsi, system_state, ctx);


    cvlm_assert(no_sui_no_lst(lsi));
}