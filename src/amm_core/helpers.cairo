use starknet::contract_address::contract_address_try_from_felt252;
use starknet::get_block_timestamp;
use starknet::ContractAddress;
use traits::Into;
use traits::TryInto;
use option::OptionTrait;

use core::cmp::max;
use core::cmp::min;

use integer::U128DivRem;

use cubit::f128::types::fixed::Fixed;
use cubit::f128::types::fixed::FixedTrait;
use cubit::f128::types::fixed::MAX_u128;
use cubit::f128::types::fixed::FixedInto;

use carmine_protocol::amm_core::oracles::agg::OracleAgg::get_terminal_price;
use carmine_protocol::amm_core::oracles::agg::OracleAgg::get_current_price;

use carmine_protocol::types::basic::Math64x61_;
use carmine_protocol::types::basic::OptionSide;
use carmine_protocol::types::basic::OptionType;
use carmine_protocol::types::basic::Int;
use carmine_protocol::types::basic::Timestamp;

use carmine_protocol::types::option_::Option_;

use carmine_protocol::amm_core::pricing::option_pricing::OptionPricing::black_scholes;
use carmine_protocol::amm_core::pricing::fees::get_fees;

use carmine_protocol::amm_core::pricing::option_pricing_helpers::get_new_volatility;
use carmine_protocol::amm_core::pricing::option_pricing_helpers::get_time_till_maturity;
use carmine_protocol::amm_core::pricing::option_pricing_helpers::select_and_adjust_premia;
use carmine_protocol::amm_core::pricing::option_pricing_helpers::add_premia_fees;

use carmine_protocol::amm_core::constants::OPTION_CALL;
use carmine_protocol::amm_core::constants::OPTION_PUT;
use carmine_protocol::amm_core::constants::TRADE_SIDE_LONG;
use carmine_protocol::amm_core::constants::TRADE_SIDE_SHORT;
use carmine_protocol::amm_core::constants::get_opposite_side;
use carmine_protocol::amm_core::constants::STOP_TRADING_BEFORE_MATURITY_SECONDS;
use carmine_protocol::amm_core::constants::RISK_FREE_RATE;
use carmine_protocol::amm_core::constants::TOKEN_ETH_ADDRESS;
use carmine_protocol::amm_core::constants::TOKEN_USDC_ADDRESS;

use carmine_protocol::erc20_interface::IERC20Dispatcher;
use carmine_protocol::erc20_interface::IERC20DispatcherTrait;

// Some helpful functions for Fixed type
#[generate_trait]
impl FixedHelpersImpl of FixedHelpersTrait {
    // @notice Asserts that given Fixed number is >= 0
    // @param self: Fixed Instance
    // @param msg: Error message for assert statement
    fn assert_nn_not_zero(self: Fixed, msg: felt252) {
        assert(self > FixedTrait::ZERO(), msg);
    }

    // @notice Asserts that given Fixed number is > 0
    // @param self: Fixed Instance
    // @param msg: Error message for assert statement
    fn assert_nn(self: Fixed, errmsg: felt252) {
        assert(self >= FixedTrait::ZERO(), errmsg)
    }

    // @notice Converts Fixed number to Math64x61 number (used in Cairo 0)
    // @param self: Fixed Instance
    // @returns Math64x61 (num * 2**61)
    fn to_legacyMath(self: Fixed) -> Math64x61_ {
        // Fixed is 8 times the old math
        let new: felt252 = (self / FixedTrait::from_unscaled_felt(8)).into();
        new
    }

    // @notice Converts Math64x61 number to Fixed number
    // @param num: Math64x61 number
    // @returns Fixed number
    fn from_legacyMath(num: Math64x61_) -> Fixed {
        // 2**61 is 8 times smaller than 2**64
        // so we can just multiply old legacy math number by 8 to get cubit 
        FixedTrait::from_felt(num * 8)
    }
}

// @notice Asserts that given option side is valid (either 0 or 1)
// @param option_side: Option side value to be checked
// @param msg: Error message for assert statement
fn assert_option_side_exists(option_side: felt252, msg: felt252) {
    assert(
        (option_side - TRADE_SIDE_LONG.into()) * (option_side - TRADE_SIDE_SHORT.into()) == 0, msg
    );
}

// @notice Asserts that given option type is valid (either 0 or 1)
// @param option_type: Option type value to be checked
// @param msg: Error message for assert statement
fn assert_option_type_exists(option_type: felt252, msg: felt252) {
    assert((option_type - OPTION_CALL.into()) * (option_type - OPTION_PUT.into()) == 0, msg);
}

