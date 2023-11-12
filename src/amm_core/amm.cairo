#[starknet::contract]
mod AMM {
    use starknet::ContractAddress;

    use cubit::f128::types::fixed::{Fixed, FixedTrait};
    use carmine_protocol::types::basic::{
        Math64x61_, LegacyVolatility, LegacyStrike, Volatility, Strike, LPTAddress, OptionSide,
        Timestamp, OptionType, Maturity, Int
    };

    use carmine_protocol::oz::security::reentrancyguard::ReentrancyGuardComponent;
    use carmine_protocol::types::pool::Pool;
    use carmine_protocol::types::option_::{LegacyOption, Option_};
    use carmine_protocol::amm_core::amm_interface::IAMM;

    

    // Reentrancy Component
    component!(path: ReentrancyGuardComponent, storage: re_guard, event: ReentrancyGuardEvent);
    impl ReentrancyGuardInternalImpl = ReentrancyGuardComponent::InternalImpl<ContractState>;

    // TODO: Constructor

    #[storage]
    struct Storage {
        #[substorage(v0)]
        re_guard: ReentrancyGuardComponent::Storage,
        // Storage vars with new types

        pool_volatility_adjustment_speed: LegacyMap<LPTAddress, Math64x61_>,
        new_pool_volatility_adjustment_speed: LegacyMap<LPTAddress, Fixed>,
        pool_volatility_separate: LegacyMap::<
            (LPTAddress, Maturity, LegacyStrike), LegacyVolatility
        >,
        option_volatility: LegacyMap::<
            (ContractAddress, u64, u128), Volatility
        >, // This is actually options vol, not pools // TODO: last key value should be Fixed, not u128(or it's mag)
        option_position_: LegacyMap<(LPTAddress, OptionSide, Maturity, LegacyStrike), felt252>,
        new_option_position: LegacyMap<
            (LPTAddress, OptionSide, Timestamp, u128), Int
        >, // TODO: last key value should be Fixed, not u128(or it's mag)
        option_token_address: LegacyMap::<
            (LPTAddress, OptionSide, Maturity, LegacyStrike), ContractAddress
        >,
        new_option_token_address: LegacyMap::<
            (LPTAddress, OptionSide, Timestamp, u128), ContractAddress
        >, // TODO: last key value should be Fixed, not u128(or it's mag)
        available_options: LegacyMap::<(LPTAddress, felt252), LegacyOption>,
        new_available_options: LegacyMap::<(LPTAddress, u32), Option_>,
        new_available_options_usable_index: LegacyMap::<LPTAddress, u32>,
        // Storage vars that are basically the same

        underlying_token_address: LegacyMap<LPTAddress, ContractAddress>,
        max_lpool_balance: LegacyMap::<LPTAddress, u256>,
        pool_locked_capital_: LegacyMap<LPTAddress, u256>,
        lpool_balance_: LegacyMap<LPTAddress, u256>,
        max_option_size_percent_of_voladjspd: Int, // TODO: This was felt252 in old amm
        trading_halted: bool, // Make this bool if they can be interchanged
        available_lptoken_adresses: LegacyMap<felt252, LPTAddress>,
        // (quote_token_addr, base_token_address, option_type) -> LpToken address
        lptoken_addr_for_given_pooled_token: LegacyMap::<
            (ContractAddress, ContractAddress, OptionType), LPTAddress
        >,
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
        // #[flat]
        ReentrancyGuardEvent: ReentrancyGuardComponent::Event,
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
    use carmine_protocol::amm_core::periferies::view::View;
    use carmine_protocol::amm_core::pricing::option_pricing::OptionPricing;
    use carmine_protocol::amm_core::oracles::agg::OracleAgg;
    use carmine_protocol::amm_core::oracles::pragma::Pragma;

    use carmine_protocol::amm_core::oracles::pragma::PragmaUtils::{
        PragmaPricesResponse, Checkpoint
    };

    use carmine_protocol::types::option_::{OptionWithPremia, OptionWithUsersPosition};
    use carmine_protocol::types::pool::{PoolInfo, UserPoolInfo};
    use starknet::ClassHash;

    use carmine_protocol::utils::assert_admin_only; 

