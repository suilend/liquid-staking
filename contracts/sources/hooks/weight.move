/// This module allows for the dynamic rebalancing of validator stakes based
/// on a set of validator addresses and weights. Rebalance can be called permissionlessly
module liquid_staking::weight {
    use liquid_staking::{
        events::emit_event,
        fees::FeeConfig,
        liquid_staking::{LiquidStakingInfo, AdminCap, CustomRedeemRequest},
        registry::Registry,
        version::{Self, Version}
    };
    use std::{ascii, string::String, type_name::{Self, TypeName}};
    use sui::{bag::{Self, Bag}, coin::Coin, package, sui::SUI, vec_map::{Self, VecMap}};
    use sui_system::sui_system::SuiSystemState;

    /* Constants */
    const CURRENT_VERSION: u16 = 1;

    public struct WeightHook<phantom P> has key, store {
        id: UID,
        validator_addresses_and_weights: VecMap<address, u64>,
        total_weight: u64,
        admin_cap: AdminCap<P>,
        version: Version,
        extra_fields: Bag,
    }

    public struct WeightHookAdminCap<phantom P> has key, store {
        id: UID,
    }

    public struct WEIGHT has drop {}

    public struct RegistryInfo has store {
        weight_hook_id: ID,
    }

    /* Events */
    public struct CreateEvent has copy, drop {
        typename: TypeName,
        weight_hook_id: ID,
        weight_hook_admin_cap_id: ID,
    }

    fun init(otw: WEIGHT, ctx: &mut TxContext) {
        package::claim_and_keep(otw, ctx)
    }

    public fun new<P>(
        admin_cap: AdminCap<P>,
        ctx: &mut TxContext,
    ): (WeightHook<P>, WeightHookAdminCap<P>) {
        let weight_hook = WeightHook {
            id: object::new(ctx),
            validator_addresses_and_weights: vec_map::empty(),
            total_weight: 0,
            admin_cap,
            version: version::new(CURRENT_VERSION),
            extra_fields: bag::new(ctx),
        };
        let weight_hook_admin_cap = WeightHookAdminCap { id: object::new(ctx) };

        emit_event(CreateEvent {
            typename: type_name::with_defining_ids<P>(),
            weight_hook_id: *weight_hook.id.as_inner(),
            weight_hook_admin_cap_id: *weight_hook_admin_cap.id.as_inner(),
        });

        (weight_hook, weight_hook_admin_cap)
    }

    public fun add_to_registry<P>(
        self: &WeightHook<P>,
        registry: &mut Registry,
        liquid_staking_info: &LiquidStakingInfo<P>,
    ) {
        registry.add_to_registry(
            &self.admin_cap,
            liquid_staking_info,
            RegistryInfo {
                weight_hook_id: *self.id.as_inner(),
            },
        );
    }

    public fun set_validator_addresses_and_weights<P>(
        self: &mut WeightHook<P>,
        _: &WeightHookAdminCap<P>,
        validator_addresses_and_weights: VecMap<address, u64>,
    ) {
        self.version.assert_version_and_upgrade(CURRENT_VERSION);
        self.validator_addresses_and_weights = validator_addresses_and_weights;

        let mut total_weight = 0;
        self.validator_addresses_and_weights.keys().length().do!(|i| {
            let (_, weight) = self.validator_addresses_and_weights.get_entry_by_idx(i);
            total_weight = total_weight + *weight;
        });

        self.total_weight = total_weight;
    }

    public fun update_fees<P>(
        self: &mut WeightHook<P>,
        _: &WeightHookAdminCap<P>,
        liquid_staking_info: &mut LiquidStakingInfo<P>,
        fee_config: FeeConfig,
    ) {
        self.version.assert_version_and_upgrade(CURRENT_VERSION);

        liquid_staking_info.update_fees(&self.admin_cap, fee_config);
    }

    public fun collect_fees<P>(
        self: &mut WeightHook<P>,
        _: &WeightHookAdminCap<P>,
        liquid_staking_info: &mut LiquidStakingInfo<P>,
        system_state: &mut SuiSystemState,
        ctx: &mut TxContext,
    ): Coin<SUI> {
        self.version.assert_version_and_upgrade(CURRENT_VERSION);

        liquid_staking_info.collect_fees(system_state, &self.admin_cap, ctx)
    }

    public fun rebalance<P>(
        self: &mut WeightHook<P>,
        system_state: &mut SuiSystemState,
        liquid_staking_info: &mut LiquidStakingInfo<P>,
        ctx: &mut TxContext,
    ) {
        liquid_staking_info.refresh(system_state, ctx);
        let total_sui_supply = liquid_staking_info.storage().total_sui_supply(); // we want to allocate the unaccrued spread fees as well

        self.rebalance_internal(system_state, liquid_staking_info, total_sui_supply, ctx)
    }

