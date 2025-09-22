#[test_only]
module liquid_staking::weight_tests {
    /* Tests */
    use sui::vec_map::{Self};
    use sui::test_scenario::{Self, Scenario};
    use sui::coin::{Self};
    use sui::address;
    use sui_system::governance_test_utils::{
        create_sui_system_state_for_testing,
        advance_epoch_with_reward_amounts,
    };
    use sui_system::sui_system::{SuiSystemState};
    use sui_system::staking_pool::StakedSui;
    const MIST_PER_SUI: u64 = 1_000_000_000;
    use liquid_staking::fees::{Self};
    use liquid_staking::liquid_staking::{create_lst};
    use liquid_staking::weight::{Self, WeightHook};
    use liquid_staking::test_utils::create_validators_with_stakes;

    public struct TEST has drop {}

    #[test_only]
    public fun stake_with(validator_index: u64, amount: u64, scenario: &mut Scenario): StakedSui {
        scenario.next_tx(@0x0);

        let mut system_state = scenario.take_shared<SuiSystemState>();

        let ctx = scenario.ctx();

        let staked_sui = system_state.request_add_stake_non_entry(
            coin::mint_for_testing(amount * MIST_PER_SUI, ctx), 
            address::from_u256(validator_index as u256), 
            ctx
        );

        test_scenario::return_shared(system_state);
        scenario.next_tx(@0x0);

        staked_sui
    }

    #[allow(deprecated_usage)]
    #[test_only]
    fun setup_sui_system(scenario: &mut Scenario, stakes: vector<u64>) {
        let validators = create_validators_with_stakes(stakes, scenario.ctx());
        create_sui_system_state_for_testing(validators, 0, 0, scenario.ctx());

        advance_epoch_with_reward_amounts(0, 0, scenario);
    }


