module spec::common;

use cvlm::asserts::cvlm_assume_msg;
use cvlm::function::Function;
use liquid_staking::liquid_staking::LiquidStakingInfo;
use spec::summaries::{active_validators};
use sui_system::sui_system::SuiSystemState;
use liquid_staking::storage::inactive_stake;
use liquid_staking::storage::get_sui_amount;

public fun setup<T>(
    lsi: &mut LiquidStakingInfo<T>,
) {
    let mut i = 0;
    while (i < lsi.storage().validators().length()) {
        let validator = &lsi.storage().validators()[i];
        let pool_id = validator.staking_pool_id();
        let active = validator.active_stake();
        let inactive = lsi.storage().validators()[i].inactive_stake();
        if (active.is_some()) {
            cvlm_assume_msg(active.borrow().pool_id() == pool_id, b"Matching pool ids");
        };
        if (inactive.is_some()) {
            cvlm_assume_msg(inactive.borrow().pool_id() == pool_id, b"Matching pool ids");
        };

        i = i+1;
    };
}


public fun setup_fresh<T>(
    lsi: &mut LiquidStakingInfo<T>,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
) {
    let mut total_sui_supply = 0;

    let validator_addresses = active_validators();

    let mut i = 0;
    while (i < lsi.storage().validators().length()) {
        let validator = &lsi.storage().validators()[i];
        let pool_id = validator.staking_pool_id();
        let active = validator.active_stake();
        let inactive = lsi.storage().validators()[i].inactive_stake();
        
        // There is no inactive state after a call to refresh
        // This is verified in the rule "no_inactive_stake_after_refresh"
        cvlm_assume_msg(inactive.is_none(), b"No inactive stake");
        
        // There are no empty validators after a call to refresh.
        // This is verified in the rule "no_empty_validators_after_refresh"
        // Since there is no inactive stake for this validator, not empty is equivalent to non-zero active stake.
        // This is verified in the invariant "no_stake_no_sui"
        cvlm_assume_msg(active.is_some(), b"No empty validator");
        let active = active.borrow();
        cvlm_assume_msg(active.pool_id() == pool_id, b"Matching pool ids");
       

        cvlm_assume_msg(
            validator_addresses.contains(&validator.validator_address()),
            b"Validator is active",
        );


        // We assume an exchange rate for this epoch exists
        let er = lsi
            .storage()
            .get_latest_exchange_rate(&validator.staking_pool_id(), system_state, ctx)
            .destroy_some();
        cvlm_assume_msg(validator.exchange_rate() == er, b"Validator has latest exchange rate");

        let active_sui_amount = get_sui_amount(&er, active.value());
        cvlm_assume_msg(validator.total_sui_amount() == active_sui_amount, b"Valid amount");

        total_sui_supply = total_sui_supply + active_sui_amount;

        i = i+1;
    };
    
    cvlm_assume_msg(lsi.storage().total_sui_supply() == total_sui_supply, b"Correct total sui supply");
    cvlm_assume_msg(lsi.storage().last_refresh_epoch() == ctx.epoch(), b"Set last refresh");    
}


public fun log<T>(_: &T) {}

public fun can_decrease_supply(f: Function): bool {
    f.name() == b"redeem" || f.name() == b"custom_redeem"
}

public fun can_increase_supply(f: Function): bool {
    f.name() == b"mint"
}
