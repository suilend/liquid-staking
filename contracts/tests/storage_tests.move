#[allow(deprecated_usage)]
#[test_only]
module liquid_staking::storage_tests {
    /* Tests */
    use sui::test_scenario::{Self, Scenario};
    use sui_system::governance_test_utils::{
        advance_epoch_with_reward_amounts,
        advance_epoch_with_reward_amounts_return_rebate,
    };
    use sui::address;
    use sui::coin::{Self};
    use sui_system::staking_pool::{StakedSui};
    use sui_system::sui_system::{SuiSystemState};
    use sui::balance::{Self};
    use liquid_staking::storage::{new};
    use sui::sui::SUI;
    use liquid_staking::test_utils::create_validators_with_stakes;
    use sui_system::governance_test_utils::create_sui_system_state_for_testing;


    #[test_only]
    fun setup_sui_system(scenario: &mut Scenario, stakes: vector<u64>) {
        let validators = create_validators_with_stakes(stakes, scenario.ctx());
        create_sui_system_state_for_testing(validators, 0, 0, scenario.ctx());

        advance_epoch_with_reward_amounts(0, 0, scenario);
    }

    const MIST_PER_SUI: u64 = 1_000_000_000;

    fun stake_with(validator_index: u64, amount: u64, scenario: &mut Scenario): StakedSui {
        stake_with_granular(validator_index, amount * MIST_PER_SUI, scenario)
    }

    fun stake_with_granular(validator_index: u64, amount: u64, scenario: &mut Scenario): StakedSui {
        scenario.next_tx(@0x0);

        let mut system_state = scenario.take_shared<SuiSystemState>();

        let ctx = scenario.ctx();

        let staked_sui = system_state.request_add_stake_non_entry(
            coin::mint_for_testing(amount, ctx), 
            address::from_u256(validator_index as u256), 
            ctx
        );

        test_scenario::return_shared(system_state);
        scenario.next_tx(@0x0);

        staked_sui
    }

    #[test]
    public fun test_refresh() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let mut storage = new(scenario.ctx());

        let staked_sui_1 = stake_with(0, 100, &mut scenario);

        let mut system_state = scenario.take_shared<SuiSystemState>();
        storage.join_stake(&mut system_state, staked_sui_1, scenario.ctx());
        storage.refresh(&mut system_state, scenario.ctx());
        test_scenario::return_shared(system_state);

