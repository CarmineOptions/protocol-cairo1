use traits::Into;

use cubit::f128::types::fixed::{Fixed, FixedTrait};

// yes I didn't find something equivalent elsewhere.
// This could be generic for generic types but I'm not wasting more time with half-assed Cairo
// FIXME use a canonical implementation
// https://github.com/influenceth/cubit/blob/main/src/f128/math/core.cairo
fn pow(base: u128, pow: u8) -> u128 {
    if (pow == 0) {
        1_u128
    } else {
        let mut res: u128 = base;
        let mut power = pow;
        loop {
            if power == 1 {
                break res;
            }
            res = res * base;
            power = power - 1;
        }
    }
}

fn convert_from_int_to_Fixed(value: u128, decimals: u8) -> Fixed {
    // Overflows (fails) when converting approx 1 million ETH, would need to use u256 for that, different code path needed.
    // TODO test that it indeed overflows.

    let denom = pow(5, decimals);
    let numer = pow(2, 64 - decimals);

    let res = (value * numer) / denom;

    FixedTrait::from_felt(res.into())
}


#[test]
fn test_sth() {
    assert(1 == 0, 'big sad')
}
