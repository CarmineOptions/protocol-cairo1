use core::array::SpanTrait;
use core::traits::TryInto;
use traits::Into;
use option::OptionTrait;

use cubit::f128::types::fixed::{Fixed, FixedTrait};

fn pow(a: u128, b: u128) -> u128 {
    let mut x: u128 = a;
    let mut n = b;

    if n == 0 {
        return 1;
    }

    let mut y = 1;
    let two = integer::u128_as_non_zero(2);

    loop {
        if n <= 1 {
            break;
        }

        let (div, rem) = integer::u128_safe_divmod(n, two);

        if rem == 1 {
            y = x * y;
        }

        x = x * x;
        n = div;
    };
    x * y
}

fn convert_from_int_to_Fixed(value: u128, decimals: u8) -> Fixed {
    // Overflows (fails) when converting approx 1 million ETH, would need to use u256 for that, different code path needed.
    // TODO test that it indeed overflows.

    let denom: u128 = pow(5, decimals.into());
    let numer: u128 = pow(2, 64 - decimals.into());

    let res: u128 = (value * numer) / denom;

    FixedTrait::from_felt(res.into())
}

#[test]
#[available_gas(3000000)]
fn test_convert_from_int_to_Fixed() {
    assert(convert_from_int_to_Fixed(1000000000000000000, 18) == FixedTrait::ONE(), 'oneeth!!');
}

fn convert_from_Fixed_to_int(value: Fixed, decimals: u8) -> u128 {
    assert(value.sign == false, 'cant convert -val to uint');

    (value.mag * pow(5, decimals.into())) / pow(2, (64 - decimals).into())
}

#[test]
#[available_gas(3000000)]
fn test_convert_from_Fixed_to_int() {
    let oneeth = convert_from_Fixed_to_int(FixedTrait::ONE(), 18);
    assert(oneeth == 1000000000000000000, 'oneeth?');
}

type Math64x61_ = felt252;

trait FixedHelpersTrait {
    fn assert_nn_not_zero(self: Fixed, msg: felt252);
    fn assert_nn(self: Fixed, errmsg: felt252);
    fn to_legacyMath(self: Fixed) -> Math64x61_;
    fn from_legacyMath(num: Math64x61_) -> Fixed;
}

impl FixedHelpersImpl of FixedHelpersTrait {
    fn assert_nn_not_zero(self: Fixed, msg: felt252) {
        assert(self > FixedTrait::ZERO(), msg);
    }

    fn assert_nn(self: Fixed, errmsg: felt252) {
        assert(self >= FixedTrait::ZERO(), errmsg)
    }

    fn to_legacyMath(self: Fixed) -> Math64x61_ {
        // TODO: Find better way to do this, this is just wrong
        // Fixed is 8 times the old math
        let new: felt252 = (self / FixedTrait::from_unscaled_felt(8)).into();
        new
    }

    fn from_legacyMath(num: Math64x61_) -> Fixed {
        // 2**61 is 8 times smaller than 2**64
        // so we can just multiply old legacy math number by 8 to get cubit 
        FixedTrait::from_felt(num * 8)
    }
}

fn percent<T, impl TInto: Into<T, felt252>>(inp: T) -> Fixed {
    FixedTrait::from_unscaled_felt(inp.into()) / FixedTrait::from_unscaled_felt(100)
}

use array::ArrayTrait;
fn reverse(inp: Span<Fixed>) -> Span<Fixed> {
    let mut res = ArrayTrait::<Fixed>::new();
    let mut i = inp.len() - 1;
    loop {
        if (i == 0) {
            res.append(*(inp.at(i)));
            break;
        }
        res.append(*(inp.at(i)));
        i -= 1;
    };
    res.span()
}
