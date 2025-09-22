#[allow(deprecated_usage)]
#[test_only]
module liquid_staking::liquid_staking_tests {
    // uncomment this line to import the module
    use sui::address;
    use sui_system::staking_pool::StakedSui;
    use sui::test_scenario::{Self, Scenario};
    use sui_system::sui_system::SuiSystemState;
    use sui::coin::{Self};
    use sui::sui::SUI;
    use liquid_staking::liquid_staking::{create_lst, create_lst_with_stake};
    use liquid_staking::fees::{Self};
    use sui_system::governance_test_utils::{
        advance_epoch_with_reward_amounts,
        create_sui_system_state_for_testing,
    };
    use liquid_staking::test_utils::create_validators_with_stakes;

    /* Constants */
    const MIST_PER_SUI: u64 = 1_000_000_000;

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

    fun setup_sui_system(scenario: &mut Scenario, stakes: vector<u64>) {
        let validators = create_validators_with_stakes(stakes, scenario.ctx());
        create_sui_system_state_for_testing(validators, 0, 0, scenario.ctx());

        advance_epoch_with_reward_amounts(0, 0, scenario);
    }

     public struct TEST has drop {}

     #[test]
     fun test_create_lst() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        scenario.next_tx(@0x0);

        let system_state = scenario.take_shared<SuiSystemState>();

        let (admin_cap, lst_info) = create_lst<TEST>(
            fees::new_builder(scenario.ctx())
                .set_sui_mint_fee_bps(100)
                .set_redeem_fee_bps(100)
                .to_fee_config(),
            coin::create_treasury_cap_for_testing(scenario.ctx()),
            scenario.ctx()
        );

        assert!(lst_info.total_lst_supply() == 0, 0);
        assert!(lst_info.storage().total_sui_supply() == 0, 0);

        test_scenario::return_shared(system_state);

        sui::test_utils::destroy(admin_cap);
        sui::test_utils::destroy(lst_info);

