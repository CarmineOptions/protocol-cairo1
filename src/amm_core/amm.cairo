use starknet::ContractAddress;
use carmine_protocol::types::basic::{OptionType, OptionSide};

use carmine_protocol::types::option_::{Option_, OptionWithPremia, OptionWithUsersPosition};
use carmine_protocol::types::pool::{PoolInfo, UserPoolInfo, Pool};
use cubit::f128::types::fixed::{Fixed, FixedTrait};

#[starknet::interface]
trait IAMM<TContractState> {
    fn deposit_liquidity(
        ref self: TContractState,
        pooled_token_addr: ContractAddress,
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        option_type: OptionType,
        amount: u256,
    );
    // fn get_option_type(self: @TContractState, lptoken_address: ContractAddress) -> OptionType; // Deleting this one - get_pool_def_from_lptoken_addr can be used
// fn empiric_median_price(self: @TContractState, key: felt252) -> Fixed;
// TODO: Functions below
// fn initializer(ref self: TContractState, proxy_admin: ContractAddress);
// fn upgrade(ref self: TContractState, new_implementation: felt252);
// fn setAdmin(ref self: TContractState, address: felt252);
// fn getImplementationHash(self: @TContractState, ) -> felt252;
}


#[starknet::contract]
mod AMM {
    use starknet::ContractAddress;

    use cubit::f128::types::fixed::{Fixed, FixedTrait};
    use carmine_protocol::types::basic::{
        Math64x61_, LegacyVolatility, LegacyStrike, Volatility, Strike, LPTAddress, OptionSide,
        Timestamp, OptionType, Maturity, Int
    };

    use carmine_protocol::types::pool::Pool;
    use carmine_protocol::types::option_::{LegacyOption, Option_};

    // TODO: Constructor

    #[storage]
    struct Storage {
        // Storage vars with new types

        pool_volatility_adjustment_speed: LegacyMap<LPTAddress, Math64x61_>,
        new_pool_volatility_adjustment_speed: LegacyMap<LPTAddress, Fixed>,
        pool_volatility_separate: LegacyMap::<(LPTAddress, Maturity, LegacyStrike),
        LegacyVolatility>,
        option_volatility: LegacyMap::<(ContractAddress, u64, u128),
        Volatility>, // This is actually options vol, not pools // TODO: last key value should be Fixed, not u128(or it's mag)
        option_position_: LegacyMap<(LPTAddress, OptionSide, Maturity, LegacyStrike), felt252>,
        new_option_position: LegacyMap<(LPTAddress, OptionSide, Timestamp, u128),
        Int>, // TODO: last key value should be Fixed, not u128(or it's mag)
        option_token_address: LegacyMap::<(LPTAddress, OptionSide, Maturity, LegacyStrike),
        ContractAddress>,
        new_option_token_address: LegacyMap::<(LPTAddress, OptionSide, Timestamp, u128),
        ContractAddress>, // TODO: last key value should be Fixed, not u128(or it's mag)
        available_options: LegacyMap::<(LPTAddress, felt252), LegacyOption>,
        new_available_options: LegacyMap::<(LPTAddress, u32), Option_>,
        new_available_options_usable_index: u32,
        // Storage vars that are basically the same

        underlying_token_address: LegacyMap<LPTAddress, ContractAddress>,
        max_lpool_balance: LegacyMap::<LPTAddress, u256>,
        pool_locked_capital_: LegacyMap<LPTAddress, u256>,
        lpool_balance_: LegacyMap<LPTAddress, u256>,
        max_option_size_percent_of_voladjspd: Int, // TODO: This was felt252 in old amm
        trading_halted: bool, // Make this bool if they can be interchanged
        available_lptoken_adresses: LegacyMap<felt252, LPTAddress>,
        // (quote_token_addr, base_token_address, option_type) -> LpToken address
        lptoken_addr_for_given_pooled_token: LegacyMap::<(
            ContractAddress, ContractAddress, OptionType
        ),
        LPTAddress>,
        pool_definition_from_lptoken_address: LegacyMap<LPTAddress, Pool>,
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


    use carmine_protocol::amm_core::trading::Trading;
    use carmine_protocol::amm_core::state::State;
    use carmine_protocol::amm_core::liquidity_pool::LiquidityPool;
    use carmine_protocol::amm_core::options::Options;
    use carmine_protocol::amm_core::view::View;
    use carmine_protocol::amm_core::pricing::option_pricing::OptionPricing;

    use carmine_protocol::types::option_::{OptionWithPremia, OptionWithUsersPosition};
    use carmine_protocol::types::pool::{PoolInfo, UserPoolInfo};

    #[external(v0)]
    impl Amm of super::IAMM<ContractState> {
        fn deposit_liquidity(
            ref self: ContractState,
            pooled_token_addr: ContractAddress,
            quote_token_address: ContractAddress,
            base_token_address: ContractAddress,
            option_type: OptionType,
            amount: u256,
        ) {
            LiquidityPool::deposit_liquidity(
                pooled_token_addr, quote_token_address, base_token_address, option_type, amount, 
            )
        }
    }
}
