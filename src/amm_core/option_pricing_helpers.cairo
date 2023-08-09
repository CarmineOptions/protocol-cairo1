use starknet::ContractAddress;
use traits::{Into, TryInto};
use option::OptionTrait;
use starknet::get_block_timestamp;

use cubit::f128::types::fixed::{Fixed, FixedTrait};
use carmine_protocol::amm_core::helpers::{
    get_decimal, felt_power, assert_option_type_exists, assert_option_side_exists,
};
use carmine_protocol::amm_core::constants::{TRADE_SIDE_LONG, TRADE_SIDE_SHORT};

use carmine_protocol::types::basic::{
    OptionType, OptionSide, Timestamp
};

use carmine_protocol::amm_core::constants::{OPTION_CALL, OPTION_PUT};

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

    assert_option_type_exists(option_type, 'CATOCFBU - unknown option type');
    assert(amount > 0, 'CATOCFBU - amt <= 0');

    if option_type == OPTION_PUT {
        let base_token_decimals = get_decimal(base_token_address)
            .expect('CATOCFBU - Cant get decimals');
        let dec = felt_power(10, base_token_decimals);
        let dec: u256 = dec.into();

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

    secs_left / secs_in_year
}

fn select_and_adjust_premia(
    call_premia: Fixed, put_premia: Fixed, option_type: OptionType, underlying_price: Fixed
) -> Fixed {
    assert_option_type_exists(option_type, 'SAAP - invalid option type');

    if option_type == OPTION_CALL {
        call_premia / underlying_price
    } else {
        put_premia
    }
}

fn add_premia_fees(side: OptionSide, total_premia_before_fees: Fixed, total_fees: Fixed) -> Fixed {
    assert_option_side_exists(side, 'APF - invalid option side');

    if side == TRADE_SIDE_LONG {
        total_premia_before_fees + total_fees
    } else {
        total_premia_before_fees - total_fees
    }
}
