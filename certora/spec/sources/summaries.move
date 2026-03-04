module spec::summaries;

use cvlm::asserts::{cvlm_assume_msg, cvlm_assert};
use cvlm::ghost::ghost_destroy;
use cvlm::manifest::{summary, ghost};
use cvlm::nondet::nondet;
use liquid_staking::storage::{Self, Storage};
use liquid_staking::version::Version;
use std::option::some;
use sui::balance::Balance;
use sui::object::id;
use sui::sui::SUI;
use sui::tx_context::epoch;
use sui_system::staking_pool::{PoolTokenExchangeRate, StakedSui, StakingPool, FungibleStakedSui};
use sui_system::sui_system::SuiSystemState;

public fun cvlm_manifest() {
    ghost(b"exchange_rate");
    summary(b"get_latest_exchange_rate", @liquid_staking, b"storage", b"get_latest_exchange_rate");
    ghost(b"validator_index");
    summary(
        b"find_validator_index_by_address",
        @liquid_staking,
        b"storage",
        b"find_validator_index_by_address",
    );

    summary(
        b"pool_token_exchange_rate_at_epoch",
        @sui_system,
        b"staking_pool",
        b"pool_token_exchange_rate_at_epoch",
    );

    ghost(b"fungible_total_supply");
    ghost(b"fungible_total_principal");

    summary(
        b"convert_to_fungible_staked_sui",
        @sui_system,
        b"sui_system",
        b"convert_to_fungible_staked_sui",
    );
    summary(
        b"redeem_fungible_staked_sui",
        @sui_system,
        b"sui_system",
        b"redeem_fungible_staked_sui",
    );
    ghost(b"active_validators");
    summary(
        b"active_validator_addresses",
        @sui_system,
        b"sui_system",
        b"active_validator_addresses",
    );
    summary(
        b"request_withdraw_stake_non_entry",
        @sui_system,
        b"sui_system",
        b"request_withdraw_stake_non_entry",
    );

    summary(
        b"assert_version_and_upgrade",
        @liquid_staking,
        b"version",
        b"assert_version_and_upgrade",
    );
}

native fun validator_index(validator_address: address): u64;
public(package) fun find_validator_index_by_address(
    self: &Storage,
    validator_address: address,
): u64 {
    let i = validator_index(validator_address);
    cvlm_assume_msg(i < self.validators().length(), b"Validator exists");
    cvlm_assume_msg(
        self.validators()[i].validator_address() == validator_address,
        b"Address is consistent",
    );
    return i
}

native fun exchange_rate(epoch: u64, staking_pool_id: &ID): PoolTokenExchangeRate;

fun get_exr(epoch: u64, staking_pool_id: &ID): PoolTokenExchangeRate {
    let er: PoolTokenExchangeRate = exchange_rate(epoch, staking_pool_id);
    cvlm_assume_msg(er.sui_amount() >= er.pool_token_amount(), b"solvent");
    er
}

native fun fungible_total_supply(pool: ID): &mut u64;
native fun fungible_total_principal(pool: ID): &mut u64;

public fun convert_to_fungible_staked_sui(
    _: &mut SuiSystemState,
    staked_sui: StakedSui,
    ctx: &mut TxContext,
): FungibleStakedSui {
    let id = staked_sui.pool_id();
    let epoch = ctx.epoch();

    let principal = staked_sui.staked_sui_amount();

    let fss: FungibleStakedSui = nondet();

    let er = get_exr(epoch, &id);
    let pool_token_amount = get_token_amount(&er, principal);

    cvlm_assume_msg(fss.pool_id() == id, b"Correct id");
    cvlm_assume_msg(fss.value() == pool_token_amount, b"Correct value");

    // Update fungible token data
    let f_total = fungible_total_supply(id);
    let f_principal = fungible_total_supply(id);
    *f_total = *f_total + pool_token_amount;
    *f_principal = *f_principal + principal;

    ghost_destroy(staked_sui);

    fss
}

public fun redeem_fungible_staked_sui(
    _wrapper: &mut SuiSystemState,
    fungible_staked_sui: FungibleStakedSui,
    ctx: &TxContext,
): Balance<SUI> {
    let id = fungible_staked_sui.pool_id();
    let epoch = ctx.epoch();
    let value = fungible_staked_sui.value();

    let principal = *fungible_total_principal(id);
    cvlm_assume_msg(principal >= value, b"");

    let total_supply = *fungible_total_supply(id);
    cvlm_assume_msg(total_supply >= principal, b"");

    let er = get_exr(epoch, &id);

    // let (
    //     principal_amount,
    //     rewards_amount,
    // ) = calculate_fungible_staked_sui_withdraw_amount(
    //     er,
    //     value,
    //     principal,
    //     total_supply,
    // );
    //let total_withdraw = principal_amount+rewards_amount;

    let total_withdraw = get_sui_amount(er, value);

    //fungible_staked_sui_data.total_supply = fungible_staked_sui_data.total_supply - value;

    let sui_out: Balance<SUI> = nondet();
    cvlm_assume_msg(sui_out.value() == total_withdraw, b"");
    // = fungible_staked_sui_data.principal.split(principal_amount);
    // sui_out.join(pool.rewards_pool.split(rewards_amount));

    // pool.pending_total_sui_withdraw = pool.pending_total_sui_withdraw + sui_out.value();
    // pool.pending_pool_token_withdraw = pool.pending_pool_token_withdraw + value;
    ghost_destroy(fungible_staked_sui);
    sui_out
}

