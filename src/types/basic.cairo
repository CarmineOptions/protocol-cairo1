
use cubit::f128::types::fixed::{Fixed, FixedTrait};
use starknet::ContractAddress;
use core::option::OptionTrait;

type LPTAddress = ContractAddress;
type OptionSide = u8; // TODO: Make this an enum
type OptionType = u8; // TODO: Make this an enum
type Timestamp = u64; // In seconds, Block timestamps are also u64

type Int = u128;

type Math64x61_ = felt252; // legacy, for AMM trait definition
type LegacyVolatility = Math64x61_;
type LegacyStrike = Math64x61_;
type Maturity = felt252; 

type Volatility = Fixed;
type Strike = Fixed;

// #[derive(Copy, Drop, Serde, Store)]
// struct LegacyOption {
//     option_side: OptionSide,
//     maturity: felt252,
//     strike_price: LegacyStrike,
//     quote_token_address: ContractAddress,
//     base_token_address: ContractAddress,
//     option_type: OptionType
// }

// TODO: Rename Option_ (note the trailing underscore) to sth more sensible
// TODO: Add lptoken addr to option (will be added in migrate function)
// #[derive(Copy, Drop, Serde, Store)]
// struct Option_ {
//     option_side: OptionSide,
//     maturity: Timestamp,
//     strike_price: Fixed,
//     quote_token_address: ContractAddress,
//     base_token_address: ContractAddress,
//     option_type: OptionType
// }

// trait Option_Trait {
//     fn sum(self: Option_) -> felt252;
// }

// impl Option_Impl of Option_Trait {
//     fn sum(self: Option_) -> felt252 {
//         self.maturity + self.strike_price.mag.into()
//     }
// }



#[derive(Copy, Drop, Serde, Store)]
struct Pool {
    quote_token_address: ContractAddress,
    base_token_address: ContractAddress,
    option_type: OptionType,
}