// @notice Asserts that current timestamp is less or equal to tx deadline
// @param deadline:  Deadline timestamp of tx
fn check_deadline(deadline: Timestamp) {
    let current_block_time = get_block_timestamp();
    assert(current_block_time <= deadline, 'TX is too old');
}


// @notice Returns value of a to the power of b
// @param a:  base
// @param b: exponent
// @return a ** b
fn pow(a: u128, b: u128) -> u128 {
    let mut x: u128 = a;
    let mut n = b;

    if n == 0 {
        // 0**0 is undefined
        assert(x > 0, 'Undefined pow action');

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


// @notice Converts the value into Uint256 balance
// @dev Conversions from Cubit to Uint256
// @dev Only for balances/token amounts, takes care of getting decimals etc
// @dev This function was done in several steps to optimize this in terms precision. It's pretty
//      nasty in terms of deconstruction. I would suggest checking tests, it might be faster.
// @param x: Value to be converted
// @param currency_address: Address of the currency - used to get decimals
// @return Input converted to Uint256
fn toU256_balance(x: Fixed, currency_address: ContractAddress) -> u256 {
    // converts for example 1.2 ETH (as Math64_61 float) to int(1.2*10**18)

    // We will guide you through with an example
    // x = 1.2 * 2**61 (example input... 2**61 since it is Math64x61)
    // We want to divide the number by 2**61 and multiply by 10**18 to get number in the "wei style
    // But the order is important, first multiply and then divide, otherwise the .2 would be lost.
    // (1.2 * 2**64) * 10**18 / 2**64
    // We can split the 10*18 to (2**18 * 5**18)
    // (1.2 * 2**64) * 2**18 * 5**18 / 2**64

    x.assert_nn('toU256 - x is zero'); //  Now we can just use the mag in Fixed

    let decimals: u128 = get_decimal(currency_address)
        .expect('toU256 - Unable to get decimals')
        .into();

    _toU256_balance(x, decimals)
}

fn _toU256_balance(x: Fixed, decimals: u128) -> u256 {
    let five_to_dec = pow(5, decimals);

    let x_5 = x.mag * five_to_dec;

    // // we can rearange a little again
    // // (1.2 * 2**61 * 5**18) / (2**61 / 2**18)
    // // (1.2 * 2**61 * 5**18) / 2**(61 - 18)
    let _64_minus_dec = 64 - decimals;

    let decreased_part = pow(2, _64_minus_dec);

    let (q, r) = integer::u128_safe_divmod(
        x_5, decreased_part.try_into().expect('toU256 - dp zero')
    );

    q.into()
}

// @notice Converts the value from Uint256 balance to Cubit
// @dev Conversions from Uint256 to Cubit
// @dev Only for balances/token amounts, takes care of getting decimals etc
// @param x: Value to be converted
// @param currency_address: Address of the currency - used to get decimals
// @return Input converted to Math64_61
fn fromU256_balance(x: u256, currency_address: ContractAddress) -> Fixed {
    // We will guide you through with an example
    // x = 1.2*10**18 (example input... 10**18 since it is ETH)
    // We want to divide the number by 10**18 and multiply by 2**64 to get Math64x61 number
    // But the order is important, first multiply and then divide, otherwise the .2 would be lost.
    // (1.2 * 10**18) * 2**61 / 10**18
    // We can split the 10*18 to (2**18 * 5**18)
    // (1.2 * 10**18) * 2**64 / (5**18 * 2**18)

    let decimals: u128 = get_decimal(currency_address).expect('fromU256 - decimals zero').into();

    _fromU256_balance(x, decimals)
}

fn _fromU256_balance(x: u256, decimals: u128) -> Fixed {
    let five_to_dec = pow(5, decimals);

    // (1.2 * 10**18) * 2**64 / (5**18 * 2**18)
    // so we have
    // x * 2**64 / (five_to_dec * 2**18)
    // and with a little bit of rearanging
    // (1.2 * 10**18) / 5**18 * (2**64 / 2**18)
    // (1.2 * 10**18) / 5**18 * 2**(64-18)
    // x / five_to_dec * 2**(sixty_one_minus_dec)
    let sixty_four_minus_dec = 64 - decimals;
    let decreased_FRACT_PART = pow(2, sixty_four_minus_dec);
    let x_ = x.low * decreased_FRACT_PART;
    // x / five_to_dec * decreased_FRACT_PART
    // x * decreased_FRACT_PART / five_t_dec

    // x_ / five_to_dec
    let (q, rem) = U128DivRem::div_rem(x_, five_to_dec.try_into().expect('fromU256 - ftd zero'));
    Fixed { mag: q, sign: false }
}

fn split_option_locked_capital(
    option_type: OptionType, option_size: Fixed, strike_price: Fixed, terminal_price: Fixed,
) -> (Fixed, Fixed) {
    assert_option_type_exists(option_type.into(), 'SOLC - unknown option type');

    if option_type == OPTION_CALL {
        // User receives option_size * max(0,  (terminal_price - strike_price) / terminal_price) in base token for long
        // User receives option_size * (1 - max(0,  (terminal_price - strike_price) / terminal_price)) for short
        // Summing the two equals option_size
        // In reality there is rounding that is happening and since we are not able to distribute
        // tokens to buyers and sellers all at the same transaction and since users can split
        // tokens we have to do it like this to ensure that
        // locked capital >= to_be_paid_buyer + to_be_paid_seller
        // and the equality cannot be guaranteed because of the reasons above

        let price_diff = terminal_price - strike_price;
        let price_relative_diff = price_diff / terminal_price;

        let buyer_relative_profit = max(FixedTrait::from_felt(0), price_relative_diff);
        let seller_relative_profit = FixedTrait::from_unscaled_felt(1) - buyer_relative_profit;

        let to_be_paid_buyer = option_size * buyer_relative_profit;
        let to_be_paid_seller = option_size * seller_relative_profit;

        return (to_be_paid_buyer, to_be_paid_seller);
    }

    // For Put option
    // User receives option_size * max(0, (strike_price - terminal_price)) in quote token for long
    // User receives option_size * min(strike_price, terminal_price) for short
    // Summing the two equals option_size * strike_price (=locked capital

    let price_diff = strike_price - terminal_price;
    let buyer_relative_profit = max(FixedTrait::from_felt(0), price_diff);
    let seller_relative_profit = min(strike_price, terminal_price);

    let to_be_paid_buyer = option_size * buyer_relative_profit;
    let to_be_paid_seller = option_size * seller_relative_profit;

    return (to_be_paid_buyer, to_be_paid_seller);
}

fn get_underlying_from_option_data(
    option_type: OptionType,
    base_token_address: ContractAddress,
    quote_token_address: ContractAddress,
) -> ContractAddress {
    if option_type == OPTION_CALL {
        base_token_address
    } else {
        quote_token_address
    }
}

// @notice Get decimal count for the given token
// @dev 18 for ETH, 6 for USDC
// @param token_address: Address of the token for which decimals are being retrieved
// @return dec: Decimal count
fn get_decimal(token_address: ContractAddress) -> Option<u8> {
    if token_address == TOKEN_ETH_ADDRESS.try_into()? {
        return Option::Some(18);
    }

    if token_address == TOKEN_USDC_ADDRESS.try_into()? {
        return Option::Some(6);
    }

    assert(!token_address.is_zero(), 'Token address is zero');

    let decimals = IERC20Dispatcher { contract_address: token_address }.decimals();
    assert(decimals != 0, 'Token has decimals = 0');

    if decimals == 0 {
        return Option::None(());
    } else {
        let decimals_felt: felt252 = decimals.into();
        return Option::Some(decimals_felt.try_into()?);
    }
}

// Tests --------------------------------------------------------------------------------------------------------------
#[cfg(test)]
mod tests {
    use starknet::ContractAddress;

    use cubit::f128::types::fixed::Fixed;
    use cubit::f128::types::fixed::FixedTrait;
    use cubit::f128::types::fixed::MAX_u128;
    use cubit::f128::types::fixed::FixedInto;

    use super::get_underlying_from_option_data;
    use super::assert_option_side_exists;
    use super::assert_option_type_exists;
    use super::split_option_locked_capital;
    use super::pow;
    use super::_fromU256_balance;
    use super::_toU256_balance;


    #[test]
    fn test_get_underlying_from_option_data() {
        let opt_type_call = 0;
        let opt_type_put = 1;

        let base_token_addr: ContractAddress = 0.try_into().unwrap();
        let quote_token_addr: ContractAddress = 1.try_into().unwrap();

        let res_1 = get_underlying_from_option_data(
            opt_type_call, base_token_addr, quote_token_addr
        );
        let res_2 = get_underlying_from_option_data(
            opt_type_put, base_token_addr, quote_token_addr
        );

        assert(res_1 == base_token_addr, 'res1');
        assert(res_2 == quote_token_addr, 'res1');
    }

    // assert_option_side_exists
    #[test]
    fn test_assert_option_side_exists() {
        assert_option_side_exists(1, '1');
        assert_option_side_exists(0, '0');
    }

    #[test]
    #[should_panic]
    fn test_assert_option_side_exists_failing() {
        assert_option_side_exists(2, 'Unknown option side')
    }


    #[test]
    fn test_assert_option_type_exists() {
        assert_option_type_exists(1, '1');
        assert_option_type_exists(0, '0');
    }

    #[test]
    #[should_panic]
    fn test_assert_option_type_exists_failing() {
        assert_option_type_exists(2, 'Unknown option type')
    }

    use debug::PrintTrait;

    #[test]
    fn test_split_option_locked_capital() {
        let opt_call = 0;
        let opt_put = 1;

        let opt_size = FixedTrait::ONE();
        let strike_price = FixedTrait::from_unscaled_felt(1_000);

        let terminal_price_higher = FixedTrait::from_unscaled_felt(1_500);
        let terminal_price_lower = FixedTrait::from_unscaled_felt(500);

        let (long1, short1) = split_option_locked_capital(
            opt_call, opt_size, strike_price, terminal_price_higher
        );
        let (long2, short2) = split_option_locked_capital(
            opt_call, opt_size, strike_price, terminal_price_lower
        );

        assert(long1 == FixedTrait::from_felt(6148914691236517205), 'long1'); // 0.33...
        assert(short1 == FixedTrait::from_felt(12297829382473034411), 'short1'); // 0.66...

        assert(long2 == FixedTrait::ZERO(), 'long2'); // 0
        assert(short2 == FixedTrait::ONE(), 'short2'); // 1

        let (long3, short3) = split_option_locked_capital(
            opt_put, opt_size, strike_price, terminal_price_higher
        );
        let (long4, short4) = split_option_locked_capital(
            opt_put, opt_size, strike_price, terminal_price_lower
        );

        assert(long3 == FixedTrait::ZERO(), 'long3'); // 0
        assert(short3 == FixedTrait::from_unscaled_felt(1_000), 'long3'); // 1_000

        assert(long4 == FixedTrait::from_unscaled_felt(500), 'long4'); // 500
        assert(short4 == FixedTrait::from_unscaled_felt(500), 'short4'); // 500
    }

    #[test]
    fn test__pow() {
        assert(pow(10, 10) == 10000000000, '1');
        assert(pow(10, 5) == 100000, '2');
        assert(pow(10, 2) == 100, '3');

        assert(pow(2, 8) == 256, '4');
        assert(pow(2, 16) == 65536, '5');
        assert(pow(2, 32) == 4294967296, '6');
        assert(pow(2, 56) == 72057594037927936, '7');
        assert(pow(2, 64) == 18446744073709551616, '8');

        assert(pow(17, 21) == 69091933913008732880827217, '9');
        assert(pow(34, 13) == 81138303245565435904, '10');
    }

    #[test]
    #[should_panic]
    fn test__pow_failing() {
        pow(69, 69); // Should overflow
    }

    #[test]
    fn test__fromU256_balance() {
        let res1 = _fromU256_balance(1000000000000000000, 18); // ie 1 eth
        let res2 = _fromU256_balance(50000000000000, 12); // 50 of something
        let res3 = _fromU256_balance(1000000000, 6); // ie 1k usdc

        assert(res1 == FixedTrait::ONE(), 'res1');
        assert(res2 == FixedTrait::from_unscaled_felt(50), 'res2');
        assert(res3 == FixedTrait::from_unscaled_felt(1_000), 'res3');

        let res4 = _fromU256_balance(54128590000000000000, 18);
        let res5 = _fromU256_balance(1124235700000, 12);
        let res6 = _fromU256_balance(100183370000, 6);

        assert(res4 == FixedTrait::from_felt(998496246800754098506), 'res4');
        assert(res5 == FixedTrait::from_felt(20738488236427709357), 'res5');
        assert(res6 == FixedTrait::from_felt(1848056986831751282079825), 'res6');
    }

    #[test]
    fn test__toU256_balance() {
        let res1 = _toU256_balance(FixedTrait::ONE(), 18);
        let res2 = _toU256_balance(FixedTrait::from_unscaled_felt(50), 12);
        let res3 = _toU256_balance(FixedTrait::from_unscaled_felt(1_000), 6);

        assert(res1 == 1000000000000000000, 'res1');
        assert(res2 == 50000000000000, 'res2');
        assert(res3 == 1000000000, 'res3');

        let res4 = _toU256_balance(FixedTrait::from_felt(998496246800754098506), 18);
        let res5 = _toU256_balance(FixedTrait::from_felt(20738488236427709357), 12);
        let res6 = _toU256_balance(FixedTrait::from_felt(1848056986831751282079825), 6);

        assert(res4 == 54128589999999999999, 'res4'); // 1 gwei rounding error
        assert(res5 == 1124235699999, 'res5'); // also
        assert(res6 == 100183369999, 'res6'); // also
    }
}