    #[external(v0)]
    impl Amm of IAMM<ContractState> {
        fn trade_open(
            ref self: ContractState,
            option_type: OptionType,
            strike_price: Fixed,
            maturity: u64,
            option_side: OptionSide,
            option_size: u128,
            quote_token_address: ContractAddress,
            base_token_address: ContractAddress,
            limit_total_premia: Fixed,
            tx_deadline: u64,
        ) -> Fixed {
            self.re_guard.start();

            let premia = Trading::trade_open(
                option_type,
                strike_price,
                maturity,
                option_side,
                option_size,
                quote_token_address,
                base_token_address,
                limit_total_premia,
                tx_deadline,
            );

            self.re_guard.end();

            premia
        }

        fn trade_close(
            ref self: ContractState,
            option_type: OptionType,
            strike_price: Fixed,
            maturity: u64,
            option_side: OptionSide,
            option_size: u128,
            quote_token_address: ContractAddress,
            base_token_address: ContractAddress,
            limit_total_premia: Fixed,
            tx_deadline: u64,
        ) -> Fixed {
            self.re_guard.start();

            let premia = Trading::trade_close(
                option_type,
                strike_price,
                maturity,
                option_side,
                option_size,
                quote_token_address,
                base_token_address,
                limit_total_premia,
                tx_deadline,
            );

            self.re_guard.end();
            premia
        }

        fn trade_settle(
            ref self: ContractState,
            option_type: OptionType,
            strike_price: Fixed,
            maturity: u64,
            option_side: OptionSide,
            option_size: u128,
            quote_token_address: ContractAddress,
            base_token_address: ContractAddress,
        ) {
            self.re_guard.start();
            Trading::trade_settle(
                option_type,
                strike_price,
                maturity,
                option_side,
                option_size,
                quote_token_address,
                base_token_address,
            );
            self.re_guard.end();
        }

        fn is_option_available(
            self: @ContractState,
            lptoken_address: ContractAddress,
            option_side: OptionSide,
            strike_price: Fixed,
            maturity: u64,
        ) -> bool {
            State::is_option_available(lptoken_address, option_side, strike_price, maturity,)
        }

        fn set_trading_halt(ref self: ContractState, new_status: bool) {
            assert_admin_only();
            State::set_trading_halt(new_status)
        }

        fn get_trading_halt(self: @ContractState) -> bool {
            State::get_trading_halt()
        }

        fn add_lptoken(
            ref self: ContractState,
            quote_token_address: ContractAddress,
            base_token_address: ContractAddress,
            option_type: OptionType,
            lptoken_address: ContractAddress,
            pooled_token_addr: ContractAddress,
            volatility_adjustment_speed: Fixed,
            max_lpool_bal: u256,
        ) {
            assert_admin_only();
            LiquidityPool::add_lptoken(
                quote_token_address,
                base_token_address,
                option_type,
                lptoken_address,
                pooled_token_addr,
                volatility_adjustment_speed,
                max_lpool_bal,
            )
        }

        fn add_option(
            ref self: ContractState,
            option_side: OptionSide,
            maturity: u64,
            strike_price: Fixed,
            quote_token_address: ContractAddress,
            base_token_address: ContractAddress,
            option_type: OptionType,
            lptoken_address: ContractAddress,
            option_token_address_: ContractAddress,
            initial_volatility: Fixed,
        ) {
            assert_admin_only();
            Options::add_option(
                option_side,
                maturity,
                strike_price,
                quote_token_address,
                base_token_address,
                option_type,
                lptoken_address,
                option_token_address_,
                initial_volatility,
            )
        }
        fn add_option_both_sides(
            ref self: ContractState,
            maturity: u64,
            strike_price: Fixed,
            quote_token_address: ContractAddress,
            base_token_address: ContractAddress,
            option_type: OptionType,
            lptoken_address: ContractAddress,
            option_token_address_long: ContractAddress,
            option_token_address_short: ContractAddress,
            initial_volatility: Fixed,
        ) {
            assert_admin_only();
            Options::add_option_both_sides(
                maturity,
                strike_price,
                quote_token_address,
                base_token_address,
                option_type,
                lptoken_address,
                option_token_address_long,
                option_token_address_short,
                initial_volatility,
            )
        }

        fn get_option_token_address(
            self: @ContractState,
            lptoken_address: ContractAddress,
            option_side: OptionSide,
            maturity: u64,
            strike_price: Fixed,
        ) -> ContractAddress {
            State::get_option_token_address(lptoken_address, option_side, maturity, strike_price,)
        }

        fn get_lptokens_for_underlying(
            self: @ContractState, pooled_token_addr: ContractAddress, underlying_amt: u256,
        ) -> u256 {
            LiquidityPool::get_lptokens_for_underlying(pooled_token_addr, underlying_amt)
        }

