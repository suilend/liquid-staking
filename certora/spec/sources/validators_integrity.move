/// Property: Validator Registry Integrity
/// Description: Verifies integrity properties of validator registry operations. Rules check that:
/// (1) validators can only be added through authorized staking operations (join_stake, join_fungible_stake)
/// or explicit validator addition (get_or_add_validator_index_by_staking_pool_id_mut), preventing
/// unauthorized registry modifications; (2) validators can only be removed through refresh operations;
/// (3) at most one validator can be added per operation; (4) after refresh, no inactive stake remains
/// in the registry; (5) after refresh, no empty validators remain in the registry.
/// These rules verify correct authorization and post-conditions for validator registry modifications.

module spec::validators_integrity;

use cvlm::asserts::{cvlm_assert, cvlm_assume_msg};
use cvlm::function::Function;
use cvlm::manifest::{target, invoker, rule};
use cvlm::nondet::nondet;
use liquid_staking::liquid_staking::LiquidStakingInfo;
use liquid_staking::storage::{Storage};
use spec::common::{setup};
use spec::dummy::DummyToken;
use sui_system::sui_system::SuiSystemState;
use spec::validators_consistency::no_stake_no_sui;

public fun cvlm_manifest() {
    // Public mut functions

    target(@liquid_staking, b"storage", b"refresh");
    target(@liquid_staking, b"storage", b"change_validator_priority");
    target(@liquid_staking, b"storage", b"join_to_sui_pool");
    target(@liquid_staking, b"storage", b"join_stake");
    target(@liquid_staking, b"storage", b"join_fungible_stake");
    target(@liquid_staking, b"storage", b"join_inactive_stake_to_validator");
    target(@liquid_staking, b"storage", b"join_fungible_staked_sui_to_validator");
    target(@liquid_staking, b"storage", b"split_up_to_n_sui_from_sui_pool");
    target(@liquid_staking, b"storage", b"split_from_sui_pool");
    target(@liquid_staking, b"storage", b"unstake_approx_n_sui_from_validator");
    target(@liquid_staking, b"storage", b"unstake_approx_n_sui_from_active_stake");
    target(@liquid_staking, b"storage", b"unstake_approx_n_sui_from_inactive_stake");
    target(@liquid_staking, b"storage", b"split_n_sui");
    target(@liquid_staking, b"storage", b"get_or_add_validator_index_by_staking_pool_id_mut");

    invoker(b"invoke");

    rule(b"can_add_correct");
    rule(b"can_remove_correct");
    rule(b"add_at_most_one");

    rule(b"no_inactive_stake_after_refresh");
    rule(b"no_empty_validators_after_refresh");
}

native fun invoke(
    target: Function,
    strg: &mut Storage,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
);


fun can_add_validator(target: Function): bool {
    target.name() == b"get_or_add_validator_index_by_staking_pool_id_mut"
    || target.name() == b"join_stake"
    || target.name() == b"join_fungible_stake"
}

fun can_remove_validator(target: Function): bool {
    target.name() == b"refresh"
}

/// Verifies that validators can only be added to the registry through explicitly authorized operations
/// (staking operations and direct validator addition), preventing unauthorized registry modifications.
public fun can_add_correct(
    target: Function,
    strg: &mut Storage,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
) {
    let validators_pre = strg.validators().length();
    invoke(target, strg, system_state, ctx);
    let validators_post = strg.validators().length();

    let appended = validators_post > validators_pre;
    let allowed = can_add_validator(target);

    cvlm_assert(!appended || allowed);
}

/// Verifies that validators can only be removed from the registry through the refresh operation,
/// which cleans up empty validators, preventing unauthorized validator removal.
public fun can_remove_correct(
    target: Function,
    strg: &mut Storage,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
) {
    let validators_pre = strg.validators().length();
    invoke(target, strg, system_state, ctx);
    let validators_post = strg.validators().length();

    let removed = validators_post < validators_pre;
    let allowed = can_remove_validator(target);

    cvlm_assert(!removed || allowed);
}



/// Verifies that any single operation can add at most one validator to the registry,
/// preventing bulk additions that could bypass validation logic.
public fun add_at_most_one(
    target: Function,
    strg: &mut Storage,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
) {
    let validators_pre = strg.validators().length();
    invoke(target, strg, system_state, ctx);
    let validators_post = strg.validators().length();

    cvlm_assert(validators_post <= validators_pre + 1);
}


/// Verifies that after a refresh operation completes, no validators in the registry contain
/// inactive stake, ensuring all stake has been properly activated or removed.
public fun no_inactive_stake_after_refresh(
    lsi: &mut LiquidStakingInfo<DummyToken>,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
) {
    setup(lsi);
    cvlm_assume_msg(ctx.epoch() > lsi.storage().last_refresh_epoch(), b"Force refresh");

    lsi.refresh(system_state, ctx);

    let i = nondet();
    cvlm_assume_msg(i < lsi.storage().validators().length(), b"");

    let inactive = lsi.storage().validators()[i].inactive_stake();
    cvlm_assert(inactive.is_none());
}

/// Verifies that after a refresh operation completes, no validators in the registry are empty
/// (containing no stake), ensuring clean state and accurate registry size.
public fun no_empty_validators_after_refresh(
    lsi: &mut LiquidStakingInfo<DummyToken>,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
) {
    setup(lsi);
    cvlm_assume_msg(ctx.epoch() > lsi.storage().last_refresh_epoch(), b"Force refresh");
    cvlm_assume_msg(no_stake_no_sui(lsi.storage()), b"Assume in pre state");
    

    lsi.refresh(system_state, ctx);

    let i = nondet();
    cvlm_assume_msg(i < lsi.storage().validators().length(), b"");
    let validator = &lsi.storage().validators()[i];

    cvlm_assert(!validator.is_empty());
}
