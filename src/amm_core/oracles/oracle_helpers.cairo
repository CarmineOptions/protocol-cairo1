use traits::Into;

use cubit::f128::types::fixed::{Fixed, FixedTrait};

use carmine_protocol::amm_core::helpers::pow;


fn convert_from_int_to_Fixed(value: u128, decimals: u8) -> Fixed {
    // Overflows (fails) when converting approx 1 million ETH, would need to use u256 for that, different code path needed.
    // TODO test that it indeed overflows.

    let denom = pow(5, decimals.into());
    let numer = pow(2, (64 - decimals).into());

    let res = (value * numer) / denom;

    FixedTrait::from_felt(res.into())
}
// // Tests --------------------------------------------------------------------------------------------------------------
// // use 
// use debug::PrintTrait;
// #[test]
// #[available_gas(2000000)]
// fn test_pow() {
//     let res = pow(2, 56);
//     res.print();
//     assert(res == 72057594037927936, 'Should not fail')
// }


