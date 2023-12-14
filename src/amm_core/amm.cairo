#[starknet::contract]
mod AMM {
    use starknet::get_block_info;
    use starknet::ContractAddress;
    use starknet::get_caller_address;

    use cubit::f128::types::fixed::{Fixed, FixedTrait};
    use carmine_protocol::types::basic::{
        Volatility, Strike, LPTAddress, OptionSide, Timestamp, OptionType, Maturity, Int
    };

    use carmine_protocol::oz::security::reentrancyguard::ReentrancyGuardComponent;
    use carmine_protocol::oz::access::ownable::OwnableComponent;
    use carmine_protocol::types::pool::Pool;
    use carmine_protocol::types::option_::Option_;
    use carmine_protocol::amm_interface::IAMM;


    // Reentrancy Component
    component!(path: ReentrancyGuardComponent, storage: re_guard, event: ReentrancyGuardEvent);
    impl ReentrancyGuardInternalImpl = ReentrancyGuardComponent::InternalImpl<ContractState>;

    // Ownable component
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableCamelOnlyImpl =
        OwnableComponent::OwnableCamelOnlyImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        re_guard: ReentrancyGuardComponent::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        // Storage used for preventing sandwich attacks within single block
        sandwich_storage: LegacyMap<ContractAddress, u64>,
        new_pool_volatility_adjustment_speed: LegacyMap<LPTAddress, Fixed>,
        option_volatility: LegacyMap::<(ContractAddress, u64, u128), Volatility>,
        new_option_position: LegacyMap<(LPTAddress, OptionSide, Timestamp, u128), Int>,
        new_option_token_address: LegacyMap::<
            (LPTAddress, OptionSide, Timestamp, u128), ContractAddress
        >,
        new_available_options: LegacyMap::<(LPTAddress, u32), Option_>,
        new_available_options_usable_index: LegacyMap::<LPTAddress, u32>,
        underlying_token_address: LegacyMap<LPTAddress, ContractAddress>,
        max_lpool_balance: LegacyMap::<LPTAddress, u256>,
        pool_locked_capital_: LegacyMap<LPTAddress, u256>,
        lpool_balance_: LegacyMap<LPTAddress, u256>,
        max_option_size_percent_of_voladjspd: felt252,
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
        // #[flat]
        OwnableEvent: OwnableComponent::Event,
        TradeOpen: TradeOpen,
        TradeClose: TradeClose,
        TradeSettle: TradeSettle,
        DepositLiquidity: DepositLiquidity,
        WithdrawLiquidity: WithdrawLiquidity,
        ExpireOptionTokenForPool: ExpireOptionTokenForPool
    }


    // @notice Checks whether user has not deposited/withdrawed in the same block
    // @param user_addr: User address
    fn SandwichGuard() {
        // Get caller's address
        let user_addr = get_caller_address();

        // Get current block number
        let curr_block = get_block_info().unbox().block_number;

        // Read block number of the last user interaction
        let mut state: ContractState = unsafe_new_contract_state();
        let user_last_interaction = state.sandwich_storage.read(user_addr);

        // Assert that the values above are not the same
        assert(curr_block != user_last_interaction, 'Cant deposit/withdraw');

        // Write block number of the last user interaction
        state.sandwich_storage.write(user_addr, curr_block);
    }

    use carmine_protocol::amm_core::trading::Trading;
    use carmine_protocol::amm_core::state::State;
    use carmine_protocol::amm_core::liquidity_pool::LiquidityPool;
    use carmine_protocol::amm_core::options::Options;
    use carmine_protocol::amm_core::peripheries::view::View;
    use carmine_protocol::amm_core::pricing::option_pricing::OptionPricing;
    use carmine_protocol::amm_core::oracles::agg::OracleAgg;
    use carmine_protocol::amm_core::oracles::pragma::Pragma;

    use carmine_protocol::amm_core::oracles::pragma::PragmaUtils::{
        PragmaPricesResponse, Checkpoint
    };

    use carmine_protocol::types::option_::{OptionWithPremia, OptionWithUsersPosition};
    use carmine_protocol::types::pool::{PoolInfo, UserPoolInfo};
    use starknet::ClassHash;

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress,) {
        self.ownable.initializer(owner);
    }

    fn can_halt_trading() -> bool {
        let caller = get_caller_address();
        let mut state: ContractState = unsafe_new_contract_state();

        if caller == state.ownable.owner() {
            true // Governance
        } else if caller == 0x0583a9d956d65628f806386ab5b12dccd74236a3c6b930ded9cf3c54efc722a1
            .try_into()
            .unwrap() {
            true // Ondra
        } else if caller == 0x06717eaf502baac2b6b2c6ee3ac39b34a52e726a73905ed586e757158270a0af
            .try_into()
            .unwrap() {
            true // Andrej
        } else if caller == 0x0011d341c6e841426448ff39aa443a6dbb428914e05ba2259463c18308b86233
            .try_into()
            .unwrap() {
            true // Marek
        } else if caller == 0x03d1525605db970fa1724693404f5f64cba8af82ec4aab514e6ebd3dec4838ad
            .try_into()
            .unwrap() {
            true // Dave
        } else {
            false
        }
    }

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
            assert(can_halt_trading(), 'Cant set trading halt status');

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
            self.ownable.assert_only_owner();

            self.re_guard.start();
            LiquidityPool::add_lptoken(
                quote_token_address,
                base_token_address,
                option_type,
                lptoken_address,
                pooled_token_addr,
                volatility_adjustment_speed,
                max_lpool_bal,
            );
            self.re_guard.end();
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
            self.ownable.assert_only_owner();

            self.re_guard.start();
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
            );
            self.re_guard.end();
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
            self.ownable.assert_only_owner();

            self.re_guard.start();
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
            );
            self.re_guard.end();
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

            SandwichGuard();

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

            SandwichGuard();

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
            self.ownable.assert_only_owner();
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
            self.ownable.assert_only_owner();
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
            self.ownable.assert_only_owner();
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

        fn upgrade(ref self: ContractState, new_implementation: ClassHash) {
            self.ownable.assert_only_owner();
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
