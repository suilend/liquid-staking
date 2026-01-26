module liquid_staking::registry {
    use liquid_staking::{liquid_staking::{AdminCap, LiquidStakingInfo}, version::{Self, Version}};
    use std::type_name;
    use sui::bag::{Self, Bag};

    const CURRENT_VERSION: u16 = 1;

    public struct Registry has key, store {
        id: UID,
        version: Version,
        table: Bag,
    }

    public struct Entry<ExtraInfoType: store> has copy, store {
        admin_cap_id: ID,
        liquid_staking_info_id: ID,
        extra_info: ExtraInfoType,
    }

    /* Getter Functions */
    public fun admin_cap_id<ExtraInfoType: store>(self: &Entry<ExtraInfoType>): ID {
        self.admin_cap_id
    }

    public fun liquid_staking_info_id<ExtraInfoType: store>(self: &Entry<ExtraInfoType>): ID {
        self.liquid_staking_info_id
    }

    public fun extra_info<ExtraInfoType: store>(self: &Entry<ExtraInfoType>): &ExtraInfoType {
        &self.extra_info
    }

    public fun new(ctx: &mut TxContext): Registry {
        let registry = Registry {
            id: object::new(ctx),
            version: version::new(CURRENT_VERSION),
            table: bag::new(ctx),
        };

        registry
    }

    public(package) fun add_to_registry<CoinType, ExtraInfoType: store>(
        self: &mut Registry,
        admin_cap: &AdminCap<CoinType>,
        liquid_staking_info: &LiquidStakingInfo<CoinType>,
        extra_info: ExtraInfoType,
    ) {
        self.version.assert_version_and_upgrade(CURRENT_VERSION);

        self
            .table
            .add(
                type_name::with_defining_ids<CoinType>(),
                Entry {
                    admin_cap_id: object::id(admin_cap),
                    liquid_staking_info_id: object::id(liquid_staking_info),
                    extra_info,
                },
            );
    }

    public(package) fun get_entry<CoinType, ExtraInfoType: store>(
        self: &Registry,
    ): &Entry<ExtraInfoType> {
        self.table.borrow(type_name::with_defining_ids<CoinType>())
    }
}
