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
    let res = fee_percent / hundred * value;
    // value.mag.print();
    return res;
}


// Tests --------------------------------------------------------------------------------------------------------------
use debug::PrintTrait;
#[test]
fn test_get_fees() {
    let res1 = get_fees(FixedTrait::from_unscaled_felt(100));
    let res2 = get_fees(FixedTrait::from_unscaled_felt(200));
    let res3 = get_fees(FixedTrait::from_unscaled_felt(3));
    let res4 = get_fees(FixedTrait::from_unscaled_felt(10));
    let res5 = get_fees(FixedTrait::from_unscaled_felt(523));

    assert(
        res1 == FixedTrait::from_felt(55340232221128654800), 'Should be 3'
    ); // Result is basically three, like 8e-19 error
    assert(res2 == FixedTrait::from_felt(110680464442257309600), 'Should be 6');
    assert(res3 == FixedTrait::from_felt(1660206966633859644), 'Should be ~0.09');
    assert(res4 == FixedTrait::from_felt(5534023222112865480), 'Should be ~0.03');
    assert(res5 == FixedTrait::from_felt(289429414516502864604), 'Should be ~15.69');
}
