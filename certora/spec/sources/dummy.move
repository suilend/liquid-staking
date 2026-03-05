module spec::dummy;


use liquid_staking::fees::FeeConfig;
use liquid_staking::liquid_staking::{LiquidStakingInfo, AdminCap, CustomRedeemRequest};
use std::ascii;
use std::string::String;
use sui::coin::{Coin, CoinMetadata};
use sui::sui::SUI;
use sui_system::sui_system::SuiSystemState;

public struct DummyToken has drop {}

public fun mint(
    self: &mut LiquidStakingInfo<DummyToken>,
    system_state: &mut SuiSystemState,
    sui: Coin<SUI>,
    ctx: &mut TxContext,
): Coin<DummyToken> {
    liquid_staking::liquid_staking::mint(self, system_state, sui, ctx)
}

public fun redeem(
    self: &mut LiquidStakingInfo<DummyToken>,
    lst: Coin<DummyToken>,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
): Coin<SUI> {
    liquid_staking::liquid_staking::redeem(self, lst, system_state, ctx)
}

public fun custom_redeem_request(
    self: &mut LiquidStakingInfo<DummyToken>,
    lst: Coin<DummyToken>,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
): CustomRedeemRequest<DummyToken> {
    liquid_staking::liquid_staking::custom_redeem_request(self, lst, system_state, ctx)
}

public fun custom_redeem(
    self: &mut LiquidStakingInfo<DummyToken>,
    request: CustomRedeemRequest<DummyToken>,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
): Coin<SUI> {
    liquid_staking::liquid_staking::custom_redeem(self, request, system_state, ctx)
}

public fun change_validator_priority(
    self: &mut LiquidStakingInfo<DummyToken>,
    cap: &AdminCap<DummyToken>,
    validator_index: u64,
    new_validator_index: u64,
) {
    liquid_staking::liquid_staking::change_validator_priority(
        self,
        cap,
        validator_index,
        new_validator_index,
    )
}

public fun increase_validator_stake(
    self: &mut LiquidStakingInfo<DummyToken>,
    cap: &AdminCap<DummyToken>,
    system_state: &mut SuiSystemState,
    validator_address: address,
    sui_amount: u64,
    ctx: &mut TxContext,
): u64 {
    liquid_staking::liquid_staking::increase_validator_stake(
        self,
        cap,
        system_state,
        validator_address,
        sui_amount,
        ctx,
    )
}

public fun decrease_validator_stake(
    self: &mut LiquidStakingInfo<DummyToken>,
    cap: &AdminCap<DummyToken>,
    system_state: &mut SuiSystemState,
    validator_address: address,
    target_unstake_sui_amount: u64,
    ctx: &mut TxContext,
): u64 {
    liquid_staking::liquid_staking::decrease_validator_stake(
        self,
        cap,
        system_state,
        validator_address,
        target_unstake_sui_amount,
        ctx,
    )
}

public fun collect_fees(
    self: &mut LiquidStakingInfo<DummyToken>,
    system_state: &mut SuiSystemState,
    _admin_cap: &AdminCap<DummyToken>,
    ctx: &mut TxContext,
): Coin<SUI> {
    liquid_staking::liquid_staking::collect_fees(self, system_state, _admin_cap, ctx)
}

public fun update_fees(
    self: &mut LiquidStakingInfo<DummyToken>,
    _admin_cap: &AdminCap<DummyToken>,
    fee_config: FeeConfig,
) {
    liquid_staking::liquid_staking::update_fees(self, _admin_cap, fee_config)
}

public fun refresh(
    self: &mut LiquidStakingInfo<DummyToken>,
    system_state: &mut SuiSystemState,
    ctx: &mut TxContext,
): bool {
    liquid_staking::liquid_staking::refresh(self, system_state, ctx)
}

public fun update_metadata(
    self: &mut LiquidStakingInfo<DummyToken>,
    cap: &AdminCap<DummyToken>,
    metadata: &mut CoinMetadata<DummyToken>,
    name: Option<String>,
    symbol: Option<ascii::String>,
    description: Option<String>,
    icon_url: Option<ascii::String>,
) {
    liquid_staking::liquid_staking::update_metadata(
        self,
        cap,
        metadata,
        name,
        symbol,
        description,
        icon_url,
    )
}
