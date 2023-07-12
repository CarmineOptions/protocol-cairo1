use starknet::ContractAddress;
use starknet::contract_address::contract_address_to_felt252;
use traits::Into;


use carmine_protocol::traits::{ IERC20Dispatcher, IERC20DispatcherTrait };

const FEE_PROPORTION_PERCENT: u128 = 3_u128;

const OPTION_CALL: felt252 = 0;
const OPTION_PUT: felt252 = 1;

const TRADE_SIDE_LONG: felt252 = 0;
const TRADE_SIDE_SHORT: felt252 = 1;

const SEPARATE_VOLATILITIES_FOR_DIFFERENT_STRIKES: felt252 = 1;
const VOLATILITY_LOWER_BOUND: felt252 = 1;
const VOLATILITY_UPPER_BOUND: felt252 = 42535295865117307932921825928971026432; // 2**64 * 2**61





const TOKEN_ETH_ADDRESS: felt252 = 0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7; // mainnet
const TOKEN_USD_ADDRESS: felt252 = 0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8; // mainnet

// @notice Get decimal count for the given token
// @dev 18 for ETH, 6 for USDC
// @param token_address: Address of the token for which decimals are being retrieved
// @return dec: Decimal count
fn get_decimal(token_address: ContractAddress) -> felt252 {

    if contract_address_to_felt252(token_address) == TOKEN_ETH_ADDRESS {
        return 18;
    }

    if contract_address_to_felt252(token_address) == TOKEN_ETH_ADDRESS {
        return 6;
    }

    assert(contract_address_to_felt252(token_address) != 0, 'Token address is zero');

    let decimals = IERC20Dispatcher{contract_address: token_address}.decimals();
    assert(decimals != 0, 'Token has decimals = 0');

    let decimals_felt: felt252 = decimals.into();
    return decimals_felt;

    // TODO: Following code breaks my LSP :/
    // match token_address {
    //     TOKEN_ETH_ADDRESS => {
    //         return 18_u8;
    //     },
    //     TOKEN_USD_ADDRESS => {
    //         return 6_u8;
    //     },
    //     _ => {
    //         assert(contract_address_to_felt252(token_address) != 0, 'Token address is zero');

    //         let decimals = IERC20Dispatcher{contract_address: token_address}.decimals();

    //         assert(decimals != 0, 'Token has decimals = 0');

    //         let decimals_felt: felt252 = decimals.into();
    //         return decimals_felt;

    //     }
    // }

}

