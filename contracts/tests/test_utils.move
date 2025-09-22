#[allow(deprecated_usage)]
#[test_only]
module liquid_staking::test_utils {
    use sui::address;
    use sui_system::governance_test_utils::{
        create_validator_for_testing,
    };
    use sui_system::validator::{Validator};

    /// Create a validator set with the given stake amounts
    public fun create_validators_with_stakes(
        stakes: vector<u64>,
        ctx: &mut TxContext,
    ): vector<Validator> {
        let mut i = 0;
        let mut validators = vector[];
        while (i < stakes.length()) {
            let validator = create_validator_for_testing(address::from_u256(i as u256), stakes[i], ctx);
            validators.push_back(validator);
            i = i + 1
        };
        validators
    }
}