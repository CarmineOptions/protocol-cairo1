#[starknet::contract]
mod AMM {
    use starknet::ContractAddress;

    use cubit::f128::types::fixed::{Fixed, FixedTrait};

    use carmine_protocol::types::basic::{
        Math64x61_, LegacyVolatility, LegacyStrike, Volatility, Strike, LPTAddress, OptionSide, Timestamp
    };

    use carmine_protocol::types::pool::Pool;

    use carmine_protocol::types::option_::{LegacyOption, Option_};

    #[storage]
    struct Storage {
        // Storage vars with new types
        underlying_token_address: LegacyMap<LPTAddress, ContractAddress>,
        pool_volatility_adjustment_speed: LegacyMap<LPTAddress, Math64x61_>,
        new_pool_volatility_adjustment_speed: LegacyMap<LPTAddress, Fixed>,
        pool_volatility_separate: LegacyMap::<(LPTAddress, Maturity, LegacyStrike),
        LegacyVolatility>,
        option_volatility: LegacyMap::<(LPTAddress, Maturity, Strike),
        Volatility>, // This is actually options vol, not pools
        option_position_: LegacyMap<(LPTAddress, OptionSide, Maturity, LegacyStrike), felt252>,
        new_option_position: LegacyMap<(LPTAddress, OptionSide, Timestamp, Strike), Int>,
        option_token_address: LegacyMap::<(LPTAddress, OptionSide, Maturity, LegacyStrike),
        ContractAddress>,
        new_option_token_address: LegacyMap::<(LPTAddress, OptionSide, Timestamp, Strike),
        ContractAddress>,
        available_options: LegacyMap::<(LPTAddress, felt252), LegacyOption>,
        new_available_options: LegacyMap::<(LPTAddress, u32), Option_>,
        new_available_options_usable_index: u32,
        // Storage vars that are basically the same
        max_lpool_balance: LegacyMap::<ContractAddress, u256>,
        pool_locked_capital_: LegacyMap<LPTAddress, u256>,
        lpool_balance_: LegacyMap<LPTAddress, u256>,
        max_option_size_percent_of_voladjspd: Int, // TODO: This was felt252 in old amm
        trading_halted: u8, // Make this bool if they can be interchanged
        available_lptoken_adresses: LegacyMap<felt252, LPTAddress>,
        // (quote_token_addr, base_token_address, option_type) -> LpToken address
        lptoken_addr_for_given_pooled_token: LegacyMap::<(
            ContractAddress, ContractAddress, OptionType
        ),
        LPTAddress>,
        pool_definition_from_lptoken_address: LegacyMap<LPTAddress, Pool>,
    // option_type -> deleting this one, it's not used in the amm and get_pool_definition can be used instead
    }
}
