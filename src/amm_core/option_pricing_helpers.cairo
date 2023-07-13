
use starknet::ContractAddress;
use traits::{Into, TryInto};
use option::OptionTrait;


use carmine_protocol::amm_core::helpers::{get_decimal, felt_power};
use carmine_protocol::types::{ OptionType };
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
    amount: u256,
    option_type: OptionType,
    strike_price: u256, 
    base_token_address: ContractAddress
) -> u256 {
    // Amount is in base tokens (in ETH in case of ETH/USDC)
    // This function puts amount into the currency required by given option_type
    //  - for call into base token (ETH in case of ETH/USDC)
    //  - for put into quote token (USDC in case of ETH/USDC)   

    assert((option_type - OPTION_CALL) * (option_type - OPTION_PUT) ==0, 'CATOCFBU - unknown option type');
    assert(amount > 0, 'CATOCFBU - amt <= 0');

    if option_type == OPTION_PUT {
        let base_token_decimals = get_decimal(base_token_address);
        let dec = felt_power(10, base_token_decimals);
        let dec: u256 = dec.into();

        let adj_amount = amount * strike_price;

        let (quot, rem) = integer::u256_safe_divmod(
            adj_amount, 
            dec.try_into().expect('Div by zero in CATOCFBU')
        );
        assert(quot >= 0, 'CATOCFBU: Opt size too low');
        assert(rem == 0, 'CATOCFBU: Value rounded'); // TODO: better msg

        return quot;
    }

    return amount;
}
