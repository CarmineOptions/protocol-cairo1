//
// @title Helper module for options pricing
//

use starknet::ContractAddress;
use traits::Into;
use traits::TryInto;
use option::OptionTrait;
use starknet::get_block_timestamp;

use cubit::f128::types::fixed::Fixed;
use cubit::f128::types::fixed::FixedTrait;
use carmine_protocol::amm_core::helpers::get_decimal;
use carmine_protocol::amm_core::helpers::assert_option_type_exists;
use carmine_protocol::amm_core::helpers::assert_option_side_exists;
use carmine_protocol::amm_core::helpers::pow;

use carmine_protocol::amm_core::constants::TRADE_SIDE_LONG;
use carmine_protocol::amm_core::constants::TRADE_SIDE_SHORT;

use carmine_protocol::types::basic::OptionType;
use carmine_protocol::types::basic::OptionSide;
use carmine_protocol::types::basic::Timestamp;

use carmine_protocol::amm_core::constants::OPTION_CALL;
use carmine_protocol::amm_core::constants::OPTION_PUT;

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
    assert(amount >= 0, 'CATOCFBU - amt <= 0');

    if option_type == OPTION_PUT {
        let base_token_decimals: u128 = get_decimal(base_token_address)
            .expect('CATOCFBU - Cant get decimals')
            .into();
        let dec: u256 = pow(10, base_token_decimals).into();

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

// @notice Calculates new volatility and trade volatility
// @param current_volatility: Current volatility in Fixed
// @param option_size: Option size in Fixed... for example 1.2 size is represented as 1.2 * 2 ** 64
// @param option_type: 0 for CALL and 1 for put
// @param side: 0 for LONG and 1 for SHORT
// @param strike_price: strike price in Fixed
// @param pool_volatility_adjustment_speed: parameter that determines speed of volatility adjustments
// @return New volatility and trade volatility
fn get_new_volatility(
    current_volatility: Fixed,
    option_size: Fixed,
    option_type: OptionType,
    side: OptionSide,
    strike_price: Fixed,
    pool_volatility_adjustment_speed: Fixed
) -> (Fixed, Fixed) {
    let hundred = FixedTrait::from_unscaled_felt(100);
    let two = FixedTrait::from_unscaled_felt(2);

    let option_size_in_pool_currency = get_option_size_in_pool_currency(
        option_size, option_type, strike_price
    );
    let relative_option_size = option_size_in_pool_currency
        / pool_volatility_adjustment_speed
        * hundred;

    let new_volatility = if side == TRADE_SIDE_LONG {
        current_volatility + relative_option_size
    } else {
        current_volatility - relative_option_size
    };

    let trade_volatility = (current_volatility + new_volatility) / two;

    (new_volatility, trade_volatility)
}

// @notice Converts option size into pool's currency
// @dev for call it does no transform and for put it multiplies the size by strike
// @param option_size: Option size to be converted in Fixed
// @param option_type: Option type - 0 for call and 1 for put
// @param strike_price: Strike price in Fixed
// @return Converted size in Fixed
fn get_option_size_in_pool_currency(
    option_size: Fixed, option_type: OptionType, strike_price: Fixed
) -> Fixed {
    if option_type == OPTION_CALL {
        option_size
    } else {
        option_size * strike_price
    }
}

// @notice Gets time till maturity in years
// @dev Calculates time till maturity in terms of Fixed type
//      Inputted maturity if not in the same type -> has to converted... and it is number
//      of seconds corresponding to unix timestamp
// @param maturity: Maturity as unix timestamp
// @return time till maturity 
fn get_time_till_maturity(maturity: Timestamp) -> Fixed {
    let curr_time = get_block_timestamp();
    let curr_time = FixedTrait::new_unscaled(curr_time.into(), false);
    let maturity = FixedTrait::new_unscaled(maturity.into(), false);

    let secs_in_year = FixedTrait::from_unscaled_felt(60 * 60 * 24 * 365);

    assert(maturity >= curr_time, 'GTTM - secs_left < 0');
    let secs_left = maturity - curr_time;

    secs_left.assert_nn('GTTM - secs left negative');

    secs_left / secs_in_year
}

// @notice Selects value based on option type and if call adjusts the value to base tokens
// @dev  Call and Put premia on input are in quote tokens (in USDC in case of ETH/USDC)
//      This function puts them into their respective currency
//      (and selects the premia based on option_type)
//          - call premia into base token (ETH in case of ETH/USDC)
//          - put premia stays the same, ie in quote tokens (USDC in case of ETH/USDC)
// @param call_premia: Call premium
// @param put_premia: Put premium
// @param option_type: Option type - 0 for call and 1 for put
// @param underlying_price: Price of the underlying (spot) in Fixed
// @return Select either put or call premium and if call adjust by price of underlying
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

// @notice Adds premium and fees (for long add and for short diff)
// @param side: 0 for long and 1 for short
// @param total_premia_before_fees: premium in Fixed
// @param total_fees: fees in Fixed
// @return Premium adjusted for fees
fn add_premia_fees(side: OptionSide, total_premia_before_fees: Fixed, total_fees: Fixed) -> Fixed {
    assert_option_side_exists(side.into(), 'APF - invalid option side');

    if side == TRADE_SIDE_LONG {
        total_premia_before_fees + total_fees
    } else {
        total_premia_before_fees - total_fees
    }
}


// Tests --------------------------------------------------------------------------------------------------------------
#[cfg(test)]
mod tests {

    use debug::PrintTrait;
    use carmine_protocol::testing::test_utils::is_close;
    use array::ArrayTrait;
    
    use cubit::f128::types::fixed::Fixed;
    use cubit::f128::types::fixed::FixedTrait;

    use super::add_premia_fees;
    use super::select_and_adjust_premia;
    use super::get_option_size_in_pool_currency;
    use super::get_time_till_maturity;


    use super::get_new_volatility;

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

    #[test]
    fn test_get_new_volatility() {
        let rel_tol = FixedTrait::from_felt(184467440737095520); // 0.01
        let mut test_cases = get_test_get_new_volatility_cases();

        let strike_price = FixedTrait::from_unscaled_felt(1_000);

        loop {
            match test_cases.pop_front() {
                Option::Some((
                    option_type, option_side, option_size, volatility
                )) => {
                    let vol_adj_spd = if option_type == 0 {
                        FixedTrait::from_unscaled_felt(10_000)
                    } else {
                        FixedTrait::from_unscaled_felt(10_000_000)
                    };
                    let two = FixedTrait::from_unscaled_felt(2);
                    let half_opt_size = option_size / two;

                    let (desired_vol, _) = get_new_volatility(
                        volatility, option_size, option_type, option_side, strike_price, vol_adj_spd
                    );

                    let (vol1, _) = get_new_volatility(
                        volatility, half_opt_size, option_type, option_side, strike_price, vol_adj_spd
                    );

                    let (vol2, _) = get_new_volatility(
                        vol1, // Use previous vol
                        half_opt_size,
                        option_type,
                        option_side,
                        strike_price,
                        vol_adj_spd
                    );

                    assert(is_close(desired_vol, vol2, rel_tol), 'Fail');
                },
                Option::None(()) => {
                    break;
                }
            };
        }
    }

    // Test contract
    #[starknet::interface]
    trait ITestCon<TContractState> {
        fn get_ttm(self: @TContractState, maturity: super::Timestamp) -> Fixed;
    }

    #[starknet::contract]
    mod TestCon {
        #[storage]
        struct Storage {}


        use cubit::f128::types::fixed::{Fixed, FixedTrait};
        use super::get_time_till_maturity;

        #[external(v0)]
        impl TestCon of super::ITestCon<ContractState> {
            fn get_ttm(self: @ContractState, maturity: u64) -> Fixed {
                get_time_till_maturity(maturity)
            }
        }
    }


    use snforge_std::{start_warp, stop_warp, declare, ContractClassTrait};
    use result::Result;
    use result::ResultTrait;

    #[test]
    fn test_get_time_till_maturity() {
        // Deploy contract
        let test_contract = declare('TestCon');
        let contract_address = test_contract.deploy(@ArrayTrait::new()).unwrap();

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

    fn get_test_get_new_volatility_cases() -> Array<(u8, u8, Fixed, Fixed)> {
        let mut arr = ArrayTrait::<(u8, u8, Fixed, Fixed)>::new();

        arr
            .append(
                (
                    0,
                    0,
                    FixedTrait::from_felt(800000000000000000),
                    FixedTrait::from_felt(1844674407370955264)
                )
            );
        arr
            .append(
                (
                    1,
                    0,
                    FixedTrait::from_felt(800000000000000000),
                    FixedTrait::from_felt(1844674407370955264)
                )
            );
        arr
            .append(
                (
                    1,
                    1,
                    FixedTrait::from_felt(34400000000000000000),
                    FixedTrait::from_felt(22136092888451461120)
                )
            );
        arr
            .append(
                (
                    1,
                    0,
                    FixedTrait::from_felt(800000000000000000),
                    FixedTrait::from_felt(1844674407370955264)
                )
            );
        arr
            .append(
                (
                    0,
                    1,
                    FixedTrait::from_felt(800000000000000000),
                    FixedTrait::from_felt(1844674407370955264)
                )
            );
        arr
            .append(
                (
                    0,
                    1,
                    FixedTrait::from_felt(31200000000000000000),
                    FixedTrait::from_felt(143884603774934499328)
                )
            );
        arr
            .append(
                (
                    1,
                    0,
                    FixedTrait::from_felt(800000000000000000),
                    FixedTrait::from_felt(1844674407370955264)
                )
            );
        arr
            .append(
                (
                    0,
                    0,
                    FixedTrait::from_felt(31200000000000000000),
                    FixedTrait::from_felt(1844674407370955264)
                )
            );
        arr
            .append(
                (
                    0,
                    0,
                    FixedTrait::from_felt(31200000000000000000),
                    FixedTrait::from_felt(35048813740048146432)
                )
            );
        arr
            .append(
                (
                    0,
                    0,
                    FixedTrait::from_felt(62400000000000000000),
                    FixedTrait::from_felt(1844674407370955264)
                )
            );
        arr
            .append(
                (
                    0,
                    0,
                    FixedTrait::from_felt(62400000000000000000),
                    FixedTrait::from_felt(175244068700240740352)
                )
            );
        arr
            .append(
                (
                    0,
                    0,
                    FixedTrait::from_felt(76000000000000000000),
                    FixedTrait::from_felt(175244068700240740352)
                )
            );
        arr
            .append(
                (
                    1,
                    0,
                    FixedTrait::from_felt(68800000000000000000),
                    FixedTrait::from_felt(105146441220144447488)
                )
            );
        arr
            .append(
                (
                    1,
                    0,
                    FixedTrait::from_felt(45600000000000000000),
                    FixedTrait::from_felt(105146441220144447488)
                )
            );
        arr
            .append(
                (
                    0,
                    0,
                    FixedTrait::from_felt(45600000000000000000),
                    FixedTrait::from_felt(105146441220144447488)
                )
            );
        arr
            .append(
                (
                    0,
                    0,
                    FixedTrait::from_felt(72000000000000000000),
                    FixedTrait::from_felt(38738162554790060032)
                )
            );
        arr
            .append(
                (
                    0,
                    0,
                    FixedTrait::from_felt(16800000000000000000),
                    FixedTrait::from_felt(38738162554790060032)
                )
            );
        arr
            .append(
                (
                    1,
                    0,
                    FixedTrait::from_felt(60000000000000000000),
                    FixedTrait::from_felt(1844674407370955264)
                )
            );
        arr
            .append(
                (
                    1,
                    0,
                    FixedTrait::from_felt(60000000000000000000),
                    FixedTrait::from_felt(138350580552821637120)
                )
            );
        arr
            .append(
                (
                    0,
                    0,
                    FixedTrait::from_felt(60000000000000000000),
                    FixedTrait::from_felt(138350580552821637120)
                )
            );
        arr
            .append(
                (
                    1,
                    0,
                    FixedTrait::from_felt(44000000000000000000),
                    FixedTrait::from_felt(97767743590660620288)
                )
            );
        arr
            .append(
                (
                    1,
                    0,
                    FixedTrait::from_felt(44000000000000000000),
                    FixedTrait::from_felt(101457092405402533888)
                )
            );
        arr
            .append(
                (
                    0,
                    0,
                    FixedTrait::from_felt(44000000000000000000),
                    FixedTrait::from_felt(101457092405402533888)
                )
            );
        arr
            .append(
                (
                    0,
                    0,
                    FixedTrait::from_felt(51200000000000000000),
                    FixedTrait::from_felt(16602069666338596864)
                )
            );
        arr
            .append(
                (
                    0,
                    0,
                    FixedTrait::from_felt(51200000000000000000),
                    FixedTrait::from_felt(118059162071741136896)
                )
            );
        arr
            .append(
                (
                    0,
                    1,
                    FixedTrait::from_felt(16000000000000000000),
                    FixedTrait::from_felt(31359464925306236928)
                )
            );
        arr
            .append(
                (
                    0,
                    0,
                    FixedTrait::from_felt(16000000000000000000),
                    FixedTrait::from_felt(31359464925306236928)
                )
            );
        arr
            .append(
                (
                    0,
                    0,
                    FixedTrait::from_felt(16000000000000000000),
                    FixedTrait::from_felt(36893488147419103232)
                )
            );
        arr
            .append(
                (
                    0,
                    1,
                    FixedTrait::from_felt(28800000000000000000),
                    FixedTrait::from_felt(29514790517935284224)
                )
            );
        arr
            .append(
                (
                    1,
                    1,
                    FixedTrait::from_felt(28800000000000000000),
                    FixedTrait::from_felt(29514790517935284224)
                )
            );
        arr
            .append(
                (
                    1,
                    1,
                    FixedTrait::from_felt(12800000000000000000),
                    FixedTrait::from_felt(29514790517935284224)
                )
            );
        arr
            .append(
                (
                    1,
                    0,
                    FixedTrait::from_felt(37600000000000000000),
                    FixedTrait::from_felt(47961534591644835840)
                )
            );
        arr
            .append(
                (
                    1,
                    0,
                    FixedTrait::from_felt(20800000000000000000),
                    FixedTrait::from_felt(47961534591644835840)
                )
            );
        arr
            .append(
                (
                    1,
                    1,
                    FixedTrait::from_felt(20800000000000000000),
                    FixedTrait::from_felt(47961534591644835840)
                )
            );
        arr
            .append(
                (
                    0,
                    0,
                    FixedTrait::from_felt(4000000000000000000),
                    FixedTrait::from_felt(18446744073709551616)
                )
            );
        arr
            .append(
                (
                    0,
                    0,
                    FixedTrait::from_felt(8000000000000000000),
                    FixedTrait::from_felt(18446744073709551616)
                )
            );
        arr
            .append(
                (
                    1,
                    1,
                    FixedTrait::from_felt(9600000000000000000),
                    FixedTrait::from_felt(71942301887467249664)
                )
            );
        arr
            .append(
                (
                    1,
                    1,
                    FixedTrait::from_felt(9600000000000000000),
                    FixedTrait::from_felt(22136092888451461120)
                )
            );
        arr
            .append(
                (
                    0,
                    0,
                    FixedTrait::from_felt(22400000000000000000),
                    FixedTrait::from_felt(177088743107611688960)
                )
            );
        arr
            .append(
                (
                    0,
                    0,
                    FixedTrait::from_felt(22400000000000000000),
                    FixedTrait::from_felt(51650883406386741248)
                )
            );
        arr
            .append(
                (
                    1,
                    0,
                    FixedTrait::from_felt(65599999999999991808),
                    FixedTrait::from_felt(77476325109580120064)
                )
            );
        arr
            .append(
                (
                    1,
                    0,
                    FixedTrait::from_felt(65599999999999991808),
                    FixedTrait::from_felt(77476325109580120064)
                )
            );
        arr
            .append(
                (
                    1,
                    1,
                    FixedTrait::from_felt(65599999999999991808),
                    FixedTrait::from_felt(77476325109580120064)
                )
            );
        arr
            .append(
                (
                    1,
                    1,
                    FixedTrait::from_felt(33600000000000000000),
                    FixedTrait::from_felt(77476325109580120064)
                )
            );
        arr
            .append(
                (
                    0,
                    1,
                    FixedTrait::from_felt(48000000000000000000),
                    FixedTrait::from_felt(162331347848644067328)
                )
            );
        arr
            .append(
                (
                    0,
                    1,
                    FixedTrait::from_felt(48000000000000000000),
                    FixedTrait::from_felt(110680464442257309696)
                )
            );
        arr
            .append(
                (
                    0,
                    0,
                    FixedTrait::from_felt(48000000000000000000),
                    FixedTrait::from_felt(110680464442257309696)
                )
            );
        arr
            .append(
                (
                    0,
                    1,
                    FixedTrait::from_felt(40000000000000000000),
                    FixedTrait::from_felt(154952650219160240128)
                )
            );
        arr
            .append(
                (
                    0,
                    1,
                    FixedTrait::from_felt(40000000000000000000),
                    FixedTrait::from_felt(92233720368547758080)
                )
            );
        arr
            .append(
                (
                    1,
                    1,
                    FixedTrait::from_felt(40000000000000000000),
                    FixedTrait::from_felt(92233720368547758080)
                )
            );
        arr
    }
}