     #[test]
     fun test_rebalance() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100, 100]);
        scenario.next_tx(@0x0);

        let (admin_cap, mut lst_info) = create_lst<TEST>(
            fees::new_builder(scenario.ctx()).to_fee_config(),
            coin::create_treasury_cap_for_testing(scenario.ctx()),
            scenario.ctx()
        );

        let mut system_state = scenario.take_shared<SuiSystemState>();
        let sui = coin::mint_for_testing(100 * MIST_PER_SUI, scenario.ctx());
        let lst = lst_info.mint(&mut system_state, sui, scenario.ctx());

        assert!(lst_info.total_lst_supply() == 100 * MIST_PER_SUI, 0);
        assert!(lst_info.storage().total_sui_supply() == 100 * MIST_PER_SUI, 0);

        let (mut weight_hook, weight_hook_admin_cap) = weight::new(admin_cap, scenario.ctx());

        weight_hook.set_validator_addresses_and_weights(
            &weight_hook_admin_cap, 
            {
                let mut map = vec_map::empty();
                map.insert(address::from_u256(0), 100);
                map.insert(address::from_u256(1), 300);

                map
            }
        );

        weight_hook.rebalance(&mut system_state, &mut lst_info, scenario.ctx());

        assert!(lst_info.storage().validators().borrow(0).total_sui_amount() == 25 * MIST_PER_SUI, 0);
        assert!(lst_info.storage().validators().borrow(1).total_sui_amount() == 75 * MIST_PER_SUI, 0);

        weight_hook.set_validator_addresses_and_weights(
            &weight_hook_admin_cap, 
            {
                let mut map = vec_map::empty();
                map.insert(address::from_u256(2), 100);

                map
            }
        );
        weight_hook.rebalance(&mut system_state, &mut lst_info, scenario.ctx());

        assert!(lst_info.storage().validators().borrow(0).total_sui_amount() == 0, 0);
        assert!(lst_info.storage().validators().borrow(1).total_sui_amount() == 0, 0);
        assert!(lst_info.storage().validators().borrow(2).total_sui_amount() == 100 * MIST_PER_SUI, 0);

        // test update fees
        let new_fees = fees::new_builder(scenario.ctx()).set_sui_mint_fee_bps(100).to_fee_config();
        weight_hook.update_fees(&weight_hook_admin_cap, &mut lst_info, new_fees);

        assert!(lst_info.fee_config().sui_mint_fee_bps() == 100, 0);

        // mint some lst
        let sui = coin::mint_for_testing(100 * MIST_PER_SUI, scenario.ctx());
        let lst2 = lst_info.mint(&mut system_state, sui, scenario.ctx());

        // test collect fees
        let collected_fees = weight_hook.collect_fees(&weight_hook_admin_cap, &mut lst_info, &mut system_state, scenario.ctx());
        assert!(collected_fees.value() == MIST_PER_SUI, 0);

        // sharing to make sure shared object deletion actually works lol
        transfer::public_share_object(weight_hook);
        scenario.next_tx(@0x0);

        let weight_hook = scenario.take_shared<WeightHook<TEST>>();
        let admin_cap = weight_hook.eject(weight_hook_admin_cap);

        test_scenario::return_shared(system_state);

        sui::test_utils::destroy(admin_cap);
        sui::test_utils::destroy(lst_info);
        sui::test_utils::destroy(lst);
        sui::test_utils::destroy(lst2);
        sui::test_utils::destroy(collected_fees);

        scenario.end(); 
     }

     #[test]
     fun test_custom_redeem_request() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100, 100]);
        scenario.next_tx(@0x0);

        let (admin_cap, mut lst_info) = create_lst<TEST>(
            fees::new_builder(scenario.ctx()).set_custom_redeem_fee_bps(100).to_fee_config(),
            coin::create_treasury_cap_for_testing(scenario.ctx()),
            scenario.ctx()
        );

        let mut system_state = scenario.take_shared<SuiSystemState>();
        let sui = coin::mint_for_testing(100 * MIST_PER_SUI, scenario.ctx());
        let mut lst = lst_info.mint(&mut system_state, sui, scenario.ctx());

        assert!(lst_info.total_lst_supply() == 100 * MIST_PER_SUI, 0);
        assert!(lst_info.storage().total_sui_supply() == 100 * MIST_PER_SUI, 0);

        let (mut weight_hook, weight_hook_admin_cap) = weight::new(admin_cap, scenario.ctx());

        weight_hook.set_validator_addresses_and_weights(
            &weight_hook_admin_cap, 
            {
                let mut map = vec_map::empty();
                map.insert(address::from_u256(0), 100);
                map.insert(address::from_u256(1), 300);

                map
            }
        );

        weight_hook.rebalance(&mut system_state, &mut lst_info, scenario.ctx());

        assert!(lst_info.storage().validators().borrow(0).total_sui_amount() == 25 * MIST_PER_SUI, 0);
        assert!(lst_info.storage().validators().borrow(1).total_sui_amount() == 75 * MIST_PER_SUI, 0);

        let lst_to_unstake = lst.split(10 * MIST_PER_SUI, scenario.ctx());
        let mut custom_redeem_request = lst_info.custom_redeem_request(lst_to_unstake,&mut system_state, scenario.ctx());
        weight_hook.handle_custom_redeem_request(&mut system_state, &mut lst_info, &mut custom_redeem_request, scenario.ctx());

        assert!(lst_info.storage().validators().borrow(0).total_sui_amount() == 25 * MIST_PER_SUI - 2_500_000_000, 0);
        assert!(lst_info.storage().validators().borrow(1).total_sui_amount() == 75 * MIST_PER_SUI - 7_500_000_000, 0);

        let sui = lst_info.custom_redeem(custom_redeem_request, &mut system_state, scenario.ctx());
        assert!(sui.value() == 10 * MIST_PER_SUI - 100_000_000, 0); // 0.1 sui fee

        test_scenario::return_shared(system_state);

        sui::test_utils::destroy(weight_hook);
        sui::test_utils::destroy(weight_hook_admin_cap);
        sui::test_utils::destroy(lst_info);
        sui::test_utils::destroy(lst);
        sui::test_utils::destroy(sui);

        scenario.end(); 
     }
}