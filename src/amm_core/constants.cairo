use core::traits::TryInto;
use starknet::ContractAddress;
use starknet::contract_address::contract_address_to_felt252;
use traits::Into;

use carmine_protocol::amm_core::helpers::{assert_option_side_exists, assert_address_not_zero};

const FEE_PROPORTION_PERCENT: u128 = 3_u128;
const RISK_FREE_RATE: felt252 = 0;

const OPTION_CALL: u8 = 0;
const OPTION_PUT: u8 = 1;

const TRADE_SIDE_LONG: u8 = 0;
const TRADE_SIDE_SHORT: u8 = 1;

fn get_opposite_side(trade_side: u8) -> u8 {
    assert_option_side_exists(trade_side, 'GES - invalid option side');

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
    0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7; // mainnet
const TOKEN_USDC_ADDRESS: felt252 =
    0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8; // mainnet
