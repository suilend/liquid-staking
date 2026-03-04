module assumptions::assumptions;

/*
    Here we validate the assumptions we make in the main spec's summaries
 */

use cvlm::manifest::{rule, function_access};
use cvlm::asserts::cvlm_assert;
use sui_system::staking_pool::PoolTokenExchangeRate;

public fun cvlm_manifest() {
    rule(b"get_sui_amount_equivalence");

    function_access(b"ls_get_sui_amount", @liquid_staking, b"storage", b"get_sui_amount");
    function_access(b"ss_get_sui_amount", @sui_system, b"staking_pool", b"get_sui_amount");
}

// private function accessors
native fun ls_get_sui_amount(exchange_rate: &PoolTokenExchangeRate, token_amount: u64): u64;
native fun ss_get_sui_amount(exchange_rate: &PoolTokenExchangeRate, token_amount: u64): u64;

// The main suilend spec's summaries assume that liquid_staking::storage::get_sui_amount is equivalent to
// sui_system::staking_pool::get_sui_amount.  We validate that assumption here.
public fun get_sui_amount_equivalence(
    exchange_rate: &PoolTokenExchangeRate,
    token_amount: u64
) {
    let ls_amount = ls_get_sui_amount(exchange_rate, token_amount);
    let ss_amount = ss_get_sui_amount(exchange_rate, token_amount);
    cvlm_assert(ls_amount == ss_amount);
} 

