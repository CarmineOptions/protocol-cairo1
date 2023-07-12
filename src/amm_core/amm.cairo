

#[starknet::contract]
mod AMM {
    use starknet::ContractAddress;   

    use cubit::types::fixed::{Fixed, FixedTrait};

    use carmine_protocol::types::{
        LPTAddress,
        OptionSide,
        Maturity,
        Math64x61_,
        Volatility,
        Strike,
        Option_,
        Pool
    };

    #[storage]
    struct Storage {
        pool_volatility_separate: LegacyMap::<(LPTAddress, Maturity, Strike), Volatility>,
        pool_volatility_adjustment_speed: LegacyMap<LPTAddress, Math64x61_>,
        pool_definition_from_lptoken_address: LegacyMap<LPTAddress, Pool>,
        pool_locked_capital_: LegacyMap<lptoken_address, u256>,

        lpool_balance_: LegacyMap<LPTAddress, u256>,
        option_position_: LegacyMap<(LPTAddress, OptionSide, Maturity, Strike), Int>,

        option_token_address: LegacyMap::<(LPTAddress, OptionSide, Maturity, Strike), ContractAddress>,
        available_options: LegacyMap::<(LPTAddress, felt252), Option_>,
        max_option_size_percent_of_voladjspd: Int,
        underlying_token_address: LegacyMap::<LPTAddress, ContractAddress>,
    }


}