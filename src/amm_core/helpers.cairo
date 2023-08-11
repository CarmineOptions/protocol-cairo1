use starknet::contract_address::{contract_address_to_felt252, contract_address_try_from_felt252};
use starknet::get_block_timestamp;
use starknet::ContractAddress;
use traits::Into;
use traits::TryInto;
use option::OptionTrait;

use core::cmp::{max, min};

use cubit::f128::types::fixed::{Fixed, FixedTrait, MAX_u128, FixedInto};

use carmine_protocol::amm_core::oracles::agg::OracleAgg::{get_terminal_price, get_current_price};

use carmine_protocol::types::basic::{Math64x61_, OptionSide, OptionType, Int, Timestamp};
use carmine_protocol::types::option_::{Option_};

use carmine_protocol::amm_core::pricing::option_pricing::black_scholes;
use carmine_protocol::amm_core::pricing::fees::get_fees;
use carmine_protocol::amm_core::pricing::option_pricing_helpers::{
    get_new_volatility, get_time_till_maturity, select_and_adjust_premia, add_premia_fees,
};

use carmine_protocol::amm_core::constants::{
    OPTION_CALL, OPTION_PUT, TRADE_SIDE_LONG, TRADE_SIDE_SHORT, get_opposite_side,
    get_decimal, STOP_TRADING_BEFORE_MATURITY_SECONDS, RISK_FREE_RATE
};

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

fn assert_option_side_exists(option_side: u8, msg: felt252) {
    assert((option_side - TRADE_SIDE_LONG) * (option_side - TRADE_SIDE_SHORT) == 0, msg);
}

fn assert_option_type_exists(option_type: u8, msg: felt252) {
    assert((option_type - OPTION_CALL) * (option_type - OPTION_PUT) == 0, msg);
}

fn assert_address_not_zero(addr: ContractAddress, msg: felt252) {
    assert(contract_address_to_felt252(addr) != 0, msg);
}

// TODO: Implement felt252**pow
fn felt_power(num: felt252, pow: felt252) -> felt252 {
    // num ** pow
    num
}

// TODO: Make this generic/for more types (impl Eq or sum shit)
// cairo1 repo has similar functions in tests/test_utils.cairo or sth

fn check_deadline(deadline: Timestamp) {
    let current_block_time = get_block_timestamp();
    assert(current_block_time <= deadline, 'TX is too old');
}

// @notice Converts the value into Uint256 balance
// @dev Conversions from Math64_61 to Uint256
// @dev Only for balances/token amounts, takes care of getting decimals etc
// @dev This function was done in several steps to optimize this in terms precision. It's pretty
//      nasty in terms of deconstruction. I would suggest checking tests, it might be faster.
// @param x: Value to be converted
// @param currency_address: Address of the currency - used to get decimals
// @return Input converted to Uint256
// TODO: Check this function, wasn't checked for correct math
// TODO: This function is 100% wrong
fn toU256_balance(x: Fixed, currency_address: ContractAddress) -> u256 {
    // converts for example 1.2 ETH (as Math64_61 float) to int(1.2*10**18)

    // We will guide you through with an example
    // x = 1.2 * 2**61 (example input... 2**61 since it is Math64x61)
    // We want to divide the number by 2**61 and multiply by 10**18 to get number in the "wei style
    // But the order is important, first multiply and then divide, otherwise the .2 would be lost.
    // (1.2 * 2**61) * 10**18 / 2**61
    // We can split the 10*18 to (2**18 * 5**18)
    // (1.2 * 2**61) * 2**18 * 5**18 / 2**61

    // let decimals = get_decimal(currency_address).expect('toU256 - Unable to get decimals');
    // let five_to_dec = FixedTrait::from_unscaled_felt(felt_power(5, decimals));

    // let x_5 = x * five_to_dec;

    // assert_nn_fixed(x_5, 'x negative in toUint256_bal');
    // // TODO: Check below is late, it would've failed already
    // assert(x_5 <= FixedTrait::new(MAX_u128 - 1, false), 'x out of bound in toUint256_bal');

    // // we can rearange a little again
    // // (1.2 * 2**61 * 5**18) / (2**61 / 2**18)
    // // (1.2 * 2**61 * 5**18) / 2**(61 - 18)
    // let _64_minus_dec = 64 - decimals;
    // assert_nn_fixed(FixedTrait::from_felt(_64_minus_dec), '64 - dec negative toUint256_bal');

    // let decreased_part = felt_power(2, _64_minus_dec);
    // let decreased_part_u128: u128 = decreased_part
    //     .try_into()
    //     .expect('dec_part felt252 -> u128 failed');

    // let x_5_u128: u128 = x_5.try_into().expect('x_5 felt252 -> u128 failed');

    // let (q, r) = integer::u128_safe_divmod(
    //     x_5_u128, decreased_part_u128.try_into().expect('Division by 0 in toUint256_bal')
    // );

    // return q.into();
    return u256 { low: 1, high: 1 };
}

// @notice Converts the value from Uint256 balance to Math64_61
// @dev Conversions from Uint256 to Math64_61
// @dev Only for balances/token amounts, takes care of getting decimals etc
// @param x: Value to be converted
// @param currency_address: Address of the currency - used to get decimals
// @return Input converted to Math64_61
fn fromU256_balance(x: u256, currency_address: ContractAddress) -> Fixed {
    // TODO: This function is 100% wrong, finish pls

    // converts for example 1.2*10**18 wei to 1.2*2**61 (Math64x61).

    // We will guide you through with an example
    // x = 1.2*10**18 (example input... 10**18 since it is ETH)
    // We want to divide the number by 10**18 and multiply by 2**61 to get Math64x61 number
    // But the order is important, first multiply and then divide, otherwise the .2 would be lost.
    // (1.2 * 10**18) * 2**61 / 10**18
    // We can split the 10*18 to (2**18 * 5**18)
    // (1.2 * 10**18) * 2**61 / (5**18 * 2**18)

    // let decimal = get_decimal(currency_address).expect('fromU256 - cant to get decimals');
    // let five_to_dec = felt_power(5, decimal);

    // let sixty_four_plus_dec = 64 + decimal;
    // let increased_INT_PART = felt_power(2, sixty_four_plus_dec);
    // assert_le(x_low, increased_INT_PART);
    // assert_le(-increased_INT_PART, x_low);

    // (1.2 * 10**18) * 2**61 / (5**18 * 2**18)
    // so we have
    // x * 2**61 / (five_to_dec * 2**18)
    // and with a little bit of rearanging
    // (1.2 * 10**18) / 5**18 * (2**61 / 2**18)
    // (1.2 * 10**18) / 5**18 * 2**(61-18)
    // x / five_to_dec * 2**(sixty_one_minus_dec)
    // let sixty_four_minus_dec = 64 - decimal;
    // let decreased_FRACT_PART = felt_power(2, sixty_four_minus_dec);
    // x / five_to_dec * decreased_FRACT_PART
    // x * decreased_FRACT_PART / five_to_dec
    // let x_ = x * FixedTrait::from_felt(decreased_FRACT_PART);

    // x_ / five_to_dec
    // let (x__, _) = unsigned_div_rem(x_, five_to_dec);
    // Just checking the final number is not out of bounds.
    // Math64x61.assert64x61(x__);
    FixedTrait::from_felt(1)
}

fn split_option_locked_capital(
    option_type: OptionType,
    option_side: OptionSide,
    option_size: Fixed,
    strike_price: Fixed,
    terminal_price: Fixed,
) -> (Fixed, Fixed) {
    assert_option_type_exists(option_type, 'SOLC - unknown option type');

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