public(package) fun calculate_fungible_staked_sui_withdraw_amount(
    latest_exchange_rate: PoolTokenExchangeRate,
    fungible_staked_sui_value: u64,
    fungible_staked_sui_data_principal_amount: u64, // fungible_staked_sui_data.principal.value()
    fungible_staked_sui_data_total_supply: u64, // fungible_staked_sui_data.total_supply
): (u64, u64) {
    // 1. if the entire FungibleStakedSuiData supply is redeemed, how much sui should we receive?
    let total_sui_amount = get_sui_amount(
        latest_exchange_rate,
        fungible_staked_sui_data_total_supply,
    ); // == fungible_staked_sui_data_principal_amount + rewards

    // min with total_sui_amount to prevent underflow
    // let fungible_staked_sui_data_principal_amount = fungible_staked_sui_data_principal_amount.min(
    //     total_sui_amount,
    // );

    cvlm_assume_msg(
        fungible_staked_sui_data_principal_amount <= total_sui_amount,
        b"Principal amount is less than total sui amount",
    );

    // 2. how much do we need to withdraw from the rewards pool?
    let total_rewards = total_sui_amount - fungible_staked_sui_data_principal_amount;

    // 3. proportionally withdraw from both wrt the fungible_staked_sui_value.
    let principal_withdraw_amount =
        (fungible_staked_sui_value*fungible_staked_sui_data_principal_amount)/fungible_staked_sui_data_total_supply;

    let rewards_withdraw_amount =
        (fungible_staked_sui_value*total_rewards)/fungible_staked_sui_data_total_supply;

    // invariant check, just in case
    let expected_sui_amount = get_sui_amount(latest_exchange_rate, fungible_staked_sui_value);
    cvlm_assert(
        principal_withdraw_amount + rewards_withdraw_amount <= expected_sui_amount,
    );

    (principal_withdraw_amount, rewards_withdraw_amount)
}

fun get_token_amount(exchange_rate: &PoolTokenExchangeRate, sui_amount: u64): u64 {
    // When either amount is 0, that means we have no stakes with this pool.
    // The other amount might be non-zero when there's dust left in the pool.
    if (exchange_rate.sui_amount() == 0 || exchange_rate.pool_token_amount() == 0) {
        return sui_amount
    };

    (exchange_rate.pool_token_amount()* sui_amount) / exchange_rate.sui_amount()
}

fun get_sui_amount(exchange_rate: PoolTokenExchangeRate, token_amount: u64): u64 {
    // When either amount is 0, that means we have no stakes with this pool.
    // The other amount might be non-zero when there's dust left in the pool.
    if (exchange_rate.sui_amount() == 0 || exchange_rate.pool_token_amount() == 0) {
        return token_amount
    };

    (exchange_rate.sui_amount()* token_amount) / exchange_rate.pool_token_amount()
}

public(package) fun get_latest_exchange_rate(
    _self: &Storage,
    staking_pool_id: &ID,
    _system_state: &mut SuiSystemState,
    ctx: &TxContext,
): Option<PoolTokenExchangeRate> { some(get_exr(ctx.epoch(), staking_pool_id)) }

public fun pool_token_exchange_rate_at_epoch(
    pool: &StakingPool,
    epoch: u64,
): PoolTokenExchangeRate {
    let id = id(pool);
    some(get_exr(epoch, &id)).destroy_some()
}

public native fun active_validators(): vector<address>;

public fun active_validator_addresses(_wrapper: &mut SuiSystemState): vector<address> {
    active_validators()
}

public fun request_withdraw_stake_non_entry(
    _wrapper: &mut SuiSystemState,
    staked_sui: StakedSui,
    ctx: &mut TxContext,
): Balance<SUI> {
    let exr = get_exr(ctx.epoch(), &staked_sui.pool_id());
    let am = storage::get_sui_amount(&exr, staked_sui.amount());

    let w: Balance<SUI> = nondet();
    cvlm_assume_msg(w.value() == am, b"Exchange");
    ghost_destroy(staked_sui);
    w
}

public(package) fun assert_version_and_upgrade(_version: &mut Version, _current_version: u16) {}