        fn get_underlying_for_lptokens(
            self: @ContractState, lptoken_addr: ContractAddress, lpt_amt: u256
        ) -> u256 {
            LiquidityPool::get_underlying_for_lptokens(lptoken_addr, lpt_amt)
        }


        fn get_available_lptoken_addresses(
            self: @ContractState, order_i: felt252
        ) -> ContractAddress {
            State::get_available_lptoken_addresses(order_i)
        }


        fn get_value_of_pool_expired_position(
            self: @ContractState, lptoken_address: LPTAddress
        ) -> Fixed {
            LiquidityPool::get_value_of_pool_expired_position(lptoken_address)
        }

        fn get_value_of_pool_non_expired_position(
            self: @ContractState, lptoken_address: LPTAddress
        ) -> Fixed {
            LiquidityPool::get_value_of_pool_non_expired_position(lptoken_address)
        }
        fn get_value_of_pool_position(
            self: @ContractState, lptoken_address: ContractAddress
        ) -> Fixed {
            LiquidityPool::get_value_of_pool_position(lptoken_address)
        }

        fn get_value_of_position(
            self: @ContractState,
            option: Option_,
            position_size: u128,
            option_type: OptionType,
            current_volatility: Fixed,
        ) -> Fixed {
            LiquidityPool::get_value_of_position(option, position_size,)
        }

        fn deposit_liquidity(
            ref self: ContractState,
            pooled_token_addr: ContractAddress,
            quote_token_address: ContractAddress,
            base_token_address: ContractAddress,
            option_type: OptionType,
            amount: u256,
        ) {
            self.re_guard.start();

            LiquidityPool::deposit_liquidity(
                pooled_token_addr, quote_token_address, base_token_address, option_type, amount,
            );

            self.re_guard.end();
        }

        fn withdraw_liquidity(
            ref self: ContractState,
            pooled_token_addr: ContractAddress,
            quote_token_address: ContractAddress,
            base_token_address: ContractAddress,
            option_type: OptionType,
            lp_token_amount: u256,
        ) {
            self.re_guard.start();

            LiquidityPool::withdraw_liquidity(
                pooled_token_addr,
                quote_token_address,
                base_token_address,
                option_type,
                lp_token_amount,
            );

            self.re_guard.end();
        }

        fn get_unlocked_capital(self: @ContractState, lptoken_address: ContractAddress) -> u256 {
            State::get_unlocked_capital(lptoken_address)
        }

        fn expire_option_token_for_pool(
            ref self: ContractState,
            lptoken_address: ContractAddress,
            option_side: OptionSide,
            strike_price: Fixed,
            maturity: u64,
        ) {
            self.re_guard.start();

            LiquidityPool::expire_option_token_for_pool(
                lptoken_address, option_side, strike_price, maturity,
            );

            self.re_guard.end();
        }

        fn set_max_option_size_percent_of_voladjspd(
            ref self: ContractState, max_opt_size_as_perc_of_vol_adjspd: u128
        ) {
            assert_admin_only();
            State::set_max_option_size_percent_of_voladjspd(max_opt_size_as_perc_of_vol_adjspd)
        }

        fn get_max_option_size_percent_of_voladjspd(self: @ContractState) -> u128 {
            State::get_max_option_size_percent_of_voladjspd()
        }

        fn get_lpool_balance(self: @ContractState, lptoken_address: ContractAddress) -> u256 {
            State::get_lpool_balance(lptoken_address)
        }

        fn get_max_lpool_balance(self: @ContractState, lpt_addr: ContractAddress) -> u256 {
            State::get_max_lpool_balance(lpt_addr)
        }

        fn set_max_lpool_balance(
            ref self: ContractState, lpt_addr: ContractAddress, max_lpool_bal: u256
        ) {
            assert_admin_only();
            State::set_max_lpool_balance(lpt_addr, max_lpool_bal)
        }

        fn get_pool_locked_capital(self: @ContractState, lptoken_address: ContractAddress) -> u256 {
            State::get_pool_locked_capital(lptoken_address)
        }

        fn get_available_options(
            self: @ContractState, lptoken_address: ContractAddress, order_i: u32
        ) -> Option_ {
            State::get_available_options(lptoken_address, order_i)
        }

        fn get_lptoken_address_for_given_option(
            self: @ContractState,
            quote_token_address: ContractAddress,
            base_token_address: ContractAddress,
            option_type: OptionType,
        ) -> ContractAddress {
            State::get_lptoken_address_for_given_option(
                quote_token_address, base_token_address, option_type,
            )
        }

