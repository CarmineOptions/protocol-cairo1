
use starknet::ContractAddress;

type BlockNumber = felt252;
type OptionSide = felt252; // TODO: Make this an enum
type OptionType = felt252; // TODO: Make this an enum
type Maturity = felt252;
type LPTAddress = ContractAddress;
type Int = felt252;

type Math64x61_ = felt252; // legacy, for AMM trait definition
type Volatility = Math64x61_;
type Strike = Math64x61_;

// TODO: Rename Option_ (note the trailing underscore) to sth more sensible
#[derive(Copy, Drop, Serde, storage_access::StorageAccess)]
struct Option_ {
    option_side: OptionSide,
    maturity: Maturity,
    strike_price: Strike,
    quote_token_address: ContractAddress,
    base_token_address: ContractAddress,
    option_type: OptionType
}

#[derive(Copy, Drop, Serde, storage_access::StorageAccess)]
struct Pool {
    quote_token_address: ContractAddress,
    base_token_address: ContractAddress,
    option_type: OptionType,
}

struct OptionWithPremia {
    option: Option_,
    premia: Math64x61_,
}
