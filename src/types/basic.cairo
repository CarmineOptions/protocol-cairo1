use carmine_protocol::amm_core::helpers::{legacyMath_to_cubit, cubit_to_legacyMath};

use cubit::f128::types::fixed::{Fixed, FixedTrait};
use starknet::ContractAddress;
use core::traits::{TryInto, Into};
use core::option::OptionTrait;

type BlockNumber = felt252;
type OptionSide = felt252; // TODO: Make this an enum
type OptionType = felt252; // TODO: Make this an enum
type Maturity = felt252;
type LPTAddress = ContractAddress;
type Int = felt252;

type Math64x61_ = felt252; // legacy, for AMM trait definition
type LegacyVolatility = Math64x61_;
type LegacyStrike = Math64x61_;

type Volatility = Fixed;
type Strike = Fixed;

#[derive(Copy, Drop, Serde, Store)]
struct LegacyOption {
    option_side: OptionSide,
    maturity: Maturity,
    strike_price: LegacyStrike,
    quote_token_address: ContractAddress,
    base_token_address: ContractAddress,
    option_type: OptionType
}

struct LegacyOptionWithPremia {
    option: LegacyOption,
    premia: Math64x61_,
}

// TODO: Rename Option_ (note the trailing underscore) to sth more sensible
// TODO: Add lptoken addr to option (will be added in migrate function)
#[derive(Copy, Drop, Serde, Store)]
struct Option_ {
    option_side: OptionSide,
    maturity: Maturity,
    strike_price: Fixed,
    quote_token_address: ContractAddress,
    base_token_address: ContractAddress,
    option_type: OptionType
}

// trait Option_Trait {
//     fn sum(self: Option_) -> felt252;
// }

// impl Option_Impl of Option_Trait {
//     fn sum(self: Option_) -> felt252 {
//         self.maturity + self.strike_price.mag.into()
//     }
// }

fn Option_to_LegacyOption(opt: Option_) -> LegacyOption {
    LegacyOption {
        option_side: opt.option_side,
        maturity: opt.maturity,
        strike_price: cubit_to_legacyMath(opt.strike_price),
        quote_token_address: opt.quote_token_address,
        base_token_address: opt.base_token_address,
        option_type: opt.option_type
    }
}

fn LegacyOption_to_Option(opt: LegacyOption) -> Option_ {
    Option_ {
        option_side: opt.option_side,
        maturity: opt.maturity,
        strike_price: legacyMath_to_cubit(opt.strike_price),
        quote_token_address: opt.quote_token_address,
        base_token_address: opt.base_token_address,
        option_type: opt.option_type
    }
}


#[derive(Copy, Drop, Serde, Store)]
struct Pool {
    quote_token_address: ContractAddress,
    base_token_address: ContractAddress,
    option_type: OptionType,
}
