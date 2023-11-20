use traits::Into;

use cubit::f128::types::fixed::{Fixed, FixedTrait};

use carmine_protocol::amm_core::helpers::pow;

fn convert_from_int_to_Fixed(value: u128, decimals: u8) -> Fixed {
    // Overflows (fails) when converting approx 1 million ETH, would need to use u256 for that, different code path needed.

    let denom = pow(5, decimals.into());
    let numer = pow(2, (64 - decimals).into());

    let res = (value * numer) / denom;

    FixedTrait::from_felt(res.into())
}
