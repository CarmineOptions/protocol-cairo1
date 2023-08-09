use starknet::ContractAddress;
use core::traits::{TryInto, Into};
use core::option::OptionTrait;

use carmine_protocol::amm_core::helpers::{legacyMath_to_cubit, cubit_to_legacyMath};
use cubit::f128::types::fixed::{Fixed, FixedTrait};

use carmine_protocol::types::basic::{
    OptionSide,
    OptionType,
    Timestamp,
    LegacyStrike
};


// Option used in c0 AMM
#[derive(Copy, Drop, Serde, Store)]
struct LegacyOption {
    option_side: OptionSide,
    maturity: felt252,
    strike_price: LegacyStrike,
    quote_token_address: ContractAddress,
    base_token_address: ContractAddress,
    option_type: OptionType
}

// New option
#[derive(Copy, Drop, Serde, Store)]
struct Option_ {
    option_side: OptionSide,
    maturity: Timestamp,
    strike_price: Fixed,
    quote_token_address: ContractAddress,
    base_token_address: ContractAddress,
    option_type: OptionType
}

trait Option_Trait {
    fn sum(self: @Option_) -> u128;
}

impl Option_Impl of Option_Trait {
    fn sum(self: @Option_) -> u128 {
        *self.strike_price.mag + (*self.maturity).into()
    }
}

fn Option_to_LegacyOption(opt: Option_) -> LegacyOption {
    LegacyOption {
        option_side: opt.option_side,
        maturity: opt.maturity.into(),
        strike_price: cubit_to_legacyMath(opt.strike_price),
        quote_token_address: opt.quote_token_address,
        base_token_address: opt.base_token_address,
        option_type: opt.option_type
    }
}

fn LegacyOption_to_Option(opt: LegacyOption) -> Option_ {
    Option_ {
        option_side: opt.option_side,
        maturity: opt.maturity.try_into().expect(''),
        strike_price: legacyMath_to_cubit(opt.strike_price),
        quote_token_address: opt.quote_token_address,
        base_token_address: opt.base_token_address,
        option_type: opt.option_type
    }
}