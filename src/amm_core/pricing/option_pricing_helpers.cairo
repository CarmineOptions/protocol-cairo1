use starknet::ContractAddress;
use traits::{Into, TryInto};
use option::OptionTrait;
use starknet::get_block_timestamp;

use cubit::f128::types::fixed::{Fixed, FixedTrait};
use carmine_protocol::amm_core::helpers::{
    get_decimal, assert_option_type_exists, assert_option_side_exists, _pow
};
use carmine_protocol::amm_core::constants::{TRADE_SIDE_LONG, TRADE_SIDE_SHORT};

use carmine_protocol::types::basic::{OptionType, OptionSide, Timestamp};
use carmine_protocol::amm_core::constants::{OPTION_CALL, OPTION_PUT};
use carmine_protocol::amm_core::helpers::FixedHelpersTrait;

// @notice Converts amount to the currency used by the option
// @dev Amount is in base tokens (in ETH in case of ETH/USDC)
//      This function puts amount into the currency required by given option_type
//          - for call into base token (ETH in case of ETH/USDC)
//          - for put into quote token (USDC in case of ETH/USDC)
// @param amount: Amount to be converted
// @param option_type: Option type - 0 for call and 1 for put
// @param strike_price: Strike price
// @param base_token_address: Address of the base token
// @return Converted amount value
fn convert_amount_to_option_currency_from_base_uint256(
    amount: u256, option_type: OptionType, strike_price: u256, base_token_address: ContractAddress
) -> u256 {
    // Amount is in base tokens (in ETH in case of ETH/USDC)
    // This function puts amount into the currency required by given option_type
    //  - for call into base token (ETH in case of ETH/USDC)
    //  - for put into quote token (USDC in case of ETH/USDC)   

    assert_option_type_exists(option_type.into(), 'CATOCFBU - unknown option type');
    assert(amount > 0, 'CATOCFBU - amt <= 0');

    if option_type == OPTION_PUT {
        let base_token_decimals: u128 = get_decimal(base_token_address)
            .expect('CATOCFBU - Cant get decimals')
            .into();
        let dec: u256 = _pow(10, base_token_decimals).into();

        let adj_amount = amount * strike_price;

        let (quot, rem) = integer::U256DivRem::div_rem(
            adj_amount, dec.try_into().expect('Div by zero in CATOCFBU')
        );
        assert(quot >= 0, 'CATOCFBU: Opt size too low');
        assert(rem == 0, 'CATOCFBU: Value rounded'); // TODO: better msg

        return quot;
    }

    return amount;
}

fn get_new_volatility(
    current_volatility: Fixed,
    option_size: Fixed,
    option_type: OptionType,
    side: OptionSide,
    strike_price: Fixed,
    get_pool_volatility_adjustment_speed: Fixed
) -> (Fixed, Fixed) {
    let hundred = FixedTrait::from_unscaled_felt(100);
    let two = FixedTrait::from_unscaled_felt(2);

    let option_size_in_pool_currency = get_option_size_in_pool_currency(
        option_size, option_type, strike_price
    );

    let relative_option_size = option_size_in_pool_currency
        / get_pool_volatility_adjustment_speed
        * hundred;

    let new_volatility = if side == TRADE_SIDE_LONG {
        current_volatility + relative_option_size
    } else {
        current_volatility - relative_option_size
    };

    let trade_volatility = (current_volatility + new_volatility) / two;

    (new_volatility, trade_volatility)
}

fn get_option_size_in_pool_currency(
    option_size: Fixed, option_type: OptionType, strike_price: Fixed
) -> Fixed {
    if option_type == OPTION_CALL {
        option_size
    } else {
        option_size * strike_price
    }
}

fn get_time_till_maturity(maturity: Timestamp) -> Fixed {
    let curr_time = get_block_timestamp();
    let curr_time = FixedTrait::new_unscaled(curr_time.into(), false);

    let maturity = FixedTrait::new(maturity.into(), false);

    let secs_in_year = FixedTrait::from_felt(60 * 60 * 24 * 365);

    assert(maturity >= curr_time, 'GTTM - secs_left < 0');
    let secs_left = maturity - curr_time;

    secs_left.assert_nn('GTTM - secs left negative');

    secs_left / secs_in_year
}

fn select_and_adjust_premia(
    call_premia: Fixed, put_premia: Fixed, option_type: OptionType, underlying_price: Fixed
) -> Fixed {
    assert_option_type_exists(option_type.into(), 'SAAP - invalid option type');

    if option_type == OPTION_CALL {
        call_premia / underlying_price
    } else {
        put_premia
    }
}

fn add_premia_fees(side: OptionSide, total_premia_before_fees: Fixed, total_fees: Fixed) -> Fixed {
    assert_option_side_exists(side.into(), 'APF - invalid option side');

    if side == TRADE_SIDE_LONG {
        total_premia_before_fees + total_fees
    } else {
        total_premia_before_fees - total_fees
    }
}


// Tests --------------------------------------------------------------------------------------------------------------