        fn get_pool_definition_from_lptoken_address(
            self: @ContractState, lptoken_addres: ContractAddress
        ) -> Pool {
            State::get_pool_definition_from_lptoken_address(lptoken_addres)
        }


        fn get_option_volatility(
            self: @ContractState,
            lptoken_address: ContractAddress,
            maturity: u64,
            strike_price: Fixed,
        ) -> Fixed {
            State::get_option_volatility(lptoken_address, maturity, strike_price,)
        }

        fn get_underlying_token_address(
            self: @ContractState, lptoken_address: ContractAddress
        ) -> ContractAddress {
            State::get_underlying_token_address(lptoken_address)
        }

        fn get_available_lptoken_addresses_usable_index(
            self: @ContractState, starting_index: felt252
        ) -> felt252 {
            State::get_available_lptoken_addresses_usable_index(starting_index)
        }

        fn get_pool_volatility_adjustment_speed(
            self: @ContractState, lptoken_address: ContractAddress
        ) -> Fixed {
            State::get_pool_volatility_adjustment_speed(lptoken_address)
        }

        fn set_pool_volatility_adjustment_speed(
            ref self: ContractState, lptoken_address: ContractAddress, new_speed: Fixed
        ) {
            State::set_pool_volatility_adjustment_speed(lptoken_address, new_speed);
        }

        fn get_option_position(
            self: @ContractState,
            lptoken_address: ContractAddress,
            option_side: OptionSide,
            maturity: u64,
            strike_price: Fixed
        ) -> u128 {
            State::get_option_position(lptoken_address, option_side, maturity, strike_price)
        }

        fn black_scholes(
            self: @ContractState,
            sigma: Fixed,
            time_till_maturity_annualized: Fixed,
            strike_price: Fixed,
            underlying_price: Fixed,
            risk_free_rate_annualized: Fixed,
            is_for_trade: bool, // bool
        ) -> (Fixed, Fixed, bool) {
            OptionPricing::black_scholes(
                sigma,
                time_till_maturity_annualized,
                strike_price,
                underlying_price,
                risk_free_rate_annualized,
                is_for_trade
            )
        }
        fn get_current_price(
            self: @ContractState,
            quote_token_address: ContractAddress,
            base_token_address: ContractAddress
        ) -> Fixed {
            OracleAgg::get_current_price(quote_token_address, base_token_address)
        }

        fn get_terminal_price(
            self: @ContractState,
            quote_token_address: ContractAddress,
            base_token_address: ContractAddress,
            maturity: u64
        ) -> Fixed {
            OracleAgg::get_terminal_price(quote_token_address, base_token_address, maturity)
        }

        // TODO: This function is like this only for internal testing!!!!
        fn upgrade(ref self: ContractState, new_implementation: ClassHash) {
            assert(!new_implementation.is_zero(), 'Class hash cannot be zero');
            starknet::replace_class_syscall(new_implementation).unwrap();
        }

        fn set_pragma_checkpoint(ref self: ContractState, key: felt252) {
            Pragma::set_pragma_checkpoint(key)
        }

        fn set_pragma_required_checkpoints(ref self: ContractState) {
            Pragma::set_pragma_required_checkpoints()
        }

        // Peripheries not intended for audit

        fn get_all_options(
            self: @ContractState, lptoken_address: ContractAddress
        ) -> Array<Option_> {
            View::get_all_options(lptoken_address)
        }

        fn get_all_non_expired_options_with_premia(
            self: @ContractState, lptoken_address: ContractAddress
        ) -> Array<OptionWithPremia> {
            View::get_all_non_expired_options_with_premia(lptoken_address)
        }

        fn get_option_with_position_of_user(
            self: @ContractState, user_address: ContractAddress
        ) -> Array<OptionWithUsersPosition> {
            View::get_option_with_position_of_user(user_address)
        }

        fn get_all_lptoken_addresses(self: @ContractState,) -> Array<ContractAddress> {
            View::get_all_lptoken_addresses()
        }

        fn get_all_poolinfo(self: @ContractState) -> Array<PoolInfo> {
            View::get_all_poolinfo()
        }

        fn get_user_pool_infos(self: @ContractState, user: ContractAddress) -> Array<UserPoolInfo> {
            View::get_user_pool_infos(user)
        }

        fn get_total_premia(
            self: @ContractState, option: Option_, position_size: u256, is_closing: bool
        ) -> (Fixed, Fixed) {
            View::get_total_premia(option, position_size, is_closing)
        }
        
    }
}
