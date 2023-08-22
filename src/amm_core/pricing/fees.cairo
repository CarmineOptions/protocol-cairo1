use cubit::f128::types::fixed::{Fixed, FixedTrait};

use carmine_protocol::amm_core::constants::FEE_PROPORTION_PERCENT;

//
// @title Fees Module
//

// @notice Calculate fees from the value
// @dev Fees might be in the future dependent on many different variables and on the current state
// @param value: Value that fees will be calculated from
// @return fees: Calculated fees
fn get_fees(value: Fixed) -> Fixed {
    let hundred = FixedTrait::new_unscaled(100_u128, false);
    let fee_percent = FixedTrait::new_unscaled(FEE_PROPORTION_PERCENT, false);
    return fee_percent / hundred * value;
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('', ))]
fn test_() {
    assert(1 == 0, '');
}