        scenario.end();
     }

    #[test]
    fun test_create_lst_with_stake_happy() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let staked_sui = stake_with(0, 100, &mut scenario);

        advance_epoch_with_reward_amounts(0, 0, &mut scenario);

        let mut system_state = scenario.take_shared<SuiSystemState>();
        let fungible_staked_sui = system_state.convert_to_fungible_staked_sui(staked_sui, scenario.ctx());

        // Create a treasury cap with non-zero coins
        let mut treasury_cap = coin::create_treasury_cap_for_testing<TEST>(scenario.ctx());
        let coins = treasury_cap.mint(200 * MIST_PER_SUI, scenario.ctx());

        let (admin_cap, lst_info) = create_lst_with_stake<TEST>(
            &mut system_state,
            fees::new_builder(scenario.ctx())
                .set_sui_mint_fee_bps(100)
                .set_redeem_fee_bps(100)
                .to_fee_config(),
            treasury_cap,
            vector[fungible_staked_sui],
            coin::mint_for_testing(100 * MIST_PER_SUI, scenario.ctx()),
            scenario.ctx()
        );

        assert!(lst_info.total_lst_supply() == 200 * MIST_PER_SUI, 0);
        assert!(lst_info.storage().total_sui_supply() == 200 * MIST_PER_SUI, 0);

        test_scenario::return_shared(system_state);

        sui::test_utils::destroy(admin_cap);
        sui::test_utils::destroy(lst_info);
        sui::test_utils::destroy( coins);

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 0, location = liquid_staking::liquid_staking)]
    fun test_create_lst_fail() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let system_state = scenario.take_shared<SuiSystemState>();

        let mut treasury_cap = coin::create_treasury_cap_for_testing(scenario.ctx());
        let coins = treasury_cap.mint(1000 * MIST_PER_SUI, scenario.ctx());

        let (admin_cap, lst_info) = create_lst<TEST>(
            fees::new_builder(scenario.ctx())
                .set_sui_mint_fee_bps(100)
                .set_redeem_fee_bps(100)
                .to_fee_config(),
            treasury_cap,
            scenario.ctx()
        );

        test_scenario::return_shared(system_state);

        sui::test_utils::destroy(coins);
        sui::test_utils::destroy(admin_cap);
        sui::test_utils::destroy(lst_info);

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 0, location = liquid_staking::liquid_staking)]
    fun test_create_lst_with_stake_fail_1() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);
        let staked_sui = stake_with(0, 100, &mut scenario);

        advance_epoch_with_reward_amounts(0, 0, &mut scenario);

        let mut system_state = scenario.take_shared<SuiSystemState>();
        let fungible_staked_sui = system_state.convert_to_fungible_staked_sui(staked_sui, scenario.ctx());

        // Create an empty treasury cap
        let treasury_cap = coin::create_treasury_cap_for_testing(scenario.ctx());

        let (admin_cap, lst_info) = create_lst_with_stake<TEST>(
            &mut system_state,
            fees::new_builder(scenario.ctx())
                .set_sui_mint_fee_bps(100)
                .set_redeem_fee_bps(100)
                .to_fee_config(),
            treasury_cap,
            vector[fungible_staked_sui],
            coin::zero<SUI>(scenario.ctx()),
            scenario.ctx()
        );

        test_scenario::return_shared(system_state);

        sui::test_utils::destroy(admin_cap);
        sui::test_utils::destroy(lst_info);

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 0, location = liquid_staking::liquid_staking)]
    fun test_create_lst_with_stake_fail_2() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let mut system_state = scenario.take_shared<SuiSystemState>();

        let mut treasury_cap = coin::create_treasury_cap_for_testing(scenario.ctx());
        let coins = treasury_cap.mint(1000 * MIST_PER_SUI, scenario.ctx());

        let (admin_cap, lst_info) = create_lst_with_stake<TEST>(
            &mut system_state,
            fees::new_builder(scenario.ctx())
                .set_sui_mint_fee_bps(100)
                .set_redeem_fee_bps(100)
                .to_fee_config(),
            treasury_cap,
            vector::empty(),
            coin::zero<SUI>(scenario.ctx()),
            scenario.ctx()
        );

        test_scenario::return_shared(system_state);

        sui::test_utils::destroy(admin_cap);
        sui::test_utils::destroy(lst_info);
        sui::test_utils::destroy(coins);

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 0, location = liquid_staking::liquid_staking)]
    fun test_create_lst_with_stake_fail_3() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let mut system_state = scenario.take_shared<SuiSystemState>();

        let mut treasury_cap = coin::create_treasury_cap_for_testing(scenario.ctx());
        let coins = treasury_cap.mint(1000 * MIST_PER_SUI, scenario.ctx());

        let (admin_cap, lst_info) = create_lst_with_stake<TEST>(
            &mut system_state,
            fees::new_builder(scenario.ctx())
                .set_sui_mint_fee_bps(100)
                .set_redeem_fee_bps(100)
                .to_fee_config(),
            treasury_cap,
            vector::empty(),
            coin::mint_for_testing(1000  * MIST_PER_SUI - 1, scenario.ctx()),
            scenario.ctx()
        );

        test_scenario::return_shared(system_state);

        sui::test_utils::destroy(admin_cap);
        sui::test_utils::destroy(lst_info);
        sui::test_utils::destroy(coins);

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 0, location = liquid_staking::liquid_staking)]
    fun test_create_lst_with_stake_fail_4() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        let mut system_state = scenario.take_shared<SuiSystemState>();

        let mut treasury_cap = coin::create_treasury_cap_for_testing(scenario.ctx());
        let coins = treasury_cap.mint(1000 * MIST_PER_SUI, scenario.ctx());

        let (admin_cap, lst_info) = create_lst_with_stake<TEST>(
            &mut system_state,
            fees::new_builder(scenario.ctx())
                .set_sui_mint_fee_bps(100)
                .set_redeem_fee_bps(100)
                .to_fee_config(),
            treasury_cap,
            vector::empty(),
            coin::mint_for_testing(2000  * MIST_PER_SUI + 1, scenario.ctx()),
            scenario.ctx()
        );

        test_scenario::return_shared(system_state);

        sui::test_utils::destroy(admin_cap);
        sui::test_utils::destroy(lst_info);
        sui::test_utils::destroy(coins);

        scenario.end();
    }

    #[test]
    fun test_mint_and_redeem() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[100, 100]);

        scenario.next_tx(@0x0);

        let mut system_state = scenario.take_shared<SuiSystemState>();
        let sui = coin::mint_for_testing<SUI>(100 * MIST_PER_SUI, scenario.ctx());

        let (admin_cap, mut lst_info) = create_lst<TEST>(
            fees::new_builder(scenario.ctx())
                .set_sui_mint_fee_bps(100)
                .set_redeem_fee_bps(100)
                .to_fee_config(),
            coin::create_treasury_cap_for_testing(scenario.ctx()),
            scenario.ctx()
        );

        let lst = lst_info.mint(&mut system_state, sui, scenario.ctx());

        assert!(lst.value() == 99 * MIST_PER_SUI, 0);
        assert!(lst_info.total_lst_supply() == 99 * MIST_PER_SUI, 0);
        assert!(lst_info.total_sui_supply() == 99 * MIST_PER_SUI, 0);
        assert!(lst_info.fees() == 1 * MIST_PER_SUI, 0);
        sui::test_utils::destroy(lst);

        let sui = coin::mint_for_testing<SUI>(100 * MIST_PER_SUI, scenario.ctx());
        let mut lst = lst_info.mint(&mut system_state, sui, scenario.ctx());

        assert!(lst.value() == 99 * MIST_PER_SUI, 0);
        assert!(lst_info.total_lst_supply() == 198 * MIST_PER_SUI, 0);
        assert!(lst_info.total_sui_supply() == 198 * MIST_PER_SUI, 0);
        assert!(lst_info.fees() == 2 * MIST_PER_SUI, 0);


        let sui = lst_info.redeem(
            lst.split(10 * MIST_PER_SUI, scenario.ctx()), 
            &mut system_state, 
            scenario.ctx()
        );

        assert!(sui.value() ==  9_900_000_000, 0);
        assert!(lst_info.total_lst_supply() == 188 * MIST_PER_SUI, 0);
        assert!(lst_info.total_sui_supply() == 188 * MIST_PER_SUI, 0);
        assert!(lst_info.fees() == 2 * MIST_PER_SUI + 100_000_000, 0);

        sui::test_utils::destroy(sui);
        sui::test_utils::destroy(lst);

        test_scenario::return_shared(system_state);

        sui::test_utils::destroy(admin_cap);
        sui::test_utils::destroy(lst_info);

        scenario.end();
    }

    #[test]
    fun test_increase_and_decrease_validator_stake() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[10, 10]);

        scenario.next_tx(@0x0);

        let mut system_state = scenario.take_shared<SuiSystemState>();
        let sui = coin::mint_for_testing<SUI>(100 * MIST_PER_SUI, scenario.ctx());

        let (admin_cap, mut lst_info) = create_lst<TEST>(
            fees::new_builder(scenario.ctx())
                .set_sui_mint_fee_bps(100)
                .set_redeem_fee_bps(100)
                .to_fee_config(),
            coin::create_treasury_cap_for_testing(scenario.ctx()),
            scenario.ctx()
        );

        let lst = lst_info.mint(&mut system_state, sui, scenario.ctx());

        assert!(lst.value() == 99 * MIST_PER_SUI, 0);
        assert!(lst_info.total_lst_supply() == 99 * MIST_PER_SUI, 0);
        assert!(lst_info.total_sui_supply() == 99 * MIST_PER_SUI, 0);
        assert!(lst_info.fees() == 1 * MIST_PER_SUI, 0);

        lst_info.increase_validator_stake(
            &admin_cap, 
            &mut system_state, 
            @0x0,
            20 * MIST_PER_SUI, 
            scenario.ctx()
        );

        assert!(lst_info.total_lst_supply() == 99 * MIST_PER_SUI, 0);
        assert!(lst_info.total_sui_supply() == 99 * MIST_PER_SUI, 0);
        assert!(
            lst_info.storage().validators()[0].inactive_stake().borrow().staked_sui_amount() == 20 * MIST_PER_SUI, 
            0
        );

        lst_info.increase_validator_stake(
            &admin_cap, 
            &mut system_state, 
            @0x1,
            20 * MIST_PER_SUI, 
            scenario.ctx()
        );

        assert!(lst_info.total_lst_supply() == 99 * MIST_PER_SUI, 0);
        assert!(lst_info.total_sui_supply() == 99 * MIST_PER_SUI, 0);
        assert!(
            lst_info.storage().validators()[1].inactive_stake().borrow().staked_sui_amount() == 20 * MIST_PER_SUI, 
            0
        );

        test_scenario::return_shared(system_state);

        scenario.next_tx(@0x0);
        advance_epoch_with_reward_amounts(0, 20, &mut scenario);


        scenario.next_tx(@0x0);
        let mut system_state = scenario.take_shared<SuiSystemState>();

        lst_info.increase_validator_stake(
            &admin_cap, 
            &mut system_state, 
            @0x1,
            20 * MIST_PER_SUI, 
            scenario.ctx()
        );

        assert!(lst_info.total_lst_supply() == 99 * MIST_PER_SUI, 0);
        assert!(lst_info.total_sui_supply() == 99 * MIST_PER_SUI, 0);
        assert!(
            lst_info.storage().validators()[1].inactive_stake().borrow().staked_sui_amount() == 20 * MIST_PER_SUI, 
            0
        );
        assert!(
            lst_info.storage().validators()[1].active_stake().borrow().value() == 10 * MIST_PER_SUI, 
            0
        );

        lst_info.decrease_validator_stake(
            &admin_cap, 
            &mut system_state, 
            @0x1,
            40 * MIST_PER_SUI, 
            scenario.ctx()
        );

        assert!(lst_info.total_lst_supply() == 99 * MIST_PER_SUI, 0);
        assert!(lst_info.total_sui_supply() == 99 * MIST_PER_SUI, 0);
        assert!(
            lst_info.storage().validators()[1].inactive_stake().is_none(),
            0
        );
        assert!(
            lst_info.storage().validators()[1].active_stake().is_none(),
            0
        );

        sui::test_utils::destroy(lst);
        test_scenario::return_shared(system_state);

        sui::test_utils::destroy(admin_cap);
        sui::test_utils::destroy(lst_info);

        scenario.end();
    }

    #[test]
    fun test_spread_fee() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[90, 90]);

        scenario.next_tx(@0x0);

        let mut system_state = scenario.take_shared<SuiSystemState>();

        let (admin_cap, mut lst_info) = create_lst<TEST>(
            fees::new_builder(scenario.ctx())
                .set_spread_fee_bps(5000) // 50%
                .set_sui_mint_fee_bps(1000) // 10%
                .to_fee_config(),
            coin::create_treasury_cap_for_testing(scenario.ctx()),
            scenario.ctx()
        );

        let sui = coin::mint_for_testing<SUI>(100 * MIST_PER_SUI, scenario.ctx());
        let lst = lst_info.mint(&mut system_state, sui, scenario.ctx());

        assert!(lst.value() == 90 * MIST_PER_SUI, 0);

        lst_info.increase_validator_stake(
            &admin_cap, 
            &mut system_state, 
            @0x0,
            45 * MIST_PER_SUI, 
            scenario.ctx()
        );
        lst_info.increase_validator_stake(
            &admin_cap, 
            &mut system_state, 
            @0x1,
            45 * MIST_PER_SUI, 
            scenario.ctx()
        );

        test_scenario::return_shared(system_state);

        scenario.next_tx(@0x0);
        advance_epoch_with_reward_amounts(0, 0, &mut scenario);

        // got 90 SUI of rewards, 45 of that should be spread fee
        advance_epoch_with_reward_amounts(0, 270, &mut scenario);

        let mut system_state = scenario.take_shared<SuiSystemState>();
        let sui = lst_info.redeem(
            lst,
            &mut system_state, 
            scenario.ctx()
        );

        assert!(sui.value() == 135 * MIST_PER_SUI, 0);
        assert!(lst_info.storage().total_sui_supply() == 45 * MIST_PER_SUI, 0);
        assert!(lst_info.total_sui_supply() == 0, 0);
        assert!(lst_info.accrued_spread_fees() == 45 * MIST_PER_SUI, 0);

        let fees = lst_info.collect_fees(&mut system_state, &admin_cap, scenario.ctx());
        assert!(fees.value() == 55 * MIST_PER_SUI, 0); // 45 in spread, 10 in mint
        assert!(lst_info.accrued_spread_fees() == 0, 0);
        assert!(lst_info.storage().total_sui_supply() == 0, 0);

        sui::test_utils::destroy(sui);
        sui::test_utils::destroy(fees);
        test_scenario::return_shared(system_state);

        sui::test_utils::destroy(admin_cap);
        sui::test_utils::destroy(lst_info);

        scenario.end();
    }

    #[test]
    fun test_update_fees() {
        let mut scenario = test_scenario::begin(@0x0);

        setup_sui_system(&mut scenario, vector[90, 90]);

        scenario.next_tx(@0x0);

        let system_state = scenario.take_shared<SuiSystemState>();

        let (admin_cap, mut lst_info) = create_lst<TEST>(
            fees::new_builder(scenario.ctx())
                .set_spread_fee_bps(5000) // 50%
                .set_sui_mint_fee_bps(1000) // 10%
                .to_fee_config(),
            coin::create_treasury_cap_for_testing(scenario.ctx()),
            scenario.ctx()
        );

        lst_info.update_fees(
            &admin_cap,
            fees::new_builder(scenario.ctx())
                .set_spread_fee_bps(1000) // 10%
                .set_sui_mint_fee_bps(100) // 10%
                .to_fee_config()
        );

        assert!(lst_info.fee_config().spread_fee_bps() == 1000, 0);
        assert!(lst_info.fee_config().sui_mint_fee_bps() == 100, 0);

        test_scenario::return_shared(system_state);

        sui::test_utils::destroy(admin_cap);
        sui::test_utils::destroy(lst_info);

        scenario.end();
    }

    #[test]
    fun test_increase_validator_stake_by_dust_amount() {
        let mut scenario = test_scenario::begin(@0x0);
        setup_sui_system(&mut scenario, vector[100, 100]);
        scenario.next_tx(@0x0);

        let mut treasury_cap = coin::create_treasury_cap_for_testing<TEST>(scenario.ctx());
        let lst = treasury_cap.mint(100 * MIST_PER_SUI, scenario.ctx());

        let mut system_state = scenario.take_shared<SuiSystemState>();

        let (admin_cap, mut lst_info) = create_lst_with_stake<TEST>(
            &mut system_state,
            fees::new_builder(scenario.ctx())
                .set_spread_fee_bps(5000) // 50%
                .set_sui_mint_fee_bps(1000) // 10%
                .to_fee_config(),
            treasury_cap,
            vector::empty(),
            coin::mint_for_testing(100 * MIST_PER_SUI, scenario.ctx()),
            scenario.ctx()
        );

        let increased_amount = lst_info.increase_validator_stake(
            &admin_cap,
            &mut system_state,
            @0x0,
            MIST_PER_SUI - 1,
            scenario.ctx()
        );

        assert!(increased_amount == 0, 0);

        sui::test_utils::destroy(lst);

        test_scenario::return_shared(system_state);

        sui::test_utils::destroy(admin_cap);
        sui::test_utils::destroy(lst_info);

        scenario.end();
    }

    #[test]
    fun test_change_validator_priority() {
        let mut scenario = test_scenario::begin(@0x0);
        setup_sui_system(&mut scenario, vector[100, 100]);

        scenario.next_tx(@0x0);

        let mut treasury_cap = coin::create_treasury_cap_for_testing<TEST>(scenario.ctx());
        let lst = treasury_cap.mint(100 * MIST_PER_SUI, scenario.ctx());

        let mut system_state = scenario.take_shared<SuiSystemState>();
        let pool_id_1 = system_state.validator_staking_pool_id(@0x0);
        let pool_id_2 = system_state.validator_staking_pool_id(@0x1);

        let (admin_cap, mut lst_info) = create_lst_with_stake<TEST>(
            &mut system_state,
            fees::new_builder(scenario.ctx())
                .set_spread_fee_bps(5000) // 50%
                .set_sui_mint_fee_bps(1000) // 10%
                .to_fee_config(),
            treasury_cap,
            vector::empty(),
            coin::mint_for_testing(100 * MIST_PER_SUI, scenario.ctx()),
            scenario.ctx()
        );

        lst_info.increase_validator_stake(
            &admin_cap,
            &mut system_state,
            @0x0,
            MIST_PER_SUI,
            scenario.ctx()
        );

        lst_info.increase_validator_stake(
            &admin_cap,
            &mut system_state,
            @0x1,
            MIST_PER_SUI,
            scenario.ctx()
        );

        assert!(lst_info.storage().validators()[0].staking_pool_id() == pool_id_1);
        assert!(lst_info.storage().validators()[1].staking_pool_id() == pool_id_2);

        lst_info.change_validator_priority(
            &admin_cap,
            0,
            1
        );

        assert!(lst_info.storage().validators()[0].staking_pool_id() == pool_id_2);
        assert!(lst_info.storage().validators()[1].staking_pool_id() == pool_id_1);

        lst_info.change_validator_priority(
            &admin_cap,
            0,
            0
        );

        assert!(lst_info.storage().validators()[0].staking_pool_id() == pool_id_2);
        assert!(lst_info.storage().validators()[1].staking_pool_id() == pool_id_1);

        sui::test_utils::destroy(lst);

        test_scenario::return_shared(system_state);

        sui::test_utils::destroy(admin_cap);
        sui::test_utils::destroy(lst_info);

        scenario.end();
    }

    /* randomized testing */

    #[random_test]
    fun test_random_increase_validator_stake(mint_amount: u64, stake_amount: u64) {
        let mut scenario = test_scenario::begin(@0x0);
        setup_sui_system(&mut scenario, vector[100, 100]);
        scenario.next_tx(@0x0);

        let mut system_state = scenario.take_shared<SuiSystemState>();

        let (admin_cap, mut lst_info) = create_lst<TEST>(
            fees::new_builder(scenario.ctx())
                .set_spread_fee_bps(5000) // 50%
                .set_sui_mint_fee_bps(1000) // 10%
                .to_fee_config(),
            coin::create_treasury_cap_for_testing(scenario.ctx()),
            scenario.ctx()
        );

        let sui = coin::mint_for_testing<SUI>(mint_amount, scenario.ctx());
        let lst = lst_info.mint(&mut system_state, sui, scenario.ctx());
        let total_sui_supply = lst_info.total_sui_supply();

        let increased_amount = lst_info.increase_validator_stake(
            &admin_cap,
            &mut system_state,
            @0x0,
            stake_amount,
            scenario.ctx()
        );

        assert!(increased_amount == std::u64::min(total_sui_supply, stake_amount), 0);

        sui::test_utils::destroy(lst);

        test_scenario::return_shared(system_state);

        sui::test_utils::destroy(admin_cap);
        sui::test_utils::destroy(lst_info);

        scenario.end();
    }

    #[random_test]
    fun test_random_decrease_validator_stake(mint_amount: u64, unstake_amount: u64) {
        let mut scenario = test_scenario::begin(@0x0);
        setup_sui_system(&mut scenario, vector[100, 100]);
        scenario.next_tx(@0x0);

        let staked_sui = stake_with(0, std::u64::max(mint_amount / MIST_PER_SUI, 1), &mut scenario);
        let mut treasury_cap = coin::create_treasury_cap_for_testing<TEST>(scenario.ctx());
        let lst = treasury_cap.mint(mint_amount / MIST_PER_SUI * MIST_PER_SUI, scenario.ctx());

        advance_epoch_with_reward_amounts(0, 0, &mut scenario);

        let mut system_state = scenario.take_shared<SuiSystemState>();
        let fungible_staked_sui = system_state.convert_to_fungible_staked_sui(staked_sui, scenario.ctx());

        let (admin_cap, mut lst_info) = create_lst_with_stake<TEST>(
            &mut system_state,
            fees::new_builder(scenario.ctx())
                .set_spread_fee_bps(5000) // 50%
                .set_sui_mint_fee_bps(1000) // 10%
                .to_fee_config(),
            treasury_cap,
            vector[fungible_staked_sui],
            coin::zero<SUI>(scenario.ctx()),
            scenario.ctx()
        );

        let total_sui_supply = lst_info.total_sui_supply();

        let unstaked_amount = lst_info.decrease_validator_stake(
            &admin_cap,
            &mut system_state,
            @0x0,
            unstake_amount,
            scenario.ctx()
        );

        assert!(unstaked_amount <= std::u64::min(total_sui_supply, unstake_amount + MIST_PER_SUI), 0);

        sui::test_utils::destroy(lst);

        test_scenario::return_shared(system_state);

        sui::test_utils::destroy(admin_cap);
        sui::test_utils::destroy(lst_info);

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 6, location = liquid_staking::liquid_staking)]
    fun test_custom_redeem_request_fail_not_processed() {
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

        let lst_to_unstake = lst.split(10 * MIST_PER_SUI, scenario.ctx());
        let custom_redeem_request = lst_info.custom_redeem_request(lst_to_unstake,&mut system_state, scenario.ctx());

        let sui = lst_info.custom_redeem(custom_redeem_request, &mut system_state, scenario.ctx());

        test_scenario::return_shared(system_state);

        sui::test_utils::destroy(lst_info);
        sui::test_utils::destroy(lst);
        sui::test_utils::destroy(sui);
        sui::test_utils::destroy(admin_cap);

        scenario.end(); 
    }
}