    public fun handle_custom_redeem_request<P>(
        self: &mut WeightHook<P>,
        system_state: &mut SuiSystemState,
        liquid_staking_info: &mut LiquidStakingInfo<P>,
        request: &mut CustomRedeemRequest<P>,
        ctx: &mut TxContext,
    ) {
        liquid_staking_info.refresh(system_state, ctx);

        let total_sui_supply = liquid_staking_info.storage().total_sui_supply(); // we want to allocate the unaccrued spread fees as well
        let sui_unstake_amount = liquid_staking_info.lst_amount_to_sui_amount(request
            .lst()
            .value());
        let total_sui_to_allocate = total_sui_supply - sui_unstake_amount;

        self.rebalance_internal(system_state, liquid_staking_info, total_sui_to_allocate, ctx);
        self.admin_cap.mark_redeem_request_as_processed(request);
    }

    public fun update_metadata<P>(
        self: &WeightHook<P>,
        _: &WeightHookAdminCap<P>,
        liquid_staking_info: &mut LiquidStakingInfo<P>,
        metadata: &mut sui::coin::CoinMetadata<P>,
        name: Option<String>,
        symbol: Option<ascii::String>,
        description: Option<String>,
        icon_url: Option<ascii::String>,
    ) {
        let admin_cap = &self.admin_cap;

        liquid_staking_info.update_metadata(
            admin_cap,
            metadata,
            name,
            symbol,
            description,
            icon_url,
        );
    }

    fun rebalance_internal<P>(
        self: &mut WeightHook<P>,
        system_state: &mut SuiSystemState,
        liquid_staking_info: &mut LiquidStakingInfo<P>,
        total_sui_to_allocate: u64,
        ctx: &mut TxContext,
    ) {
        self.version.assert_version_and_upgrade(CURRENT_VERSION);
        if (self.total_weight == 0) {
            return
        };

        let mut validator_addresses_and_weights = self.validator_addresses_and_weights;

        // 1. add all validators that exist in lst_info.validators() to the validator_address_to_weight map if they don't already exist
        liquid_staking_info.storage().validators().do_ref!(|validator| {
            let validator_address = validator.validator_address();
            if (!validator_addresses_and_weights.contains(&validator_address)) {
                validator_addresses_and_weights.insert(validator_address, 0);
            };
        });

        // 2. calculate current and target amounts of sui for each validator
        let (
            validator_addresses,
            validator_weights,
        ) = validator_addresses_and_weights.into_keys_values();

        let validator_target_amounts = validator_weights.map!(|weight| {
            (
                (total_sui_to_allocate as u128) * (weight as u128) / (self.total_weight as u128),
            ) as u64
        });

        let validator_current_amounts = validator_addresses.map_ref!(|validator_address| {
            let validator_index = liquid_staking_info
                .storage()
                .find_validator_index_by_address(*validator_address);
            if (validator_index >= liquid_staking_info.storage().validators().length()) {
                return 0
            };

            let validator = liquid_staking_info.storage().validators().borrow(validator_index);
            validator.total_sui_amount()
        });

        // 3. decrease the stake for validators that have more stake than the target amount
        validator_addresses.length().do!(|i| {
            if (validator_current_amounts[i] > validator_target_amounts[i]) {
                liquid_staking_info.decrease_validator_stake(
                    &self.admin_cap,
                    system_state,
                    validator_addresses[i],
                    validator_current_amounts[i] - validator_target_amounts[i],
                    ctx,
                );
            };
        });

        // 4. increase the stake for validators that have less stake than the target amount
        validator_addresses.length().do!(|i| {
            if (validator_current_amounts[i] < validator_target_amounts[i]) {
                liquid_staking_info.increase_validator_stake(
                    &self.admin_cap,
                    system_state,
                    validator_addresses[i],
                    validator_target_amounts[i] - validator_current_amounts[i],
                    ctx,
                );
            };
        });
    }

    public fun eject<P>(mut self: WeightHook<P>, admin_cap: WeightHookAdminCap<P>): AdminCap<P> {
        self.version.assert_version_and_upgrade(CURRENT_VERSION);

        let WeightHookAdminCap { id } = admin_cap;
        object::delete(id);

        let WeightHook { id, admin_cap, extra_fields, .. } = self;
        extra_fields.destroy_empty();
        object::delete(id);

        admin_cap
    }

    public fun admin_cap<P>(self: &WeightHook<P>, _: &WeightHookAdminCap<P>): &AdminCap<P> {
        self.version.assert_version(CURRENT_VERSION);

        &self.admin_cap
    }

    public fun weight_hook_id(self: &RegistryInfo): ID {
        self.weight_hook_id
    }
}
