/// Property: Fee Accounting Integrity
/// Description: Verifies that the protocol's fee accounting maintains critical invariants across all
/// operations. Accrued spread fees must never exceed the total SUI supply (preventing over-collection),
/// fees must grow monotonically except during collection operations (ensuring they are not lost), and
/// fees must never completely consume user deposits or redemptions (guaranteeing users always receive value).
/// These properties ensure the fee mechanism operates correctly without compromising user funds or
/// protocol accounting.

module spec::fees;

use cvlm::asserts::{cvlm_assert, cvlm_assume_msg};
use cvlm::function::Function;
use cvlm::ghost::ghost_destroy;
use cvlm::manifest::{rule, target, invoker};
use cvlm::nondet::nondet;
use liquid_staking::fees::validate_fees;
use liquid_staking::liquid_staking::LiquidStakingInfo;
use spec::common::setup_fresh;
use spec::dummy::DummyToken;
use sui::coin::Coin;
use sui::sui::SUI;
use sui_system::sui_system::SuiSystemState;
use liquid_staking::liquid_staking::create_lst;

public fun cvlm_manifest() {
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

    rule(b"spread_fees_dont_exceed_sui_supply_base");
    rule(b"spread_fees_dont_exceed_sui_supply_step");
    
    rule(b"fees_grow_monotonically");
    
    rule(b"fees_dont_eat_deposit");
    rule(b"fees_dont_eat_redemption");
}

native fun invoke(
    target: Function,
    lsi: &mut LiquidStakingInfo<DummyToken>,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
);

/// Base case: Verifies that for newly created pools, accrued spread fees do not exceed the total SUI supply.
/// This establishes the initial state for the fee accounting invariant.
public fun spread_fees_dont_exceed_sui_supply_base(
    ctx: &mut TxContext,
) {
    let fee_config = nondet();
    let lst_treasury_cap = nondet();    
    let (_cap, lsi) = create_lst<DummyToken>(fee_config, lst_treasury_cap, ctx);
    let spread_fees = lsi.fees();
    let sui = lsi.storage().total_sui_supply();
    cvlm_assert(spread_fees <= sui);

    ghost_destroy(_cap);
    ghost_destroy(lsi);

}

/// Inductive step: Verifies that all operations preserve the invariant that accrued spread fees
/// do not exceed the total SUI supply. This prevents the protocol from claiming fees it cannot honor.
public fun spread_fees_dont_exceed_sui_supply_step(
    target: Function,
    lsi: &mut LiquidStakingInfo<DummyToken>,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
) {
    // This already assumes spread_fees < storage.sui_supply, we'll make it explicit nevertheless
    setup_fresh(lsi, system_state, ctx);
    validate_fees(lsi.fee_config()); 
    let spread_fees_pre = lsi.accrued_spread_fees();
    let sui_pre = lsi.storage().total_sui_supply();

    cvlm_assume_msg(spread_fees_pre <= sui_pre, b"Assume in precondition");

    invoke(target, lsi, system_state, ctx);

    let spread_fees_post = lsi.accrued_spread_fees();
    let sui_post = lsi.storage().total_sui_supply();

    cvlm_assert(spread_fees_post <= sui_post);
}

/// Verifies that accrued fees either remain constant or increase across all operations, except
/// during explicit fee collection. This ensures fees are not lost or incorrectly reduced during operations.
public fun fees_grow_monotonically(
    target: Function,
    lsi: &mut LiquidStakingInfo<DummyToken>,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
) {
    setup_fresh(lsi, system_state, ctx);
    validate_fees(lsi.fee_config());
    let spread_fees_pre = lsi.fees();

    invoke(target, lsi, system_state, ctx);

    let spread_fees_post = lsi.fees();

    let collected = target.name() == b"collect_fees";
    let increased = spread_fees_post >= spread_fees_pre;

    // !collected -> increased <==> collected || increased
    cvlm_assert(collected || increased);
}

/// Verifies that redemption fees do not completely consume the user's redemption, ensuring users
/// always receive a non-zero amount of SUI when redeeming non-zero LST tokens.
public fun fees_dont_eat_redemption(
    lsi: &mut LiquidStakingInfo<DummyToken>,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
) {
    setup_fresh(lsi, system_state, ctx);
    validate_fees(lsi.fee_config());

    let coin: Coin<DummyToken> = nondet();

    let fees_pre = lsi.fees();

    cvlm_assume_msg(coin.value() > 0, b"Non-zero value");
    let sui = lsi.redeem(coin, system_state, ctx);

    let fees = lsi.fees() - fees_pre;

    cvlm_assume_msg(sui.value() + fees > 0, b"No lost funds");
    cvlm_assert(sui.value() > 0);
    ghost_destroy(sui);
}

/// Verifies that deposit fees do not completely consume the user's deposit, ensuring users
/// always receive a non-zero amount of LST tokens when depositing non-zero SUI.
public fun fees_dont_eat_deposit(
    lsi: &mut LiquidStakingInfo<DummyToken>,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
) {
    setup_fresh(lsi, system_state, ctx);
    validate_fees(lsi.fee_config());

    let coin: Coin<SUI> = nondet();

    let fees_pre = lsi.fees();

    cvlm_assume_msg(coin.value() > 0, b"Non-zero value");
    let lst = lsi.mint(system_state, coin, ctx);
    let fees = lsi.fees() - fees_pre;

    cvlm_assume_msg(lst.value()+fees > 0, b"No lost funds");
    cvlm_assert(lst.value() > 0);
    ghost_destroy(lst);
}
