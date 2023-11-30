mod Trading {
    use starknet::get_block_timestamp;
    use starknet::ContractAddress;
    use option::OptionTrait;
    use traits::TryInto;
    use traits::Into;

    use cubit::f128::types::fixed::Fixed;
    use cubit::f128::types::fixed::FixedTrait;

    use carmine_protocol::types::basic::Math64x61_;
    use carmine_protocol::types::basic::OptionType;
    use carmine_protocol::types::basic::OptionSide;
    use carmine_protocol::types::basic::LPTAddress;
    use carmine_protocol::types::basic::Int;
    use carmine_protocol::types::basic::Timestamp;

    use carmine_protocol::amm_core::helpers::fromU256_balance;
    use carmine_protocol::amm_core::helpers::toU256_balance;
    use carmine_protocol::amm_core::helpers::check_deadline;

    use carmine_protocol::amm_core::state::State::get_option_volatility;
    use carmine_protocol::amm_core::state::State::get_pool_volatility_adjustment_speed;
    use carmine_protocol::amm_core::state::State::set_option_volatility;
    use carmine_protocol::amm_core::state::State::get_trading_halt;
    use carmine_protocol::amm_core::state::State::is_option_available;
    use carmine_protocol::amm_core::state::State::get_lptoken_address_for_given_option;

    use carmine_protocol::amm_core::options::Options::mint_option_token;
    use carmine_protocol::amm_core::options::Options::burn_option_token;
    use carmine_protocol::amm_core::options::Options::expire_option_token;

    use carmine_protocol::amm_core::constants::RISK_FREE_RATE;
    use carmine_protocol::amm_core::constants::TRADE_SIDE_LONG;
    use carmine_protocol::amm_core::constants::TRADE_SIDE_SHORT;
    use carmine_protocol::amm_core::constants::get_opposite_side;
    use carmine_protocol::amm_core::constants::STOP_TRADING_BEFORE_MATURITY_SECONDS;

    use carmine_protocol::amm_core::pricing::option_pricing::OptionPricing::black_scholes;
    use carmine_protocol::amm_core::pricing::fees::get_fees;

    use carmine_protocol::amm_core::pricing::option_pricing_helpers::convert_amount_to_option_currency_from_base_uint256;
    use carmine_protocol::amm_core::pricing::option_pricing_helpers::get_new_volatility;
    use carmine_protocol::amm_core::pricing::option_pricing_helpers::get_time_till_maturity;
    use carmine_protocol::amm_core::pricing::option_pricing_helpers::select_and_adjust_premia;
    use carmine_protocol::amm_core::pricing::option_pricing_helpers::add_premia_fees;
    use carmine_protocol::amm_core::pricing::option_pricing_helpers::assert_option_type_exists;
    use carmine_protocol::amm_core::pricing::option_pricing_helpers::assert_option_side_exists;

    use carmine_protocol::amm_core::oracles::agg::OracleAgg::get_current_price;
    use carmine_protocol::amm_core::oracles::agg::OracleAgg::get_terminal_price;

    // @notice Executes option trade
    // @dev options_size is always denominated in the lowest possible unit of BASE tokens (ETH in case
    //      of ETH/USDC), e.g. wei in case of ETH.
    // @dev Option size of 1 ETH would be 10**18 since 1 ETH = 10**18 wei.
    // @param option_type: Type of the option 0 for Call, 1 for Put
    // @param strike_price: Option's strike price in terms of Fixed, ie strike 1500 is
    //      1500*2**64 = 27670116110564327424000 -> use FixedTrait::new(27670116110564327424000, false) as input value
    // @param maturity: Option's maturity as unix timestamp 
    // @param side: Side of the option 0 for Long, 1 for Short
    // @param option_size: Size to be traded denominated in the lowest possible unit of BASE tokens
    // @param quote_token_address: Address of the quote token (USDC in ETH/USDC)
    // @param base_token_address: Address of the base token (ETH in ETH/USDC)
    // @param lptoken_address: Address of the liquidity pool token
    // @param limit_total_premia: Limit for premia with fees, min when short and max when long
    // @return premia: Premia for one unit of underlying (not adjusted for size or fees) in terms of Fixed
    fn do_trade(
        option_type: OptionType,
        strike_price: Fixed,
        maturity: Timestamp,
        side: OptionSide,
        option_size: Int,
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        lptoken_address: LPTAddress,
        limit_total_premia: Fixed,
    ) -> Fixed {
        // Helper Values
        let option_size_cubit = fromU256_balance(option_size.into(), base_token_address);

        let option_size_in_pool_currency = convert_amount_to_option_currency_from_base_uint256(
            option_size.into(),
            option_type,
            toU256_balance(strike_price, quote_token_address),
            base_token_address
        );

        let hundred = FixedTrait::from_unscaled_felt(100);

        // 1) Get current volatility
        let current_volatility = get_option_volatility(lptoken_address, maturity, strike_price);

        // 2) get price of underlying asset
        let underlying_price = get_current_price(quote_token_address, base_token_address);

        // 3) Calculate new volatility, calculate trade volatility
        let pool_volatility_adjustment_speed = get_pool_volatility_adjustment_speed(
            lptoken_address
        );

        let (new_volatility, trade_volatility) = get_new_volatility(
            current_volatility,
            option_size_cubit,
            option_type,
            side,
            strike_price,
            pool_volatility_adjustment_speed
        );

        set_option_volatility(lptoken_address, maturity, strike_price, new_volatility);

        // 5) Get TTM
        let time_till_maturity = get_time_till_maturity(maturity);

        // 6) Risk free rate
        let risk_free_rate = FixedTrait::from_unscaled_felt(RISK_FREE_RATE);

        // 7) Get premia
        let sigma = trade_volatility / hundred;
        let (call_premia, put_premia, _) = black_scholes(
            sigma, time_till_maturity, strike_price, underlying_price, risk_free_rate, true
        );

        let premia = select_and_adjust_premia(
            call_premia, put_premia, option_type, underlying_price
        );
        let total_premia_before_fees = premia * option_size_cubit;

        // 8) Get fees
        let total_fees = get_fees(total_premia_before_fees);
        let total_premia = add_premia_fees(side, total_premia_before_fees, total_fees);

        // 9) Validate slippage
        if side == TRADE_SIDE_LONG {
            assert(total_premia <= limit_total_premia, 'Premia out of slippage bounds');
        } else {
            assert(total_premia >= limit_total_premia, 'Premia out of slippage bounds');
        }

        // 10) Make the trade
        mint_option_token(
            lptoken_address,
            option_size,
            option_size_in_pool_currency,
            side,
            option_type,
            maturity,
            strike_price,
            total_premia,
            underlying_price,
        );

        return premia;
    }

    // @notice Closes existing position or part of it
    // @dev options_size is always denominated in the lowest possible unit of base token - "wei" for ETH/USDC
    // @dev options_size of 1 ETH would be 10**18 since 1 ETH = 10**18 wei.
    // @param option_type: Type of the option 0 for Call, 1 for Put
    // @param strike_price: Option's strike price in terms of Fixed, ie strike 1500 is
    //      1500*2**64 = 27670116110564327424000 -> use FixedTrait::new(27670116110564327424000, false) as input value
    // @param maturity: Option's maturity as unix timestamp
    // @param side: Side of the option 0 for Long, 1 for Short
    // @param option_size: Size to be traded in base token lowest unit (ie 10**18 for size 1 of ETH/USDC)
    // @param quote_token_address: Address of the quote token (USDC in ETH/USDC)
    // @param base_token_address: Address of the base token (ETH in ETH/USDC)
    // @param lptoken_address: Address of the liquidity pool token
    // @param limit_total_premia: Limit for premia with fees, min when short and max when long
    // @return premia: Premia for one unit of underlying (not adjusted for size or fees) in terms of Fixed
    fn close_position(
        option_type: OptionType,
        strike_price: Fixed,
        maturity: Timestamp,
        side: OptionSide,
        option_size: Int,
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        lptoken_address: LPTAddress,
        limit_total_premia: Fixed,
    ) -> Fixed {
        let opposite_side = get_opposite_side(side);

        // Helper Values
        let opt_size_u256: u256 = option_size.into();
        let option_size_cubit = fromU256_balance(opt_size_u256, base_token_address);

        let option_size_in_pool_currency = convert_amount_to_option_currency_from_base_uint256(
            opt_size_u256,
            option_type,
            toU256_balance(strike_price, quote_token_address),
            base_token_address
        );

        let hundred = FixedTrait::from_unscaled_felt(100);

        // 1) Get current volatility
        let current_volatility = get_option_volatility(lptoken_address, maturity, strike_price);

        // 2) get price of underlying
        let underlying_price = get_current_price(quote_token_address, base_token_address);

        // 3) Calculate new volatility, calculate trade volatility
        let pool_volatility_adjustment_speed = get_pool_volatility_adjustment_speed(
            lptoken_address
        );

        let (new_volatility, trade_volatility) = get_new_volatility(
            current_volatility,
            option_size_cubit,
            option_type,
            opposite_side,
            strike_price,
            pool_volatility_adjustment_speed
        );

        // 4) Update volatility
        set_option_volatility(lptoken_address, maturity, strike_price, new_volatility);

        // 5) Get TTM
        let time_till_maturity = get_time_till_maturity(maturity);

        // 6) Risk free rate
        let risk_free_rate = FixedTrait::from_felt(RISK_FREE_RATE);

        // 7) Get premia
        let sigma = trade_volatility / hundred;

        let (call_premia, put_premia, _) = black_scholes(
            sigma, time_till_maturity, strike_price, underlying_price, risk_free_rate, true
        );

        let premia = select_and_adjust_premia(
            call_premia, put_premia, option_type, underlying_price
        );
        let total_premia_before_fees = premia * option_size_cubit;

        // 8) get fees 
        let total_fees = get_fees(total_premia_before_fees);
        let total_premia = add_premia_fees(opposite_side, total_premia_before_fees, total_fees);

        // 9) Validate slippage
        if opposite_side == TRADE_SIDE_LONG {
            assert(total_premia <= limit_total_premia, 'Premia out of slippage bounds');
        } else {
            assert(limit_total_premia <= total_premia, 'Premia out of slippage bounds');
        }

        burn_option_token(
            lptoken_address,
            option_size,
            option_size_in_pool_currency,
            side,
            option_type,
            maturity,
            strike_price,
            total_premia,
            underlying_price
        );

        return premia;
    }

    // @notice Validates trade inputs and fails if any input is not valid
    // @dev options_size is always denominated in the lowest possible unit of base token - "wei" for ETH/USDC
    // @dev options_size of 1 ETH would be 10**18 since 1 ETH = 10**18 wei.
    // @param option_type: Type of the option 0 for Call, 1 for Put
    // @param strike_price: Option's strike price in terms of Fixed, ie strike 1500 is
    //      1500*2**64 = 27670116110564327424000 -> use FixedTrait::new(27670116110564327424000, false) as input value
    // @param maturity: Option's maturity as unix timestamp
    // @param option_side: Side of the option 0 for Long, 1 for Short
    // @param option_size: Size to be traded denominated in the lowest possible unit of BASE tokens
    // @param quote_token_address: Address of the quote token (USDC in ETH/USDC)
    // @param base_token_address: Address of the base token (ETH in ETH/USDC)
    // @param lptoken_address: Address of the liquidity pool token
    // @param open_position: True if user wants to open position, false otherwise
    // @param limit_total_premia: Limit for premia with fees, min when short and max when long
    // @param tx_deadline: Fail the transaction if the current block timestamp is greater that the deadline
    fn validate_trade_input(
        option_type: OptionType,
        strike_price: Fixed,
        maturity: Timestamp,
        option_side: OptionSide,
        option_size: Int,
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        lptoken_address: ContractAddress,
        open_position: bool,
        limit_total_premia: Fixed,
        tx_deadline: Timestamp,
    ) {
        let halt_status = get_trading_halt();
        assert(halt_status, 'Trading halted');

        assert(option_size > 0_u128, 'VTI - opt size <= 0');
        assert_option_type_exists(option_type.into(), 'VTI - invalid option type');
        assert_option_side_exists(option_side.into(), 'VTI - invalid option side');

        let is_opt_available = is_option_available(
            lptoken_address, option_side, strike_price, maturity
        );
        assert(is_opt_available, 'VTI - opt unavailable');

        let current_block_time = get_block_timestamp();

        // Check that maturity hasn't matured in case of open_position=TRUE
        // If open_position=FALSE it means the user wants to close or settle the option
        if open_position {
            assert(current_block_time < maturity, 'VTI - opt already expired');
            assert(
                current_block_time < (maturity - STOP_TRADING_BEFORE_MATURITY_SECONDS),
                'VTI - Trading is stopped'
            );
        } else {
            let is_not_ripe = current_block_time <= maturity;
            let cannot_be_closed = (maturity
                - STOP_TRADING_BEFORE_MATURITY_SECONDS) <= current_block_time;

            let cannot_be_closed_or_settled = is_not_ripe & cannot_be_closed;

            assert(!cannot_be_closed_or_settled, 'VTI - No Closing/settling yet')
        }

        assert(limit_total_premia >= FixedTrait::from_felt(1), 'VTI - limit total premia <= 0');
        assert(tx_deadline >= 1, 'VTI - tx deadline <= 0');
    }

    // @notice External function for opening a position
    // @dev options_size is always denominated in the lowest possible unit of base token - "wei" for ETH/USDC
    // @dev options_size of 1 ETH would be 10**18 since 1 ETH = 10**18 wei
    // @param option_type: Type of the option 0 for Call, 1 for Put
    // @param strike_price: Option's strike price in terms of Fixed, ie strike 1500 is
    //      1500*2**64 = 27670116110564327424000 -> use FixedTrait::new(27670116110564327424000, false) as input value
    // @param maturity: Option's maturity as unix timestamp
    // @param option_side: Side of the option 0 for Long, 1 for Short
    // @param option_size: Size to be traded denominated in the lowest possible unit of BASE tokens
    // @param quote_token_address: Address of the quote token (USDC in ETH/USDC)
    // @param base_token_address: Address of the base token (ETH in ETH/USDC)
    // @param limit_total_premia: Limit for premia with fees, min when short and max when long
    // @param tx_deadline: Fail the transaction if the current block time is greater that the deadline
    // @return premia: Premia that was paid in terms of Fixed
    fn trade_open(
        option_type: OptionType,
        strike_price: Fixed,
        maturity: Timestamp,
        option_side: OptionSide,
        option_size: Int, // in base token currency
        quote_token_address: ContractAddress, // part of underlying_asset definition
        base_token_address: ContractAddress, // part of underlying_asset definition
        limit_total_premia: Fixed, // The limit price that user wants
        tx_deadline: Timestamp, // Timestamp deadline for the transaction to happen
    ) -> Fixed {
        let lptoken_address = get_lptoken_address_for_given_option(
            quote_token_address, base_token_address, option_type
        );
        validate_trade_input(
            option_type,
            strike_price,
            maturity,
            option_side,
            option_size,
            quote_token_address,
            base_token_address,
            lptoken_address,
            true,
            limit_total_premia,
            tx_deadline,
        );

        // Validate deadline
        check_deadline(tx_deadline);

        do_trade(
            option_type,
            strike_price,
            maturity,
            option_side,
            option_size,
            quote_token_address,
            base_token_address,
            lptoken_address,
            limit_total_premia,
        )
    }

    // @notice External function for closing a position
    // @dev options_size is always denominated in the lowest possible unit of base token - "wei" for ETH/USDC
    // @dev options_size of 1 ETH would be 10**18 since 1 ETH = 10**18 wei
    // @param option_type: Type of the option 0 for Call, 1 for Put
    // @param strike_price: Option's strike price in terms of Fixed, ie strike 1500 is
    //      1500*2**64 = 27670116110564327424000 -> use FixedTrait::new(27670116110564327424000, false) as input value
    // @param maturity: Option's maturity as unix timestamp
    // @param option_side: Side of the option 0 for Long, 1 for Short
    // @param option_size: Size to be traded denominated in the lowest possible unit of BASE tokens
    // @param quote_token_address: Address of the quote token (USDC in ETH/USDC)
    // @param base_token_address: Address of the base token (ETH in ETH/USDC)
    // @param limit_total_premia: Limit for premia with fees, min when short and max when long
    // @param tx_deadline: Fail the transaction if the current block time is greater that the deadline
    // @return premia: Per unit premium without fee adjustment in terms of Fixed
    fn trade_close(
        option_type: OptionType,
        strike_price: Fixed,
        maturity: Timestamp,
        option_side: OptionSide,
        option_size: Int, // in base token currency
        quote_token_address: ContractAddress, // part of underlying_asset definition
        base_token_address: ContractAddress, // part of underlying_asset definition
        limit_total_premia: Fixed, // The limit price that user wants
        tx_deadline: Timestamp, // Timestamp deadline for the transaction to happen
    ) -> Fixed {
        let lptoken_address = get_lptoken_address_for_given_option(
            quote_token_address, base_token_address, option_type
        );

        validate_trade_input(
            option_type,
            strike_price,
            maturity,
            option_side,
            option_size,
            quote_token_address,
            base_token_address,
            lptoken_address,
            false,
            limit_total_premia,
            tx_deadline,
        );

        // Validate deadline
        check_deadline(tx_deadline);

        close_position(
            option_type,
            strike_price,
            maturity,
            option_side,
            option_size,
            quote_token_address,
            base_token_address,
            lptoken_address,
            limit_total_premia,
        )
    }

    // @notice External function for settling a position
    // @dev options_size is always denominated in the lowest possible unit of base token - "wei" for ETH/USDC
    // @dev options_size of 1 ETH would be 10**18 since 1 ETH = 10**18 wei
    // @param option_type: Type of the option 0 for Call, 1 for Put
    // @param strike_price: Option's strike price in terms of Fixed, ie strike 1500 is
    //      1500*2**64 = 27670116110564327424000 -> use FixedTrait::new(27670116110564327424000, false) as input value
    // @param maturity: Option's maturity as unix timestamp
    // @param option_side: Side of the option 0 for Long, 1 for Short
    // @param option_size: Size to be traded denominated in the lowest possible unit of BASE tokens
    // @param quote_token_address: Address of the quote token (USDC in ETH/USDC)
    // @param base_token_address: Address of the base token (ETH in ETH/USDC)
    fn trade_settle(
        option_type: OptionType,
        strike_price: Fixed,
        maturity: Timestamp,
        option_side: OptionSide,
        option_size: Int,
        quote_token_address: ContractAddress, // Identifies underlying_asset
        base_token_address: ContractAddress, // Identifies underlying_asset
    ) {
        let lptoken_address = get_lptoken_address_for_given_option(
            quote_token_address, base_token_address, option_type
        );

        validate_trade_input(
            option_type,
            strike_price,
            maturity,
            option_side,
            option_size,
            quote_token_address,
            base_token_address,
            lptoken_address,
            false,
            FixedTrait::from_felt(1), // effectively switching off this check
            1677588647000, // effectively switching off this check
        );

        // Position can be expired/settled only if the maturity has passed.
        let current_block_time = get_block_timestamp();
        assert(maturity <= current_block_time, 'Settle - option not expired');

        let terminal_price = get_terminal_price(quote_token_address, base_token_address, maturity);

        expire_option_token(
            lptoken_address,
            option_type,
            option_side,
            strike_price,
            terminal_price,
            option_size,
            maturity,
        );
    }
}