        // check state
        assert!(storage.total_sui_supply() == 100 * MIST_PER_SUI, 0);
        assert!(storage.last_refresh_epoch() == scenario.ctx().epoch(), 0);
        assert!(storage.validators().length() == 1, 0);
        assert!(storage.validators()[0].total_sui_amount() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].active_stake().is_none(), 0);
        assert!(storage.validators()[0].inactive_stake().borrow().staked_sui_amount() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].exchange_rate().sui_amount() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].exchange_rate().pool_token_amount() == 100 * MIST_PER_SUI, 0);

        // stake now looks like [200, 100] => [300, 200]
        advance_epoch_with_reward_amounts(0, 200, &mut scenario);

        let mut system_state = scenario.take_shared<SuiSystemState>();
        assert!(storage.refresh(&mut system_state, scenario.ctx()), 0);
        test_scenario::return_shared(system_state);

        // inactive stake should have been converted to active stake
        assert!(storage.total_sui_supply() == 100 * MIST_PER_SUI, 0);
        assert!(storage.last_refresh_epoch() == scenario.ctx().epoch(), 0);
        assert!(storage.validators().length() == 1, 0);
        assert!(storage.validators()[0].total_sui_amount() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].active_stake().borrow().value() == 50 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].inactive_stake().is_none(), 0);
        assert!(storage.validators()[0].exchange_rate().sui_amount() == 300 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].exchange_rate().pool_token_amount() == 150 * MIST_PER_SUI, 0);

        // stake now looks like [300, 200] => [450, 300]
        advance_epoch_with_reward_amounts(0,300, &mut scenario);

        let mut system_state = scenario.take_shared<SuiSystemState>();
        assert!(storage.refresh(&mut system_state, scenario.ctx()), 0);

        assert!(storage.total_sui_supply() == 150 * MIST_PER_SUI, 0);
        assert!(storage.last_refresh_epoch() == scenario.ctx().epoch(), 0);
        assert!(storage.validators().length() == 1, 0);
        assert!(storage.validators()[0].total_sui_amount() == 150 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].active_stake().borrow().value() == 50 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].inactive_stake().is_none(), 0);
        assert!(storage.validators()[0].exchange_rate().sui_amount() == 450 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].exchange_rate().pool_token_amount() == 150 * MIST_PER_SUI, 0);

        // check idempotency
        assert!(!storage.refresh(&mut system_state, scenario.ctx()), 0);
        test_scenario::return_shared(system_state);

        sui::test_utils::destroy(storage);
        scenario.end();
    }

    #[test]
    fun test_refresh_prune_empty_validator_infos() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let staked_sui = stake_with(0, 50, &mut scenario);

        let mut storage = new(scenario.ctx());
        assert!(storage.total_sui_supply() == 0, 0);

        let mut system_state = scenario.take_shared<SuiSystemState>();

        storage.join_stake(&mut system_state, staked_sui, scenario.ctx());

        assert!(storage.validators().length() == 1, 0);
        assert!(storage.total_sui_supply() == 50 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].total_sui_amount() == 50 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].active_stake().is_none(), 0);
        assert!(storage.validators()[0].inactive_stake().borrow().staked_sui_amount() == 50 * MIST_PER_SUI, 0);

        // Withdraw the stake before refresh
        let unstaked_sui = storage.unstake_approx_n_sui_from_validator(
            &mut system_state,
            0,  
            100 * MIST_PER_SUI,  
            scenario.ctx()
        );

        assert!(unstaked_sui == 50 * MIST_PER_SUI, 0);
        assert!(storage.total_sui_supply() == 50 * MIST_PER_SUI, 0);
        assert!(storage.sui_pool().value() == 50 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].total_sui_amount() == 0, 0);
        assert!(storage.validators()[0].active_stake().is_none(), 0);
        assert!(storage.validators()[0].inactive_stake().is_none(), 0);

        test_scenario::return_shared(system_state);
        advance_epoch_with_reward_amounts(0, 0, &mut scenario);

        let mut system_state = scenario.take_shared<SuiSystemState>();
        assert!(storage.refresh(&mut system_state, scenario.ctx()), 0);

        assert!(storage.total_sui_supply() == 50 * MIST_PER_SUI, 0);
        assert!(storage.sui_pool().value() == 50 * MIST_PER_SUI, 0);
        assert!(storage.validators().length() == 0, 0);  // Validator should be removed as it's empty

        test_scenario::return_shared(system_state);
        sui::test_utils::destroy(storage);
        scenario.end();
    }

    #[test]
    fun test_refresh_skip_epoch() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let staked_sui = stake_with(0, 100, &mut scenario);

        let mut storage = new(scenario.ctx());
        assert!(storage.total_sui_supply() == 0, 0);

        let mut system_state = scenario.take_shared<SuiSystemState>();

        storage.join_stake(&mut system_state, staked_sui, scenario.ctx());
        test_scenario::return_shared(system_state);

        assert!(storage.validators().length() == 1, 0);
        assert!(storage.total_sui_supply() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].total_sui_amount() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].active_stake().is_none(), 0);
        assert!(storage.validators()[0].inactive_stake().borrow().staked_sui_amount() == 100 * MIST_PER_SUI, 0);

        // stake now looks like [200, 100] => [300, 200]
        advance_epoch_with_reward_amounts(0, 200, &mut scenario);
        // stake now looks like [300, 200] => [450, 300]
        advance_epoch_with_reward_amounts(0, 300, &mut scenario);

        let mut system_state = scenario.take_shared<SuiSystemState>();
        storage.refresh(&mut system_state, scenario.ctx());

        assert!(storage.validators().length() == 1, 0);
        assert!(storage.total_sui_supply() == 150 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].total_sui_amount() == 150 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].active_stake().borrow().value() == 50 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].inactive_stake().is_none(), 0);
        assert!(storage.validators()[0].exchange_rate().sui_amount() == 450 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].exchange_rate().pool_token_amount() == 150 * MIST_PER_SUI, 0);

        test_scenario::return_shared(system_state);
        sui::test_utils::destroy(storage);
        scenario.end();
    }

    #[test]
    fun test_refresh_safe_mode() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let staked_sui = stake_with(0, 100, &mut scenario);

        let mut storage = new(scenario.ctx());
        assert!(storage.total_sui_supply() == 0, 0);

        let mut system_state = scenario.take_shared<SuiSystemState>();

        storage.join_stake(&mut system_state, staked_sui, scenario.ctx());
        test_scenario::return_shared(system_state);

        assert!(storage.validators().length() == 1, 0);
        assert!(storage.total_sui_supply() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].total_sui_amount() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].active_stake().is_none(), 0);
        assert!(storage.validators()[0].inactive_stake().borrow().staked_sui_amount() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].exchange_rate().sui_amount() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].exchange_rate().pool_token_amount() == 100 * MIST_PER_SUI, 0);
        assert!(storage.last_refresh_epoch() == 1, 0);

        // safe mode
        test_scenario::next_epoch(&mut scenario, @0x0);

        let mut system_state = scenario.take_shared<SuiSystemState>();
        storage.refresh(&mut system_state, scenario.ctx());

        // storage should use the old exchange rate
        assert!(storage.validators().length() == 1, 0);
        assert!(storage.total_sui_supply() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].total_sui_amount() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].active_stake().borrow().value() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].inactive_stake().is_none(), 0);
        assert!(storage.validators()[0].exchange_rate().sui_amount() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].exchange_rate().pool_token_amount() == 100 * MIST_PER_SUI, 0);
        assert!(storage.last_refresh_epoch() == 2, 0);

        test_scenario::return_shared(system_state);
        sui::test_utils::destroy(storage);
        scenario.end();
    }

    #[test] 
    fun test_join_to_sui_pool() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);
        let mut storage = new(scenario.ctx());

        scenario.next_tx(@0x0);

        assert!(storage.total_sui_supply() == 0, 0);
        assert!(storage.sui_pool().value() == 0, 0);

        let sui = balance::create_for_testing<SUI>(50 * MIST_PER_SUI);
        storage.join_to_sui_pool(sui);

        assert!(storage.total_sui_supply() == 50 * MIST_PER_SUI, 0);
        assert!(storage.sui_pool().value() == 50 * MIST_PER_SUI, 0);

        sui::test_utils::destroy(storage);
        scenario.end();
    }

    /* Join Stake tests */

    #[test]
    fun test_join_stake_active() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let active_staked_sui_1 = stake_with(0, 50, &mut scenario);
        let active_staked_sui_2 = stake_with(0, 50, &mut scenario);

        advance_epoch_with_reward_amounts(0, 0, &mut scenario);
        // stake now looks like [200, 200] => [400, 400]
        advance_epoch_with_reward_amounts(0, 400, &mut scenario);


        let mut storage = new(scenario.ctx());
        assert!(storage.total_sui_supply() == 0, 0);

        let mut system_state = scenario.take_shared<SuiSystemState>();

        storage.join_stake(&mut system_state, active_staked_sui_1, scenario.ctx());

        assert!(storage.validators().length() == 1, 0);
        assert!(storage.total_sui_supply() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].total_sui_amount() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].active_stake().borrow().value() == 50 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].inactive_stake().is_none(), 0);
        assert!(storage.validators()[0].exchange_rate().sui_amount() == 400 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].exchange_rate().pool_token_amount() == 200 * MIST_PER_SUI, 0);

        storage.join_stake(&mut system_state, active_staked_sui_2, scenario.ctx());

        assert!(storage.validators().length() == 1, 0);
        assert!(storage.total_sui_supply() == 200 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].total_sui_amount() == 200 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].active_stake().borrow().value() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].inactive_stake().is_none(), 0);
        assert!(storage.validators()[0].exchange_rate().sui_amount() == 400 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].exchange_rate().pool_token_amount() == 200 * MIST_PER_SUI, 0);

        test_scenario::return_shared(system_state);
        sui::test_utils::destroy(storage);
        
        scenario.end();
    }

    #[test]
    fun test_join_stake_inactive() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let mut staked_sui_1 = stake_with(0, 100, &mut scenario);
        let staked_sui_2 = staked_sui_1.split(50 * MIST_PER_SUI, scenario.ctx());

        scenario.next_tx(@0x0);

        let mut storage = new(scenario.ctx());
        assert!(storage.total_sui_supply() == 0, 0);

        let mut system_state = scenario.take_shared<SuiSystemState>();

        storage.join_stake(&mut system_state, staked_sui_1, scenario.ctx());

        assert!(storage.last_refresh_epoch() == scenario.ctx().epoch(), 0);
        assert!(storage.total_sui_supply() == 50 * MIST_PER_SUI, 0);
        assert!(storage.validators().length() == 1, 0);
        assert!(storage.validators()[0].total_sui_amount() == 50 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].active_stake().is_none(), 0);
        assert!(storage.validators()[0].inactive_stake().borrow().staked_sui_amount() == 50 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].exchange_rate().sui_amount() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].exchange_rate().pool_token_amount() == 100 * MIST_PER_SUI, 0);

        storage.join_stake(&mut system_state, staked_sui_2, scenario.ctx());

        assert!(storage.last_refresh_epoch() == scenario.ctx().epoch(), 0);
        assert!(storage.total_sui_supply() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators().length() == 1, 0);
        assert!(storage.validators()[0].total_sui_amount() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].active_stake().is_none(), 0);
        assert!(storage.validators()[0].inactive_stake().borrow().staked_sui_amount() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].exchange_rate().sui_amount() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].exchange_rate().pool_token_amount() == 100 * MIST_PER_SUI, 0);

        test_scenario::return_shared(system_state);
        sui::test_utils::destroy(storage);
        
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 1, location = liquid_staking::storage)]
    fun test_join_inactive_stake_from_non_active_validator() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let staked_sui_1 = stake_with(1, 100, &mut scenario);

        scenario.next_tx(@0x1);
        let mut system_state = scenario.take_shared<SuiSystemState>();
        system_state.request_remove_validator(scenario.ctx());
        test_scenario::return_shared(system_state);

        advance_epoch_with_reward_amounts(0, 0, &mut scenario);

        let mut system_state = scenario.take_shared<SuiSystemState>();
        assert!(!system_state.active_validator_addresses().contains(&@0x1), 0);


        let mut storage = new(scenario.ctx());
        storage.join_stake(&mut system_state, staked_sui_1, scenario.ctx());

        test_scenario::return_shared(system_state);
        sui::test_utils::destroy(storage);
        
        scenario.end();
    }

    #[test]
    fun test_refresh_with_inactive_stake() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let staked_sui_1 = stake_with(1, 100, &mut scenario);

        let mut system_state = scenario.take_shared<SuiSystemState>();
        let mut storage = new(scenario.ctx());
        storage.join_stake(&mut system_state, staked_sui_1, scenario.ctx());
        test_scenario::return_shared(system_state);

        scenario.next_tx(@0x1);
        let mut system_state = scenario.take_shared<SuiSystemState>();
        system_state.request_remove_validator(scenario.ctx());
        test_scenario::return_shared(system_state);

        advance_epoch_with_reward_amounts(0, 0, &mut scenario);
        advance_epoch_with_reward_amounts(0, 0, &mut scenario);

        let mut system_state = scenario.take_shared<SuiSystemState>();
        assert!(!system_state.active_validator_addresses().contains(&@0x1), 0);

        storage.refresh(&mut system_state, scenario.ctx());
        assert!(storage.validators().length() == 0, 0); // got removed
        assert!(storage.total_sui_supply() == 100 * MIST_PER_SUI, 0);

        test_scenario::return_shared(system_state);
        sui::test_utils::destroy(storage);
        
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 15, location = sui_system::staking_pool)]
    fun test_refresh_inactive_staking_pool_edge_case() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let staked_sui_1 = stake_with(1, 100, &mut scenario);

        let mut system_state = scenario.take_shared<SuiSystemState>();
        let mut storage = new(scenario.ctx());
        storage.join_stake(&mut system_state, staked_sui_1, scenario.ctx());
        test_scenario::return_shared(system_state);

        // remove validator
        scenario.next_tx(@0x1);
        let mut system_state = scenario.take_shared<SuiSystemState>();
        system_state.request_remove_validator(scenario.ctx());
        test_scenario::return_shared(system_state);

        advance_epoch_with_reward_amounts(0, 0, &mut scenario);
        advance_epoch_with_reward_amounts(0, 0, &mut scenario);

        let mut system_state = scenario.take_shared<SuiSystemState>();
        assert!(!system_state.active_validator_addresses().contains(&@0x1), 0);
        test_scenario::return_shared(system_state);

        // readd with same address
        scenario.next_tx(@0x1);
        let mut system_state = scenario.take_shared<SuiSystemState>();
        let pubkey = x"99f25ef61f8032b914636460982c5cc6f134ef1ddae76657f2cbfec1ebfc8d097374080df6fcf0dcb8bc4b0d8e0af5d80ebbff2b4c599f54f42d6312dfc314276078c1cc347ebbbec5198be258513f386b930d02c2749a803e2330955ebd1a10";
        let pop = x"b01cc86f421beca7ab4cfca87c0799c4d038c199dd399fbec1924d4d4367866dba9e84d514710b91feb65316e4ceef43";
        system_state.request_add_validator_candidate_for_testing(
            pubkey,
            vector[215, 64, 85, 185, 231, 116, 69, 151, 97, 79, 4, 183, 20, 70, 84, 51, 211, 162, 115, 221, 73, 241, 240, 171, 192, 25, 232, 106, 175, 162, 176, 43],
            vector[148, 117, 212, 171, 44, 104, 167, 11, 177, 100, 4, 55, 17, 235, 117, 45, 117, 84, 159, 49, 14, 159, 239, 246, 237, 21, 83, 166, 112, 53, 62, 199],
            pop,
            b"ValidatorName2",
            b"description2",
            b"image_url2",
            b"project_url2",
            b"/ip4/127.0.0.2/tcp/80",
            b"/ip4/127.0.0.2/udp/80",
            b"/ip4/168.168.168.168/udp/80",
            b"/ip4/168.168.168.168/udp/80",
            1,
            0,
            scenario.ctx(),
        );
        test_scenario::return_shared(system_state);
        
        let staked_sui_2 = stake_with(1, 100, &mut scenario);

        // 3. mark candidate as pending active validator
        scenario.next_tx(@0x1);
        let mut system_state = scenario.take_shared<SuiSystemState>();
        system_state.request_add_validator(scenario.ctx());
        test_scenario::return_shared(system_state);

        advance_epoch_with_reward_amounts(0, 0, &mut scenario);

        let mut system_state = scenario.take_shared<SuiSystemState>();
        storage.refresh(&mut system_state, scenario.ctx());
        test_scenario::return_shared(system_state);

        sui::test_utils::destroy(storage);
        sui::test_utils::destroy(staked_sui_2);
        
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 1, location = liquid_staking::storage)]
    fun test_join_active_stake_from_non_active_validator() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let active_staked_sui_1 = stake_with(0, 100, &mut scenario);

        advance_epoch_with_reward_amounts(0, 0, &mut scenario);
        advance_epoch_with_reward_amounts(0, 300, &mut scenario);

        // mark validator as inactive
        scenario.next_tx(@0x0);
        let mut system_state = scenario.take_shared<SuiSystemState>();
        system_state.request_remove_validator(scenario.ctx());
        test_scenario::return_shared(system_state);

        advance_epoch_with_reward_amounts(0, 0, &mut scenario);

        let mut system_state = scenario.take_shared<SuiSystemState>();
        let mut storage = new(scenario.ctx());
        assert!(storage.total_sui_supply() == 0, 0);

        storage.join_stake(&mut system_state, active_staked_sui_1, scenario.ctx());

        test_scenario::return_shared(system_state);
        sui::test_utils::destroy(storage);
        
        scenario.end();
    }

    #[test]
    fun test_join_stake_multiple_validators() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let active_staked_sui_1 = stake_with(0, 100, &mut scenario);
        let active_staked_sui_2 = stake_with(1, 100, &mut scenario);

        advance_epoch_with_reward_amounts(0, 0, &mut scenario);
        // stake now looks like [200, 200] => [400, 400]
        advance_epoch_with_reward_amounts(0, 400, &mut scenario);


        let staked_sui = stake_with(0, 100, &mut scenario);
        scenario.next_tx(@0x0);

        let mut storage = new(scenario.ctx());
        assert!(storage.total_sui_supply() == 0, 0);

        let mut system_state = scenario.take_shared<SuiSystemState>();

        storage.join_stake(&mut system_state, staked_sui, scenario.ctx());
        storage.join_stake(&mut system_state, active_staked_sui_1, scenario.ctx());
        storage.join_stake(&mut system_state, active_staked_sui_2, scenario.ctx());

        assert!(storage.validators().length() == 2, 0);
        assert!(storage.total_sui_supply() == 500 * MIST_PER_SUI, 0);

        assert!(storage.validators()[0].total_sui_amount() == 300 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].validator_address() == @0x0, 0);
        assert!(storage.validators()[0].active_stake().borrow().value() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].inactive_stake().borrow().staked_sui_amount() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].exchange_rate().sui_amount() == 400 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].exchange_rate().pool_token_amount() == 200 * MIST_PER_SUI, 0);

        assert!(storage.validators()[1].total_sui_amount() == 200 * MIST_PER_SUI, 0);
        assert!(storage.validators()[1].validator_address() == @0x1, 0);
        assert!(storage.validators()[1].active_stake().borrow().value() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[1].inactive_stake().is_none(), 0);
        assert!(storage.validators()[1].exchange_rate().sui_amount() == 400 * MIST_PER_SUI, 0);
        assert!(storage.validators()[1].exchange_rate().pool_token_amount() == 200 * MIST_PER_SUI, 0);

        test_scenario::return_shared(system_state);
        sui::test_utils::destroy(storage);
        
        scenario.end();
    }

    #[test]
    fun test_split_up_to_n_sui_from_sui_pool() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);
        let mut storage = new(scenario.ctx());

        scenario.next_tx(@0x0);

        assert!(storage.total_sui_supply() == 0, 0);

        let sui = balance::create_for_testing<SUI>(50 * MIST_PER_SUI);
        storage.join_to_sui_pool(sui);

        assert!(storage.total_sui_supply() == 50 * MIST_PER_SUI, 0);

        let sui = storage.split_up_to_n_sui_from_sui_pool(25 * MIST_PER_SUI);
        assert!(storage.total_sui_supply() == 25 * MIST_PER_SUI, 0);
        assert!(sui.value() == 25 * MIST_PER_SUI, 0);
        sui::test_utils::destroy(sui);

        let sui = storage.split_up_to_n_sui_from_sui_pool(50 * MIST_PER_SUI);
        assert!(storage.total_sui_supply() == 0 * MIST_PER_SUI, 0);
        assert!(sui.value() == 25 * MIST_PER_SUI, 0);
        sui::test_utils::destroy(sui);

        sui::test_utils::destroy(storage);

        scenario.end();
    }

    /* Unstake Approx Inactive Stake Tests */

    #[test]
    fun test_unstake_approx_n_sui_from_inactive_stake_take_nothing() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let staked_sui_1 = stake_with(0, 100, &mut scenario);

        let mut system_state = scenario.take_shared<SuiSystemState>();

        let mut storage = new(scenario.ctx());
        storage.join_stake(&mut system_state, staked_sui_1, scenario.ctx());
        assert!(storage.total_sui_supply() == 100 * MIST_PER_SUI, 0);

        let amount = storage.unstake_approx_n_sui_from_inactive_stake(
            &mut system_state, 
            0, 
            0, 
            scenario.ctx()
        );

        assert!(amount == 0, 0);
        assert!(storage.validators().length() == 1, 0);
        assert!(storage.total_sui_supply() == 100 * MIST_PER_SUI, 0);
        assert!(storage.sui_pool().value() == 0, 0);
        assert!(storage.validators()[0].total_sui_amount() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].active_stake().is_none(), 0);
        assert!(
            storage.validators()[0].inactive_stake().borrow().staked_sui_amount() == 100 * MIST_PER_SUI, 
            0
        );

        sui::test_utils::destroy(storage);
        test_scenario::return_shared(system_state);
        scenario.end();
    }

    #[test]
    fun test_unstake_approx_n_sui_from_inactive_stake_take_all() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let staked_sui_1 = stake_with(0, 100, &mut scenario);

        let mut system_state = scenario.take_shared<SuiSystemState>();

        let mut storage = new(scenario.ctx());
        storage.join_stake(&mut system_state, staked_sui_1, scenario.ctx());
        assert!(storage.total_sui_supply() == 100 * MIST_PER_SUI, 0);

        let amount = storage.unstake_approx_n_sui_from_inactive_stake(
            &mut system_state, 
            0, 
            101 * MIST_PER_SUI, 
            scenario.ctx()
        );

        assert!(amount  == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators().length() == 1, 0);
        assert!(storage.total_sui_supply() == 100 * MIST_PER_SUI, 0);
        assert!(storage.sui_pool().value() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].total_sui_amount() == 0, 0);
        assert!(storage.validators()[0].active_stake().is_none(), 0);
        assert!(storage.validators()[0].inactive_stake().is_none(), 0);

        sui::test_utils::destroy(storage);
        test_scenario::return_shared(system_state);
        scenario.end();
    }

    #[test]
    fun test_unstake_approx_n_sui_from_inactive_stake_take_partial() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let staked_sui_1 = stake_with(0, 100, &mut scenario);

        let mut system_state = scenario.take_shared<SuiSystemState>();

        let mut storage = new(scenario.ctx());
        storage.join_stake(&mut system_state, staked_sui_1, scenario.ctx());
        assert!(storage.total_sui_supply() == 100 * MIST_PER_SUI, 0);

        let amount = storage.unstake_approx_n_sui_from_inactive_stake(
            &mut system_state, 
            0, 
            50 * MIST_PER_SUI, 
            scenario.ctx()
        );

        assert!(amount  == 50 * MIST_PER_SUI, 0);
        assert!(storage.validators().length() == 1, 0);
        assert!(storage.total_sui_supply() == 100 * MIST_PER_SUI, 0);
        assert!(storage.sui_pool().value() == 50 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].total_sui_amount() == 50 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].active_stake().is_none(), 0);
        assert!(
            storage.validators()[0].inactive_stake().borrow().staked_sui_amount() == 50 * MIST_PER_SUI, 
            0
        );

        sui::test_utils::destroy(storage);
        test_scenario::return_shared(system_state);
        scenario.end();
    }

    #[test]
    fun test_unstake_approx_n_sui_from_inactive_stake_take_dust() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let staked_sui_1 = stake_with(0, 100, &mut scenario);

        let mut system_state = scenario.take_shared<SuiSystemState>();

        let mut storage = new(scenario.ctx());
        storage.join_stake(&mut system_state, staked_sui_1, scenario.ctx());
        assert!(storage.total_sui_supply() == 100 * MIST_PER_SUI, 0);

        let amount = storage.unstake_approx_n_sui_from_inactive_stake(
            &mut system_state, 
            0, 
            1, 
            scenario.ctx()
        );

        assert!(amount  == MIST_PER_SUI, 0);
        assert!(storage.validators().length() == 1, 0);
        assert!(storage.total_sui_supply() == 100 * MIST_PER_SUI, 0);
        assert!(storage.sui_pool().value() == MIST_PER_SUI, 0);
        assert!(storage.validators()[0].total_sui_amount() == 99 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].active_stake().is_none(), 0);
        assert!(
            storage.validators()[0].inactive_stake().borrow().staked_sui_amount() == 99 * MIST_PER_SUI, 
            0
        );

        sui::test_utils::destroy(storage);
        test_scenario::return_shared(system_state);
        scenario.end();
    }

    #[test]
    fun test_unstake_approx_n_sui_from_inactive_stake_leave_dust() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let staked_sui_1 = stake_with(0, 100, &mut scenario);

        let mut system_state = scenario.take_shared<SuiSystemState>();

        let mut storage = new(scenario.ctx());
        storage.join_stake(&mut system_state, staked_sui_1, scenario.ctx());
        assert!(storage.total_sui_supply() == 100 * MIST_PER_SUI, 0);

        let amount = storage.unstake_approx_n_sui_from_inactive_stake(
            &mut system_state, 
            0, 
            99 * MIST_PER_SUI + 1,
            scenario.ctx()
        );

        assert!(amount == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators().length() == 1, 0);
        assert!(storage.total_sui_supply() == 100 * MIST_PER_SUI, 0);
        assert!(storage.sui_pool().value() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].total_sui_amount() == 0, 0);
        assert!(storage.validators()[0].active_stake().is_none(), 0);
        assert!(storage.validators()[0].inactive_stake().is_none(), 0);

        sui::test_utils::destroy(storage);
        test_scenario::return_shared(system_state);
        scenario.end();
    }

    /* Unstake Approx Active Stake Tests */

    #[test]
    fun test_unstake_approx_n_sui_from_active_stake_take_nothing() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let staked_sui_1 = stake_with(0, 100, &mut scenario);
        advance_epoch_with_reward_amounts(0, 0, &mut scenario);
        advance_epoch_with_reward_amounts(0, 400, &mut scenario);

        scenario.next_tx(@0x0);

        let mut system_state = scenario.take_shared<SuiSystemState>();
        let mut storage = new(scenario.ctx());

        storage.join_stake(&mut system_state, staked_sui_1, scenario.ctx());
        assert!(storage.total_sui_supply() == 200 * MIST_PER_SUI, 0);

        let amount = storage.unstake_approx_n_sui_from_active_stake(
            &mut system_state, 
            0, 
            0, 
            scenario.ctx()
        );

        assert!(amount == 0, 0);
        assert!(storage.validators().length() == 1, 0);
        assert!(storage.total_sui_supply() == 200 * MIST_PER_SUI, 0);
        assert!(storage.sui_pool().value() == 0, 0);
        assert!(storage.validators()[0].total_sui_amount() == 200 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].active_stake().borrow().value() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].inactive_stake().is_none(), 0);

        sui::test_utils::destroy(storage);
        test_scenario::return_shared(system_state);
        scenario.end();
    }

    #[test]
    fun test_unstake_approx_n_sui_from_active_stake_take_all() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let staked_sui_1 = stake_with(0, 100, &mut scenario);
        advance_epoch_with_reward_amounts(0, 0, &mut scenario);
        advance_epoch_with_reward_amounts(0, 400, &mut scenario);

        scenario.next_tx(@0x0);

        let mut system_state = scenario.take_shared<SuiSystemState>();
        let mut storage = new(scenario.ctx());

        storage.refresh(&mut system_state, scenario.ctx());

        storage.join_stake(&mut system_state, staked_sui_1, scenario.ctx());
        assert!(storage.total_sui_supply() == 200 * MIST_PER_SUI, 0);

        let amount = storage.unstake_approx_n_sui_from_active_stake(
            &mut system_state, 
            0, 
            200 * MIST_PER_SUI, 
            scenario.ctx()
        );

        assert!(amount == 200 * MIST_PER_SUI, 0);
        assert!(storage.validators().length() == 1, 0);
        assert!(storage.total_sui_supply() == 200 * MIST_PER_SUI, 0);
        assert!(storage.sui_pool().value() == 200 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].total_sui_amount() == 0, 0);
        assert!(storage.validators()[0].active_stake().is_none(), 0);
        assert!(storage.validators()[0].inactive_stake().is_none(), 0);

        sui::test_utils::destroy(storage);
        test_scenario::return_shared(system_state);
        scenario.end();
    }

    #[test]
    fun test_unstake_approx_n_sui_from_active_stake_take_partial() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let staked_sui_1 = stake_with(0, 100, &mut scenario);
        advance_epoch_with_reward_amounts(0, 0, &mut scenario);
        advance_epoch_with_reward_amounts(0, 400, &mut scenario);

        scenario.next_tx(@0x0);

        let mut system_state = scenario.take_shared<SuiSystemState>();
        let mut storage = new(scenario.ctx());

        storage.refresh(&mut system_state, scenario.ctx());

        storage.join_stake(&mut system_state, staked_sui_1, scenario.ctx());
        assert!(storage.total_sui_supply() == 200 * MIST_PER_SUI, 0);

        let amount = storage.unstake_approx_n_sui_from_active_stake(
            &mut system_state, 
            0, 
            100 * MIST_PER_SUI, 
            scenario.ctx()
        );

        assert!(amount == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators().length() == 1, 0);
        assert!(storage.total_sui_supply() == 200 * MIST_PER_SUI, 0);
        assert!(storage.sui_pool().value() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].total_sui_amount() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].active_stake().borrow().value() == 50 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].inactive_stake().is_none(), 0);

        sui::test_utils::destroy(storage);
        test_scenario::return_shared(system_state);
        scenario.end();
    }

    #[test]
    fun test_unstake_approx_n_sui_from_active_stake_take_dust() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let staked_sui_1 = stake_with(0, 100, &mut scenario);
        advance_epoch_with_reward_amounts(0, 0, &mut scenario);
        advance_epoch_with_reward_amounts(0, 400, &mut scenario);

        scenario.next_tx(@0x0);

        let mut system_state = scenario.take_shared<SuiSystemState>();
        let mut storage = new(scenario.ctx());

        storage.refresh(&mut system_state, scenario.ctx());

        storage.join_stake(&mut system_state, staked_sui_1, scenario.ctx());
        assert!(storage.total_sui_supply() == 200 * MIST_PER_SUI, 0);

        let amount = storage.unstake_approx_n_sui_from_active_stake(
            &mut system_state, 
            0, 
            1, 
            scenario.ctx()
        );

        assert!(amount == MIST_PER_SUI, 0);
        assert!(storage.validators().length() == 1, 0);
        assert!(storage.total_sui_supply() == 200 * MIST_PER_SUI, 0);
        assert!(storage.sui_pool().value() == MIST_PER_SUI, 0);
        assert!(storage.validators()[0].total_sui_amount() == 199 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].active_stake().borrow().value() == 99_500_000_000, 0);
        assert!(storage.validators()[0].inactive_stake().is_none(), 0);

        sui::test_utils::destroy(storage);
        test_scenario::return_shared(system_state);
        scenario.end();
    }

    #[test]
    fun test_unstake_approx_n_sui_from_active_stake_leave_dust() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let staked_sui_1 = stake_with(0, 100, &mut scenario);
        advance_epoch_with_reward_amounts(0, 0, &mut scenario);
        advance_epoch_with_reward_amounts(0, 400, &mut scenario);

        scenario.next_tx(@0x0);

        let mut system_state = scenario.take_shared<SuiSystemState>();
        let mut storage = new(scenario.ctx());

        storage.refresh(&mut system_state, scenario.ctx());

        storage.join_stake(&mut system_state, staked_sui_1, scenario.ctx());
        assert!(storage.total_sui_supply() == 200 * MIST_PER_SUI, 0);

        let amount = storage.unstake_approx_n_sui_from_active_stake(
            &mut system_state, 
            0, 
            199 * MIST_PER_SUI + 1, 
            scenario.ctx()
        );

        assert!(amount == 199 * MIST_PER_SUI + 2, 0);
        assert!(storage.validators().length() == 1, 0);
        assert!(storage.total_sui_supply() == 200 * MIST_PER_SUI, 0);
        assert!(storage.sui_pool().value() == 199 * MIST_PER_SUI + 2, 0);
        assert!(storage.validators()[0].total_sui_amount() == MIST_PER_SUI - 2, 0);
        assert!(storage.validators()[0].active_stake().borrow().value() == MIST_PER_SUI / 2 - 1, 0);
        assert!(storage.validators()[0].inactive_stake().is_none(), 0);

        sui::test_utils::destroy(storage);
        test_scenario::return_shared(system_state);
        scenario.end();
    }

    #[test]
    fun test_unstake_approx_n_sui_from_active_stake_ceil() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let staked_sui_1 = stake_with(0, 100, &mut scenario);
        advance_epoch_with_reward_amounts(0, 0, &mut scenario);
        advance_epoch_with_reward_amounts(0, 400, &mut scenario);

        scenario.next_tx(@0x0);

        let mut system_state = scenario.take_shared<SuiSystemState>();
        let mut storage = new(scenario.ctx());

        storage.refresh(&mut system_state, scenario.ctx());

        storage.join_stake(&mut system_state, staked_sui_1, scenario.ctx());
        assert!(storage.total_sui_supply() == 200 * MIST_PER_SUI, 0);

        let amount = storage.unstake_approx_n_sui_from_active_stake(
            &mut system_state, 
            0, 
            2 * MIST_PER_SUI + 1, 
            scenario.ctx()
        );

        assert!(amount == 2 * MIST_PER_SUI + 2, 0);
        assert!(storage.validators().length() == 1, 0);
        assert!(storage.total_sui_supply() == 200 * MIST_PER_SUI, 0);
        assert!(storage.sui_pool().value() == 2 * MIST_PER_SUI + 2, 0);
        assert!(storage.validators()[0].total_sui_amount() == 198 * MIST_PER_SUI - 2, 0);
        assert!(storage.validators()[0].active_stake().borrow().value() == 99_000_000_000 - 1, 0);
        assert!(storage.validators()[0].inactive_stake().is_none(), 0);

        sui::test_utils::destroy(storage);
        test_scenario::return_shared(system_state);
        scenario.end();
    }

    /* split up to n sui tests */

    #[test]
    fun test_split_up_to_n_sui_only_from_sui_pool() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let active_staked_sui_1 = stake_with(0, 100, &mut scenario);
        let active_staked_sui_2 = stake_with(1, 100, &mut scenario);

        advance_epoch_with_reward_amounts(0, 0, &mut scenario);
        // stake now looks like [200, 200] => [400, 400]
        advance_epoch_with_reward_amounts(0, 400, &mut scenario);


        let staked_sui = stake_with(0, 100, &mut scenario);
        scenario.next_tx(@0x0);

        let mut storage = new(scenario.ctx());
        assert!(storage.total_sui_supply() == 0, 0);

        let mut system_state = scenario.take_shared<SuiSystemState>();

        storage.join_to_sui_pool(balance::create_for_testing(100 * MIST_PER_SUI));
        storage.join_stake(&mut system_state, staked_sui, scenario.ctx());
        storage.join_stake(&mut system_state, active_staked_sui_1, scenario.ctx());
        storage.join_stake(&mut system_state, active_staked_sui_2, scenario.ctx());

        assert!(storage.total_sui_supply() == 600 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].total_sui_amount() == 300 * MIST_PER_SUI, 0);
        assert!(storage.validators()[1].total_sui_amount() == 200 * MIST_PER_SUI, 0);

        // start of test
        let sui = storage.split_n_sui(
            &mut system_state,
            100 * MIST_PER_SUI,
            scenario.ctx()
        );

        assert!(sui.value() == 100 * MIST_PER_SUI, 0);
        assert!(storage.total_sui_supply() == 500 * MIST_PER_SUI, 0);
        assert!(storage.sui_pool().value() == 0, 0);
        assert!(storage.validators()[0].total_sui_amount() == 300 * MIST_PER_SUI, 0);
        assert!(storage.validators()[1].total_sui_amount() == 200 * MIST_PER_SUI, 0);

        test_scenario::return_shared(system_state);
        sui::test_utils::destroy(storage);
        sui::test_utils::destroy(sui);
        
        scenario.end();
    }

    #[test]
    fun test_split_up_to_n_sui_take_from_inactive_stake() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let active_staked_sui_1 = stake_with(0, 100, &mut scenario);
        let active_staked_sui_2 = stake_with(1, 100, &mut scenario);

        advance_epoch_with_reward_amounts(0, 0, &mut scenario);
        // stake now looks like [200, 200] => [400, 400]
        advance_epoch_with_reward_amounts(0, 400, &mut scenario);


        let staked_sui = stake_with(0, 100, &mut scenario);
        scenario.next_tx(@0x0);

        let mut storage = new(scenario.ctx());
        assert!(storage.total_sui_supply() == 0, 0);

        let mut system_state = scenario.take_shared<SuiSystemState>();

        storage.join_to_sui_pool(balance::create_for_testing(100 * MIST_PER_SUI));
        storage.join_stake(&mut system_state, staked_sui, scenario.ctx());
        storage.join_stake(&mut system_state, active_staked_sui_1, scenario.ctx());
        storage.join_stake(&mut system_state, active_staked_sui_2, scenario.ctx());

        assert!(storage.total_sui_supply() == 600 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].total_sui_amount() == 300 * MIST_PER_SUI, 0);
        assert!(storage.validators()[1].total_sui_amount() == 200 * MIST_PER_SUI, 0);

        // start of test
        let sui = storage.split_n_sui(
            &mut system_state,
            200 * MIST_PER_SUI,
            scenario.ctx()
        );

        assert!(sui.value() == 200 * MIST_PER_SUI, 0);
        assert!(storage.total_sui_supply() == 400 * MIST_PER_SUI, 0);
        assert!(storage.sui_pool().value() == 0, 0);
        assert!(storage.validators()[0].total_sui_amount() == 200 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].inactive_stake().is_none(), 0);
        assert!(storage.validators()[1].total_sui_amount() == 200 * MIST_PER_SUI, 0);

        test_scenario::return_shared(system_state);
        sui::test_utils::destroy(storage);
        sui::test_utils::destroy(sui);
        
        scenario.end();
    }

    #[test]
    fun test_split_up_to_n_sui_take_all() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let active_staked_sui_1 = stake_with(0, 100, &mut scenario);
        let active_staked_sui_2 = stake_with(1, 100, &mut scenario);

        advance_epoch_with_reward_amounts(0, 0, &mut scenario);
        // stake now looks like [200, 200] => [400, 400]
        advance_epoch_with_reward_amounts(0, 400, &mut scenario);

        let staked_sui = stake_with(0, 100, &mut scenario);
        scenario.next_tx(@0x0);

        let mut storage = new(scenario.ctx());
        assert!(storage.total_sui_supply() == 0, 0);

        let mut system_state = scenario.take_shared<SuiSystemState>();

        storage.join_to_sui_pool(balance::create_for_testing(100 * MIST_PER_SUI));
        storage.join_stake(&mut system_state, staked_sui, scenario.ctx());
        storage.join_stake(&mut system_state, active_staked_sui_1, scenario.ctx());
        storage.join_stake(&mut system_state, active_staked_sui_2, scenario.ctx());

        assert!(storage.total_sui_supply() == 600 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].total_sui_amount() == 300 * MIST_PER_SUI, 0);
        assert!(storage.validators()[1].total_sui_amount() == 200 * MIST_PER_SUI, 0);

        // start of test
        let sui = storage.split_n_sui(
            &mut system_state,
            600 * MIST_PER_SUI,
            scenario.ctx()
        );

        assert!(sui.value() == 600 * MIST_PER_SUI, 0);
        assert!(storage.total_sui_supply() == 0, 0);
        assert!(storage.sui_pool().value() == 0, 0);
        assert!(storage.validators()[0].total_sui_amount() == 0, 0);
        assert!(storage.validators()[0].inactive_stake().is_none(), 0);
        assert!(storage.validators()[0].active_stake().is_none(), 0);
        assert!(storage.validators()[1].inactive_stake().is_none(), 0);
        assert!(storage.validators()[1].active_stake().is_none(), 0);

        test_scenario::return_shared(system_state);
        sui::test_utils::destroy(storage);
        sui::test_utils::destroy(sui);
        
        scenario.end();
    }

    #[test]
    fun test_split_up_to_n_sui_take_nothing() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let active_staked_sui_1 = stake_with(0, 100, &mut scenario);
        let active_staked_sui_2 = stake_with(1, 100, &mut scenario);

        advance_epoch_with_reward_amounts(0, 0, &mut scenario);
        // stake now looks like [200, 200] => [400, 400]
        advance_epoch_with_reward_amounts(0, 400, &mut scenario);

        let staked_sui = stake_with(0, 100, &mut scenario);
        scenario.next_tx(@0x0);

        let mut storage = new(scenario.ctx());
        assert!(storage.total_sui_supply() == 0, 0);

        let mut system_state = scenario.take_shared<SuiSystemState>();

        storage.join_to_sui_pool(balance::create_for_testing(100 * MIST_PER_SUI));
        storage.join_stake(&mut system_state, staked_sui, scenario.ctx());
        storage.join_stake(&mut system_state, active_staked_sui_1, scenario.ctx());
        storage.join_stake(&mut system_state, active_staked_sui_2, scenario.ctx());

        assert!(storage.total_sui_supply() == 600 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].total_sui_amount() == 300 * MIST_PER_SUI, 0);
        assert!(storage.validators()[1].total_sui_amount() == 200 * MIST_PER_SUI, 0);

        // start of test
        let sui = storage.split_n_sui(
            &mut system_state,
            0,
            scenario.ctx()
        );

        assert!(sui.value() == 0, 0);
        assert!(storage.total_sui_supply() == 600 * MIST_PER_SUI, 0);

        test_scenario::return_shared(system_state);
        sui::test_utils::destroy(storage);
        sui::test_utils::destroy(sui);
        
        scenario.end();
    }

    #[random_test]
    fun test_random_split_n_sui_from_active_stake(
        initial_validator_stake_amount: u64,
        initial_stake_amount: u64,
        reward_amount: u64,
        split_amount: u64
    ) {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[initial_validator_stake_amount % 10_000_000]);

        let active_staked_sui = stake_with_granular(
            0,
            initial_stake_amount % (1_000_000 * MIST_PER_SUI) + MIST_PER_SUI,
            &mut scenario
        );

        advance_epoch_with_reward_amounts(0, 1, &mut scenario);
        advance_epoch_with_reward_amounts(0, 1, &mut scenario);
        advance_epoch_with_reward_amounts(0, 1, &mut scenario);

        let storage_rebate = advance_epoch_with_reward_amounts_return_rebate(
            0,
            reward_amount % (100_000 * MIST_PER_SUI), 
            0,
            0,
            &mut scenario
        );
        sui::test_utils::destroy(storage_rebate);

        let mut system_state = scenario.take_shared<SuiSystemState>();
        let mut storage = new(scenario.ctx());
        storage.join_stake(&mut system_state, active_staked_sui, scenario.ctx());

        let total_sui_supply = storage.total_sui_supply();
        let sui = storage.split_n_sui(
            &mut system_state,
            (split_amount % total_sui_supply) % 4001,
            scenario.ctx()
        );

        test_scenario::return_shared(system_state);
        sui::test_utils::destroy(storage);
        sui::test_utils::destroy(sui);
        scenario.end();
    }

    /* unstake approx n sui from validator tests */

    #[test]
    fun test_unstake_approx_n_sui_from_validator_take_from_inactive_stake() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let active_staked_sui = stake_with(0, 100, &mut scenario);

        advance_epoch_with_reward_amounts(0, 0, &mut scenario);
        // stake now looks like [200, 200] => [400, 400]
        advance_epoch_with_reward_amounts(0, 400, &mut scenario);

        let staked_sui = stake_with(0, 100, &mut scenario);
        scenario.next_tx(@0x0);

        let mut storage = new(scenario.ctx());
        assert!(storage.total_sui_supply() == 0, 0);

        let mut system_state = scenario.take_shared<SuiSystemState>();

        storage.join_stake(&mut system_state, staked_sui, scenario.ctx());
        storage.join_stake(&mut system_state, active_staked_sui, scenario.ctx());

        assert!(storage.total_sui_supply() == 300 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].total_sui_amount() == 300 * MIST_PER_SUI, 0);

        let amount = storage.unstake_approx_n_sui_from_validator(
            &mut system_state,
            0,
            100 * MIST_PER_SUI,
            scenario.ctx()
        );

        assert!(amount == 100 * MIST_PER_SUI, 0);
        assert!(storage.total_sui_supply() == 300 * MIST_PER_SUI, 0);
        assert!(storage.sui_pool().value() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].total_sui_amount() == 200 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].inactive_stake().is_none(), 0);
        assert!(storage.validators()[0].active_stake().borrow().value() == 100 * MIST_PER_SUI, 0);

        test_scenario::return_shared(system_state);
        sui::test_utils::destroy(storage);
        
        scenario.end();
    }

    #[test]
    fun test_unstake_approx_n_sui_from_validator_take_all() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let active_staked_sui = stake_with(0, 100, &mut scenario);

        advance_epoch_with_reward_amounts(0, 0, &mut scenario);
        // stake now looks like [200, 200] => [400, 400]
        advance_epoch_with_reward_amounts(0, 400, &mut scenario);

        let staked_sui = stake_with(0, 100, &mut scenario);
        scenario.next_tx(@0x0);

        let mut storage = new(scenario.ctx());
        assert!(storage.total_sui_supply() == 0, 0);

        let mut system_state = scenario.take_shared<SuiSystemState>();

        storage.join_stake(&mut system_state, staked_sui, scenario.ctx());
        storage.join_stake(&mut system_state, active_staked_sui, scenario.ctx());

        assert!(storage.total_sui_supply() == 300 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].total_sui_amount() == 300 * MIST_PER_SUI, 0);

        let amount = storage.unstake_approx_n_sui_from_validator(
            &mut system_state,
            0,
            300 * MIST_PER_SUI,
            scenario.ctx()
        );

        assert!(amount == 300 * MIST_PER_SUI, 0);
        assert!(storage.total_sui_supply() == 300 * MIST_PER_SUI, 0);
        assert!(storage.sui_pool().value() == 300 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].total_sui_amount() == 0, 0);
        assert!(storage.validators()[0].inactive_stake().is_none(), 0);
        assert!(storage.validators()[0].active_stake().is_none(), 0);

        test_scenario::return_shared(system_state);
        sui::test_utils::destroy(storage);
        
        scenario.end();
    }

    #[test]
    fun test_unstake_approx_n_sui_from_validator_take_nothing() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let active_staked_sui = stake_with(0, 100, &mut scenario);

        advance_epoch_with_reward_amounts(0, 0, &mut scenario);
        // stake now looks like [200, 200] => [400, 400]
        advance_epoch_with_reward_amounts(0, 400, &mut scenario);

        let staked_sui = stake_with(0, 100, &mut scenario);
        scenario.next_tx(@0x0);

        let mut storage = new(scenario.ctx());
        assert!(storage.total_sui_supply() == 0, 0);

        let mut system_state = scenario.take_shared<SuiSystemState>();

        storage.join_stake(&mut system_state, staked_sui, scenario.ctx());
        storage.join_stake(&mut system_state, active_staked_sui, scenario.ctx());

        assert!(storage.total_sui_supply() == 300 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].total_sui_amount() == 300 * MIST_PER_SUI, 0);

        let amount = storage.unstake_approx_n_sui_from_validator(
            &mut system_state,
            0,
            0,
            scenario.ctx()
        );

        assert!(amount == 0, 0);
        assert!(storage.total_sui_supply() == 300 * MIST_PER_SUI, 0);
        assert!(storage.sui_pool().value() == 0, 0);
        assert!(storage.validators()[0].total_sui_amount() == 300 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].inactive_stake().borrow().staked_sui_amount() == 100 * MIST_PER_SUI, 0);
        assert!(storage.validators()[0].active_stake().borrow().value() == 100 * MIST_PER_SUI, 0);

        test_scenario::return_shared(system_state);
        sui::test_utils::destroy(storage);
        
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 2, location = liquid_staking::storage)]
    fun test_too_many_validators() {
        let mut scenario = test_scenario::begin(@0x0);

        let mut storage = new(scenario.ctx());

        let mut validator_initial_stakes = vector::empty();
        51u64.do!(|_| {
            validator_initial_stakes.push_back(100);
        });

        setup_sui_system(&mut scenario, validator_initial_stakes);
        scenario.next_tx(@0x0);

        51u64.do!(|i| {
            let stake = stake_with(i, 100, &mut scenario);

            let mut system_state = scenario.take_shared<SuiSystemState>();
            storage.join_stake(&mut system_state, stake, scenario.ctx());
            test_scenario::return_shared(system_state);

            scenario.next_tx(@0x0);
        });

        sui::test_utils::destroy(storage);
        scenario.end();
    }
}   
