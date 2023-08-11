#[starknet::contract]
mod AMM {
    use starknet::ContractAddress;

    use cubit::f128::types::fixed::{Fixed, FixedTrait};

    use carmine_protocol::types::basic::{
        Math64x61_, LegacyVolatility, LegacyStrike, Volatility, Strike, LPTAddress, OptionSide,
        Timestamp
    };
    // use starknet::event::EventEmitter;
    use carmine_protocol::types::pool::Pool;

    use carmine_protocol::types::option_::{LegacyOption, Option_};

    #[storage]
    struct Storage {
        // Storage vars with new types

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
        underlying_token_address: LegacyMap<LPTAddress, ContractAddress>,
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

    fn emit_event<S, impl IntoImpl: traits::Into<S, Event>, impl DropImpl: traits::Drop<S>>(
        event: S
    ) {
        let mut state: ContractState = unsafe_new_contract_state();
        state.emit(event);
    }

    // Events
    #[derive(starknet::Event, Drop)]
    struct TradeOpen {
        caller: ContractAddress,
        option_token: ContractAddress,
        capital_transfered: u256,
        option_tokens_minted: u256,
    }


    #[derive(starknet::Event, Drop)]
    struct TradeClose {
        caller: ContractAddress,
        option_token: ContractAddress,
        capital_transfered: u256,
        option_tokens_burned: u256
    }

    #[derive(starknet::Event, Drop)]
    struct TradeSettle {
        caller: ContractAddress,
        option_token: ContractAddress,
        capital_transfered: u256,
        option_tokens_burned: u256
    }

    #[derive(starknet::Event, Drop)]
    struct DepositLiquidity {
        caller: ContractAddress,
        lp_token: ContractAddress,
        capital_transfered: u256,
        lp_tokens_minted: u256
    }

    #[derive(starknet::Event, Drop)]
    struct WithdrawLiquidity {
        caller: ContractAddress,
        lp_token: ContractAddress,
        capital_transfered: u256,
        lp_tokens_burned: u256
    }

    #[derive(starknet::Event, Drop)]
    struct ExpireOptionTokenForPool {
        lptoken_address: ContractAddress,
        option_side: u8,
        strike_price: Fixed,
        maturity: Timestamp,
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        TradeOpen: TradeOpen,
        TradeClose: TradeClose,
        TradeSettle: TradeSettle,
        DepositLiquidity: DepositLiquidity,
        WithdrawLiquidity: WithdrawLiquidity,
        ExpireOptionTokenForPool: ExpireOptionTokenForPool
    }
}
