// Module responsible for interactions with the AMM

use option::OptionTrait;
use traits::TryInto;
use array::ArrayTrait;
use traits::Into;

use starknet::{ContractAddress, get_block_timestamp};

use carmine_protocol::ilhedge::constants::{TOKEN_ETH_ADDRESS, TOKEN_USDC_ADDRESS};
use carmine_protocol::ilhedge::helpers::FixedHelpersTrait;
use carmine_protocol::types::option_::Option_;
use carmine_protocol::amm_core::amm::{AMM, IAMMDispatcher, IAMMDispatcherTrait};

use cubit::f128::types::fixed::{Fixed, FixedTrait};


fn buy_option(strike: Fixed, notional: u128, expiry: u64, calls: bool, amm_address: ContractAddress, quote_token_addr: ContractAddress, base_token_addr: ContractAddress,) {
    let optiontype = if (calls) {
        0
    } else {
        1
    };
    let amm = IAMMDispatcher { contract_address: amm_address };
    amm.trade_open(
        optiontype,
        strike,
        expiry,
        0,
        notional,
        quote_token_addr,
        base_token_addr,
        (FixedTrait::from_unscaled_felt((notional / 5).into())/FixedTrait::from_felt(1000000000000000000)),
        99999999999
    );
}

use debug::PrintTrait;

fn price_option(strike: Fixed, notional: u128, expiry: u64, calls: bool, amm_address: ContractAddress, quote_token_addr: ContractAddress, base_token_addr: ContractAddress) -> u128 {
    let optiontype = if (calls) {
        0
    } else {
        1
    };
    let lpt_addr_felt: felt252 = if (calls) { // testnet
        0x03b176f8e5b4c9227b660e49e97f2d9d1756f96e5878420ad4accd301dd0cc17
    } else {
        0x30fe5d12635ed696483a824eca301392b3f529e06133b42784750503a24972
    };
    'pricing option, maturity:'.print();
    expiry.print();
    'notional:'.print();
    notional.print();
    'strike:'.print();
    strike.print();
    'calls:'.print();
    calls.print();
    let option = Option_ {
        option_side: 0,
        maturity: expiry.into(),
        strike_price: strike,
        quote_token_address: quote_token_addr,
        base_token_address: base_token_addr, // testnet
        option_type: optiontype
    };
    let (before_fees, after_fees) = IAMMDispatcher {
        contract_address: amm_address
    }
        .get_total_premia(option, notional.into(), false);
    'call to get_total_premia fin'.print();
    after_fees.try_into().unwrap()
}

fn available_strikes(
    expiry: u64, quote_token_addr: ContractAddress, base_token_addr: ContractAddress, calls: bool
) -> Array<Fixed> {
    // TODO implement
    if (calls) {
        let mut res = ArrayTrait::<Fixed>::new();
        res.append(FixedTrait::from_unscaled_felt(1700));
        res.append(FixedTrait::from_unscaled_felt(1800));
        res.append(FixedTrait::from_unscaled_felt(1900));
        res.append(FixedTrait::from_unscaled_felt(2000));
        res
    } else {
        let mut res = ArrayTrait::<Fixed>::new();
        res.append(FixedTrait::from_unscaled_felt(1300));
        res.append(FixedTrait::from_unscaled_felt(1400));
        res.append(FixedTrait::from_unscaled_felt(1500));
        res.append(FixedTrait::from_unscaled_felt(1600));
        res
    }
}

type LegacyStrike = Math64x61_;
type Math64x61_ = felt252; // legacy, for AMM trait definition
type OptionSide = felt252;
type OptionType = felt252;
