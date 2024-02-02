//
// @title Constants Contract
//

use core::traits::TryInto;
use starknet::ContractAddress;
use starknet::contract_address::contract_address_to_felt252;
use traits::Into;

use carmine_protocol::amm_core::helpers::assert_option_side_exists;

const FEE_PROPORTION_PERCENT: u128 = 3_u128;
const RISK_FREE_RATE: felt252 = 0;

const OPTION_CALL: u8 = 0;
const OPTION_PUT: u8 = 1;

const TRADE_SIDE_LONG: u8 = 0;
const TRADE_SIDE_SHORT: u8 = 1;


// @notice Return the opposite option side of the input
// @param trade_side: Option side
// @return opposite side: Opposite option side
fn get_opposite_side(trade_side: u8) -> u8 {
    assert_option_side_exists(trade_side.into(), 'GES - invalid option side');

    if trade_side == TRADE_SIDE_LONG {
        TRADE_SIDE_SHORT
    } else {
        TRADE_SIDE_LONG
    }
}

const STOP_TRADING_BEFORE_MATURITY_SECONDS: u64 = 7200;

const VOLATILITY_LOWER_BOUND: felt252 = 1;
const VOLATILITY_UPPER_BOUND: felt252 = 42535295865117307932921825928971026432; // 2**64 * 2**61

const TOKEN_ETH_ADDRESS: felt252 =
    0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7; // mainnet and testnet
const TOKEN_USDC_ADDRESS: felt252 =
    0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8; // mainnet
// const TOKEN_USDC_ADDRESS: felt252 =
//     0x0643907b9a4bc6a55e9069c4fd5fd1f5c79a22470690f75556c4736e34426; // testnet

const TOKEN_WBTC_ADDRESS: felt252 =
    0x03fe2b97c1fd336e750087d68b9b867997fd64a2661ff3ca5a7c771641e8e7ac; // mainnet
// const TOKEN_WBTC_ADDRESS: felt252 =
//     0x012d537dc323c439dc65c976fad242d5610d27cfb5f31689a0a319b8be7f3d56; // testnet

const TOKEN_STRK_ADDRESS: felt252 =
    0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d; // testnet

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    #[test]
    fn test_get_opposite_side() {
        let res_1 = super::get_opposite_side(super::TRADE_SIDE_LONG);
        let res_2 = super::get_opposite_side(super::TRADE_SIDE_SHORT);

        assert(res_1 == super::TRADE_SIDE_SHORT, 'res1');
        assert(res_2 == super::TRADE_SIDE_LONG, 'res1');
    }
    #[test]
    #[should_panic(expected: ('GES - invalid option side',))]
    fn test_get_opposite_side_failing() {
        let res_1 = super::get_opposite_side(2);
    }
}
