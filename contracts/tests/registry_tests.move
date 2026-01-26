#[test_only]
module liquid_staking::registry_tests {
    use liquid_staking::{fees, liquid_staking, registry, weight};
    use std::unit_test;
    use sui::{coin, test_scenario};

    public struct TEST has drop {}

    #[test]
    fun test_add_weight_hook_to_registry() {
        let mut scenario = test_scenario::begin(@0x0);

        let (admin_cap, lst_info) = liquid_staking::create_lst<TEST>(
            fees::new_builder(scenario.ctx()).to_fee_config(),
            coin::create_treasury_cap_for_testing(scenario.ctx()),
            scenario.ctx(),
        );

        let admin_cap_id = object::id(&admin_cap);
        let lst_info_id = object::id(&lst_info);

        let (weight_hook, weight_hook_admin_cap) = weight::new(admin_cap, scenario.ctx());

        let mut registry = registry::new(scenario.ctx());
        weight_hook.add_to_registry(&mut registry, &lst_info);

        let entry = registry::get_entry<TEST, weight::RegistryInfo>(&registry);
        assert!(entry.admin_cap_id() == admin_cap_id);
        assert!(entry.liquid_staking_info_id() == lst_info_id);
        assert!(entry.extra_info().weight_hook_id() == object::id(&weight_hook));

        unit_test::destroy(lst_info);
        unit_test::destroy(weight_hook);
        unit_test::destroy(weight_hook_admin_cap);
        unit_test::destroy(registry);

        scenario.end();
    }
}