use debug::PrintTrait;

#[test]
fn test_add_premia_fees() {
    let side_long = 0;
    let side_short = 1;
    let total_premia_before_fees_1 = FixedTrait::from_unscaled_felt(100);
    let total_premia_before_fees_2 = FixedTrait::from_unscaled_felt(69);
    let total_premia_before_fees_3 = FixedTrait::from_unscaled_felt(420);

    let total_fees = FixedTrait::from_unscaled_felt(3);

    let res_1 = add_premia_fees(side_long, total_premia_before_fees_1, total_fees);
    let res_2 = add_premia_fees(side_short, total_premia_before_fees_1, total_fees);
    let res_3 = add_premia_fees(side_long, total_premia_before_fees_2, total_fees);
    let res_4 = add_premia_fees(side_short, total_premia_before_fees_2, total_fees);
    let res_5 = add_premia_fees(side_long, total_premia_before_fees_3, total_fees);
    let res_6 = add_premia_fees(side_short, total_premia_before_fees_3, total_fees);

    assert(res_1 == FixedTrait::from_felt(1900014639592083816448), 'res1');
    assert(res_2 == FixedTrait::from_felt(1789334175149826506752), 'res2');
    assert(res_3 == FixedTrait::from_felt(1328165573307087716352), 'res3');
    assert(res_4 == FixedTrait::from_felt(1217485108864830406656), 'res4');
    assert(res_5 == FixedTrait::from_felt(7802972743179140333568), 'res5');
    assert(res_6 == FixedTrait::from_felt(7692292278736883023872), 'res6');
}

#[test]
fn test_select_and_adjust_premia() {
    let type_call = 0;
    let type_put = 1;

    let call_premia = FixedTrait::from_unscaled_felt(50);
    let put_premia = FixedTrait::from_unscaled_felt(100);

    let underlying_price = FixedTrait::from_unscaled_felt(1000);

    let res1 = select_and_adjust_premia(call_premia, put_premia, type_call, underlying_price);
    let res2 = select_and_adjust_premia(call_premia, put_premia, type_put, underlying_price);

    assert(res1 == call_premia / underlying_price, 'res1');
    assert(res2 == put_premia, 'res2');
}

#[test]
fn test_get_option_size_in_pool_currency() {
    let type_call = 0;
    let type_put = 1;

    let option_size = FixedTrait::from_unscaled_felt(1);
    let strike_price = FixedTrait::from_unscaled_felt(1_000);

    let res1 = get_option_size_in_pool_currency(option_size, type_call, strike_price);
    let res2 = get_option_size_in_pool_currency(option_size, type_put, strike_price);

    assert(res1 == option_size, 'res1');
    assert(res2 == option_size * strike_price, 'res2');
}

// TODO: Below
// #[test]
// fn test_get_new_volatility() {
// }

// Test contract
#[starknet::interface]
trait ITestCon<TContractState> {
    fn get_ttm(self: @TContractState, maturity: Timestamp) -> Fixed;
}

#[starknet::contract]
mod TestCon {
    #[storage]
    struct Storage {}


    use cubit::f128::types::fixed::{Fixed, FixedTrait};

    #[external(v0)]
    impl TestCon of super::ITestCon<ContractState> {
        fn get_ttm(self: @ContractState, maturity: u64) -> super::Fixed {
            super::get_time_till_maturity(maturity)
        }
    }
}


use snforge_std::{start_warp, stop_warp, declare, PreparedContract, deploy};
use result::Result;
use result::ResultTrait;

#[test]
fn test_get_time_till_maturity() {
    // Deploy contract
    let class_hash = declare('TestCon');
    let prepared = PreparedContract {
        class_hash: class_hash, constructor_calldata: @ArrayTrait::new()
    };
    let contract_address = deploy(prepared).unwrap();

    let dispatcher = ITestConDispatcher { contract_address };

    start_warp(contract_address, 0);
    let res1 = dispatcher.get_ttm(31536000); // 1 year ttm -> 365 * 24 * 3600
    let res2 = dispatcher.get_ttm(15768000); // 0.5 year ttm -> 365 * 24 * 3600 / 2
    let res3 = dispatcher.get_ttm(2628000); // 1 month ttm -> 365 * 24 * 3600 / 12
    let res4 = dispatcher.get_ttm(606461); // 1 week ttm -> 365 * 24 * 3600 / 52
    let res5 = dispatcher.get_ttm(86400); // 1 day ttm -> 24 * 3600 

    assert(res1 == FixedTrait::ONE(), 'res1');
    assert(res2 == FixedTrait::ONE() / FixedTrait::from_unscaled_felt(2), 'res2');
    assert(res3 == FixedTrait::ONE() / FixedTrait::from_unscaled_felt(12), 'res3');
    assert(res4 == FixedTrait::from_felt(354744763371574339), 'res4'); // Very small rounding here
    assert(res5 == FixedTrait::ONE() / FixedTrait::from_unscaled_felt(365), 'res5');
}
