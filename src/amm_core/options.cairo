mod Options {
    use core::traits::TryInto;
    use core::cmp::min;
    use starknet::get_block_timestamp;
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use starknet::contract_address::contract_address_to_felt252;
    use starknet::info::get_contract_address;
    use traits::Into;
    use option::OptionTrait;

    use cubit::f128::types::fixed::Fixed;
    use cubit::f128::types::fixed::FixedTrait;

    use carmine_protocol::amm_core::amm::AMM::TradeOpen;
    use carmine_protocol::amm_core::amm::AMM::TradeClose;
    use carmine_protocol::amm_core::amm::AMM::TradeSettle;
    use carmine_protocol::amm_core::amm::AMM::emit_event;

    use carmine_protocol::amm_core::liquidity_pool::LiquidityPool::expire_option_token_for_pool;

    use carmine_protocol::types::basic::OptionSide;
    use carmine_protocol::types::basic::OptionType;
    use carmine_protocol::types::basic::Math64x61_;
    use carmine_protocol::types::basic::Int;
    use carmine_protocol::types::basic::LPTAddress;
    use carmine_protocol::types::basic::Volatility;
    use carmine_protocol::types::basic::Strike;
    use carmine_protocol::types::basic::Timestamp;

    use carmine_protocol::types::option_::Option_;

    use carmine_protocol::amm_core::helpers::toU256_balance;
    use carmine_protocol::amm_core::helpers::fromU256_balance;
    use carmine_protocol::amm_core::helpers::FixedHelpersTrait;
    use carmine_protocol::amm_core::helpers::split_option_locked_capital;
    use carmine_protocol::amm_core::helpers::assert_option_type_exists;
    use carmine_protocol::amm_core::helpers::assert_option_side_exists;

    use carmine_protocol::amm_core::pricing::option_pricing_helpers::convert_amount_to_option_currency_from_base_uint256;

    use carmine_protocol::amm_core::constants::OPTION_CALL;
    use carmine_protocol::amm_core::constants::OPTION_PUT;
    use carmine_protocol::amm_core::constants::TRADE_SIDE_LONG;
    use carmine_protocol::amm_core::constants::TRADE_SIDE_SHORT;

    use carmine_protocol::amm_core::state::State::get_option_token_address;
    use carmine_protocol::amm_core::state::State::set_option_volatility;
    use carmine_protocol::amm_core::state::State::append_to_available_options;
    use carmine_protocol::amm_core::state::State::get_pool_volatility_adjustment_speed;
    use carmine_protocol::amm_core::state::State::get_max_option_size_percent_of_voladjspd;
    use carmine_protocol::amm_core::state::State::get_underlying_token_address;
    use carmine_protocol::amm_core::state::State::get_pool_definition_from_lptoken_address;
    use carmine_protocol::amm_core::state::State::get_lpool_balance;
    use carmine_protocol::amm_core::state::State::set_lpool_balance;
    use carmine_protocol::amm_core::state::State::get_option_position;
    use carmine_protocol::amm_core::state::State::set_option_position;
    use carmine_protocol::amm_core::state::State::get_pool_locked_capital;
    use carmine_protocol::amm_core::state::State::set_pool_locked_capital;
    use carmine_protocol::amm_core::state::State::get_unlocked_capital;
    use carmine_protocol::amm_core::state::State::set_option_token_address;

    use carmine_protocol::erc20_interface::IERC20Dispatcher;
    use carmine_protocol::erc20_interface::IERC20DispatcherTrait;

    use carmine_protocol::tokens::option_token::IOptionTokenDispatcher;
    use carmine_protocol::tokens::option_token::IOptionTokenDispatcherTrait;
    // @notice Adds option both long and short into the AMM. Requires all the options definition.
    // @notice Basically just calls "add_option" function twice with different option sides
    // @param maturity: Maturity as unix timestamp.
    // @param strike_price: Option's strike price in terms of Fixed, ie strike 1500 is
    //      1500*2**64 = 27670116110564327424000 -> use FixedTrait::new(27670116110564327424000, false) as input value
    // @param quote_token_address: Address of quote token (USDC in case of ETH/USDC).
    // @param base_token_address: Address of base token (ETH in case of ETH/USDC).
    // @param option_type: 0 or 1. 0 for call option and 1 for put option.
    // @param lptoken_address: Address of lp token. Ie identifier of liquidity pool that will be
    //      providing liquidity for this option.
    // @param option_token_address_long: Address of long option token.
    // @param option_token_address_short: Address of short option token.
    // @param initial_volatility: Initial volatility in terms of Fixed. Ie 80% volatility is
    //      inputted as FixedTrait::new(1475739525896764129280, false).
    // @return: Doesn't return anything. 
    fn add_option_both_sides(
        maturity: Timestamp,
        strike_price: Strike,
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        option_type: OptionType,
        lptoken_address: ContractAddress,
        option_token_address_long: ContractAddress,
        option_token_address_short: ContractAddress,
        initial_volatility: Volatility,
    ) {
        add_option(
            TRADE_SIDE_LONG,
            maturity,
            strike_price,
            quote_token_address,
            base_token_address,
            option_type,
            lptoken_address,
            option_token_address_long,
            initial_volatility
        );
        add_option(
            TRADE_SIDE_SHORT,
            maturity,
            strike_price,
            quote_token_address,
            base_token_address,
            option_type,
            lptoken_address,
            option_token_address_short,
            initial_volatility
        );
    }

    // @notice Adds option into the AMM. Requires all the option definition.
    // @param option_side: Either 0 or 1. 0 for long option and 1 for short.
    // @param maturity: Maturity as unix timestamp.
    // @param strike_price: Option's strike price in terms of Fixed, ie strike 1500 is
    //      1500*2**64 = 27670116110564327424000 -> use FixedTrait::new(27670116110564327424000, false) as input value
    // @param quote_token_address: Address of quote token (USDC in case of ETH/USDC).
    // @param base_token_address: Address of base token (ETH in case of ETH/USDC).
    // @param option_type: 0 or 1. 0 for call option and 1 for put option.
    // @param lptoken_address: Address of lp token. Ie identifier of liquidity pool that will be
    //      providing liquidity for this option.
    // @param option_token_address: Address of option token. These token are later on minted when
    //      users are getting into this position.
    // @param initial_volatility: Initial volatility in terms of Fixed. Ie 80% volatility is
    //      inputted as FixedTrait::new(1475739525896764129280, false).
    // @return: Doesn't return anything. 
    fn add_option(
        option_side: OptionSide,
        maturity: Timestamp,
        strike_price: Strike,
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        option_type: OptionType,
        lptoken_address: ContractAddress,
        option_token_address: ContractAddress,
        initial_volatility: Volatility,
    ) {
        assert_option_type_exists(option_type.into(), 'Undefined option type');
        assert_option_side_exists(option_side.into(), 'Undefined option side');

        let now = get_block_timestamp();

        assert(maturity > now, 'Cant add past matuirty');

        let opt_address = get_option_token_address(
            lptoken_address, option_side, maturity, strike_price
        );
        assert(contract_address_to_felt252(opt_address) == 0, 'OPT has already been added');

        let contr_opt_type = IOptionTokenDispatcher { contract_address: option_token_address }
            .option_type();
        let contr_strike = IOptionTokenDispatcher { contract_address: option_token_address }
            .strike_price();
        let contr_maturity = IOptionTokenDispatcher { contract_address: option_token_address }
            .maturity();
        let contr_side = IOptionTokenDispatcher { contract_address: option_token_address }.side();

        assert(contr_opt_type == option_type, 'Option type input doesnt match');
        assert(contr_strike == strike_price, 'Strike price input doesnt match');
        assert(contr_maturity == maturity.into(), 'Maturity input doesnt match');
        assert(contr_side == option_side, 'Option side input doesnt match');

        set_option_volatility(lptoken_address, maturity, strike_price, initial_volatility);

        let option_ = Option_ {
            option_side: option_side,
            maturity: maturity,
            strike_price: strike_price,
            quote_token_address: quote_token_address,
            base_token_address: base_token_address,
            option_type: option_type
        };

        append_to_available_options(option_, lptoken_address);

        set_option_token_address(
            lptoken_address, option_side, maturity, strike_price, option_token_address
        );
    }

    // @notice Mints option token for user and "removes" capital from the user.
    // @dev  User opens/increases its position (if user is long, it increases the size of its long,
    //      if he/she is short, the short gets increased).
    //      Switching position from long to short requires both mint_option_token and burn_option_token
    //      functions to be called. This also changes internal state of the pool and realocates locked
    //      capital/premia and fees between user and the pool for example how much capital is unlocked,
    //      how much is locked,...
    // @param lptoken_address: Address of lp token. Ie identifier of liquidity pool that will be
    //      providing liquidity for this option.
    // @param option_size: Size of option to be minted. In decimals of base token (ETH in case of
    //      ETH/USDC). For example size 0.1 is inputted as 0.1 * 10**18.
    // @param option_size_in_pool_currency: Same as option_size, just in the pool's currency
    //      (each option is assigned to given pool). For example for PUT option this is in USDC.
    //      This variable is used to lock in capital into the option. This means that
    //      option_size_in_pool_currency might be tiny bit bigger than option_size in value, but not
    //      smaller.
    // @param option_side: Either 0 or 1. 0 for long option and 1 for short.
    // @param option_type: 0 or 1. 0 for call option and 1 for put option.
    // @param maturity: Maturity as unix timestamp.
    // @param strike_price: Option's strike price in terms of Fixed, ie strike 1500 is
    //      1500*2**64 = 27670116110564327424000 -> use FixedTrait::new(27670116110564327424000, false) as input value
    // @param premia_including_fees: What the user pays for the option or what the user gets
    //      for the option in terms of premium. It's already adjusted for fees but not for locked
    //      capital if that is required. In terms of Fixed
    // @param underlying_price: Price of the underlying asset.
    // @return: Doesn't return anything.
    fn mint_option_token(
        lptoken_address: LPTAddress,
        option_size: Int, // in base tokens (ETH in case of ETH/USDC)
        option_size_in_pool_currency: u256,
        option_side: OptionSide,
        option_type: OptionType,
        maturity: Timestamp, // in seconds
        strike_price: Strike,
        premia_including_fees: Fixed, // either base or quote token
        underlying_price: Fixed,
    ) {
        let opt_address = get_option_token_address(
            lptoken_address, option_side, maturity, strike_price
        );

        let contr_opt_type = IOptionTokenDispatcher { contract_address: opt_address }.option_type();
        let contr_strike = IOptionTokenDispatcher { contract_address: opt_address }.strike_price();
        let contr_maturity = IOptionTokenDispatcher { contract_address: opt_address }.maturity();
        let contr_side = IOptionTokenDispatcher { contract_address: opt_address }.side();

        assert(contr_opt_type == option_type, 'Option type input doesnt match');
        assert(contr_strike == strike_price, 'Strike price input doesnt match');
        assert(contr_maturity == maturity, 'Maturity input doesnt match');
        assert(contr_side == option_side, 'Option side input doesnt match');

        if option_side == TRADE_SIDE_LONG {
            _mint_option_token_long(
                lptoken_address,
                opt_address,
                option_size,
                option_size_in_pool_currency,
                premia_including_fees,
                option_type,
                maturity,
                strike_price,
            );
        } else {
            _mint_option_token_short(
                lptoken_address,
                opt_address,
                option_size,
                option_size_in_pool_currency,
                premia_including_fees,
                option_type,
                maturity,
                strike_price,
            );
        }

        let hundred = FixedTrait::from_unscaled_felt(100);
        let adjspd_cubit = get_pool_volatility_adjustment_speed(lptoken_address);

        let max_opt_perc = get_max_option_size_percent_of_voladjspd();
        let max_opt_perc_cubit = FixedTrait::new_unscaled(max_opt_perc, false);
        let ratio = max_opt_perc_cubit / hundred;

        let max_optsize_cubit = ratio * adjspd_cubit;
        let max_optsize = toU256_balance(max_optsize_cubit, opt_address);

        assert(option_size_in_pool_currency <= max_optsize, 'Trade exceeds max optsize');
    }


    // @notice Mints LONG option token for user and "removes" capital from the user.
    // @dev Not only mints the option token, but also transfers cash from user and update
    //      internal state. Transfers premium from user to the pool and locks the pool's capital
    //      to guarantee the buyers payment.
    // @param lptoken_address: Address of lp token. Ie identifier of liquidity pool that will be
    //      providing liquidity for this option.
    // @param option_token_address:
    // @param option_size: Size of option to be minted. In decimals of base token (ETH in case of
    //      ETH/USDC). For example size 0.1 is inputted as 0.1 * 10**18.
    // @param option_size_in_pool_currency: Same as option_size, just in the pool's currency
    //      (each option is assigned to given pool). For example for PUT option this is in USDC.
    //      This variable is used to lock in capital into the option. This means that
    //      option_size_in_pool_currency might be tiny bit bigger than option_size in value, but not
    //      smaller.
    // @param premia_including_fees: What the user pays for the option or what the user gets
    //      for the option in terms of premium. It's already adjusted for fees but not for locked
    //      capital if that is required. In terms of Fixed
    // @param option_type: 0 or 1. 0 for call option and 1 for put option.
    // @param maturity: Maturity as unix timestamp.
    // @param strike_price: Option's strike price in terms of Fixed, ie strike 1500 is
    //      1500*2**64 = 27670116110564327424000 -> use FixedTrait::new(27670116110564327424000, false) as input value
    // @return: Doesn't return anything.
    fn _mint_option_token_long(
        lptoken_address: LPTAddress,
        option_token_address: ContractAddress,
        option_size: Int,
        option_size_in_pool_currency: u256,
        premia_including_fees: Fixed,
        option_type: OptionType,
        maturity: Timestamp,
        strike_price: Strike,
    ) {
        let curr_contract_address = get_contract_address();
        let user_address = get_caller_address();
        let currency_address = get_underlying_token_address(lptoken_address);
        let pool_definition = get_pool_definition_from_lptoken_address(lptoken_address);
        let base_address = pool_definition.base_token_address;
        let quote_address = pool_definition.quote_token_address;

        assert(!option_token_address.is_zero(), 'MOTL - opt addr is zero');
        assert(!lptoken_address.is_zero(), 'MOTL - lpt addr is zero');
        assert(!curr_contract_address.is_zero(), 'MOTL - curr addr is zero');
        assert(!user_address.is_zero(), 'MOTL - user addr is zero');

        // Move premia from user to the pool
        let premia_including_fees_u256 = toU256_balance(premia_including_fees, currency_address);

        emit_event(
            TradeOpen {
                caller: user_address,
                option_token: option_token_address,
                capital_transfered: premia_including_fees_u256,
                option_tokens_minted: option_size.into()
            }
        );

        // Pool is locking in capital only if there is no previous position to cover the user's long
        //      -> if pool does not have sufficient long to "pass down to user", it has to lock
        //           capital... option position has to be updated too!!!

        // Increase lpool_balance by premia_including_fees -> this also increases unlocked capital
        // since only locked_capital storage_var exists
        let current_balance = get_lpool_balance(lptoken_address);
        let new_balance = current_balance + premia_including_fees_u256;

        // The nonnegativity of new_balance is checked inside of the set_lpool_balance
        set_lpool_balance(lptoken_address, new_balance);

        let current_long_position = get_option_position(
            lptoken_address, TRADE_SIDE_LONG, maturity, strike_price
        );

        let current_short_position = get_option_position(
            lptoken_address, TRADE_SIDE_SHORT, maturity, strike_price
        )
            .into();

        let current_locked_balance = get_pool_locked_capital(lptoken_address);

        // Get diffs to update everything
        let decrease_long_by = min(option_size, current_long_position);
        let increase_short_by = option_size - decrease_long_by;

        let strike_price_u256 = toU256_balance(strike_price, quote_address);
        let increase_locked_by = convert_amount_to_option_currency_from_base_uint256(
            increase_short_by.into(),
            option_type,
            strike_price_u256, // Strike price should never be negative anyway
            base_address
        );

        let new_long_position = current_long_position - decrease_long_by;

        let new_short_position = current_short_position + increase_short_by;

        let new_locked_capital = current_locked_balance + increase_locked_by;

        // Check that there is enough capital to be locked.
        assert(new_locked_capital <= new_balance, 'MOTL - not enough unlocked');

        set_option_position(
            lptoken_address, TRADE_SIDE_LONG, maturity, strike_price, new_long_position
        );
        set_option_position(
            lptoken_address, TRADE_SIDE_SHORT, maturity, strike_price, new_short_position
        );
        set_pool_locked_capital(lptoken_address, new_locked_capital);

        // Mint tokens
        IOptionTokenDispatcher { contract_address: option_token_address }
            .mint(user_address, option_size.into());

        assert(premia_including_fees_u256 > 0, 'MOTL: prem incl fees is 0');

        // Transfer premia 
        let transfer_res = IERC20Dispatcher { contract_address: currency_address }
            .transferFrom(user_address, curr_contract_address, premia_including_fees_u256);

        assert(transfer_res, 'MOTL: unable to transfer premia');
    }

    // @notice Mints SHORT option token for user and "removes" capital from the user.
    // @dev Not only mints the option token, but also transfers cash from user and update
    //      internal state. Transfers (locked capital minus premium) from user to the pool to guarantee
    //      pool's payoff.
    // @param lptoken_address: Address of lp token. Ie identifier of liquidity pool that will be
    //      providing liquidity for this option.
    // @param option_token_address:
    // @param option_size: Size of option to be minted. In decimals of base token (ETH in case of
    //      ETH/USDC). For example size 0.1 is inputted as 0.1 * 10**18.
    // @param option_size_in_pool_currency: Same as option_size, just in the pool's currency
    //      (each option is assigned to given pool). For example for PUT option this is in USDC.
    //      This variable is used to lock in capital into the option. This means that
    //      option_size_in_pool_currency might be tiny bit bigger than option_size in value, but not
    //      smaller.
    // @param premia_including_fees: What the user pays for the option or what the user gets
    //      for the option in terms of premium. It's already adjusted for fees but not for locked
    //      capital if that is required. In terms of Fixed
    // @param option_type: 0 or 1. 0 for call option and 1 for put option.
    // @param maturity: Maturity as unix timestamp.
    // @param strike_price: Option's strike price in terms of Fixed, ie strike 1500 is
    //      1500*2**64 = 27670116110564327424000 -> use FixedTrait::new(27670116110564327424000, false) as input value
    // @return: Doesn't return anything.
    fn _mint_option_token_short(
        lptoken_address: LPTAddress,
        option_token_address: ContractAddress,
        option_size: Int,
        option_size_in_pool_currency: u256,
        premia_including_fees: Fixed,
        option_type: OptionType,
        maturity: Timestamp,
        strike_price: Strike,
    ) {
        let curr_contract_address = get_contract_address();
        let user_address = get_caller_address();
        let currency_address = get_underlying_token_address(lptoken_address);
        let pool_definition = get_pool_definition_from_lptoken_address(lptoken_address);
        let base_address = pool_definition.base_token_address;
        let quote_address = pool_definition.quote_token_address;

        assert(!option_token_address.is_zero(), 'MOTS - opt addr is zero');
        assert(!lptoken_address.is_zero(), 'MOTS - lpt addr is zero');
        assert(!curr_contract_address.is_zero(), 'MOTS - curr addr is zero');
        assert(!user_address.is_zero(), 'MOTS - user addr is zero');

        // let option_size_u256: u256 = option_size.into();
        let premia_including_fees_u256 = toU256_balance(premia_including_fees, currency_address);
        let to_be_paid_by_user = option_size_in_pool_currency - premia_including_fees_u256;

        emit_event(
            TradeOpen {
                caller: user_address,
                option_token: option_token_address,
                capital_transfered: premia_including_fees_u256,
                option_tokens_minted: option_size.into()
            }
        );

        // Decrease lpool_balance by premia_including_fees -> this also decreases unlocked capital
        // since only locked_capital storage_var exists
        let current_balance = get_lpool_balance(lptoken_address);
        let new_balance = current_balance - premia_including_fees_u256;
        set_lpool_balance(lptoken_address, new_balance);

        // User is going short, hence user is locking in capital...
        //      if pool has short position -> unlock pool's capital
        // pools_position is in terms of base tokens (ETH in case of ETH/USD)...
        //      in same units is option_size
        // since user wants to go short, the pool can "sell off" its short... and unlock its capital

        // Update pool's short position
        let pools_short_position = get_option_position(
            lptoken_address, TRADE_SIDE_SHORT, maturity, strike_price
        );

        let size_to_be_unlocked_in_base = min(option_size, pools_short_position);

        let new_pools_short_position = pools_short_position - size_to_be_unlocked_in_base;
        set_option_position(
            lptoken_address, TRADE_SIDE_SHORT, maturity, strike_price, new_pools_short_position
        );

        // Update pool's long position
        let pools_long_position = get_option_position(
            lptoken_address, TRADE_SIDE_LONG, maturity, strike_price
        );
        let size_to_increase_long_position = option_size - size_to_be_unlocked_in_base;
        let new_pools_long_position = pools_long_position + size_to_increase_long_position;
        
        set_option_position(
            lptoken_address, TRADE_SIDE_LONG, maturity, strike_price, new_pools_long_position
        );

        // Update the locked capital
        let size_to_be_unlocked_in_base_u256: u256 = size_to_be_unlocked_in_base.into();
        let strike_price_u256 = toU256_balance(strike_price, quote_address);
        let size_to_be_unlocked = convert_amount_to_option_currency_from_base_uint256(
            size_to_be_unlocked_in_base_u256, option_type, strike_price_u256, base_address
        );
        let current_locked_balance = get_pool_locked_capital(lptoken_address);
        let new_locked_balance = current_locked_balance - size_to_be_unlocked;

        // Non negativity of the new_locked_balance is validated in set_pool_locked_capital
        set_pool_locked_capital(lptoken_address, new_locked_balance);

        // Mint tokens
        IOptionTokenDispatcher { contract_address: option_token_address }
            .mint(user_address, option_size.into());

        // Move (option_size minus (premia minus fees)) from user to the pool
        let transfer_res = IERC20Dispatcher { contract_address: currency_address }
            .transferFrom(user_address, curr_contract_address, to_be_paid_by_user);

        assert(transfer_res, 'MOTS: unable to transfer premia');
    }


    // @notice Burns option token (closes position) for user and "sends" capital to the user.
    // @dev User decreases its position (if user is long, it decreases the size of its long, if he/she
    //      is short, the short gets decreased). Switching position from long to short requires both
    //      mint_option_token and burn_option_token functions to be called. This also changes internal
    //      state of the pool and realocates locked capital/premia and fees between user and the pool
    //      for example how much capital is unlocked, how much is locked,...
    // @param lptoken_address: Address of lp token. Ie identifier of liquidity pool that will be
    //      providing liquidity for this option.
    // @param option_size: Size of option to be minted. In decimals of base token (ETH in case of
    //      ETH/USDC). For example size 0.1 is inputted as 0.1 * 10**18.
    // @param option_size_in_pool_currency: Same as option_size, just in the pool's currency
    //      (each option is assigned to given pool). For example for PUT option this is in USDC.
    //      This variable is used to lock in capital into the option. This means that
    //      option_size_in_pool_currency might be tiny bit bigger than option_size in value, but not
    //      smaller.
    // @param option_side: Either 0 or 1. 0 for long option and 1 for short.
    // @param option_type: 0 or 1. 0 for call option and 1 for put option.
    // @param maturity: Maturity as unix timestamp.
    // @param strike_price: Option's strike price in terms of Fixed, ie strike 1500 is
    //      1500*2**64 = 27670116110564327424000 -> use FixedTrait::new(27670116110564327424000, false) as input value
    // @param premia_including_fees: What the user gets for the option or what the user pays
    //      for the option in terms of premium. It's already adjusted for fees but not for locked
    //      capital if that is required. In terms of Fixed
    // @param underlying_price: Price of the underlying asset.
    // @return: Doesn't return anything.
    fn burn_option_token(
        lptoken_address: LPTAddress,
        option_size: Int, // in base tokens (ETH in case of ETH/USDC)
        option_size_in_pool_currency: u256,
        option_side: OptionSide,
        option_type: OptionType,
        maturity: Timestamp, // in seconds
        strike_price: Strike,
        premia_including_fees: Fixed, // either base or quote token
        underlying_price: Fixed,
    ) {
        let opt_address = get_option_token_address(
            lptoken_address, option_side, maturity, strike_price
        );

        let contr_opt_type = IOptionTokenDispatcher { contract_address: opt_address }.option_type();
        let contr_strike = IOptionTokenDispatcher { contract_address: opt_address }.strike_price();
        let contr_maturity = IOptionTokenDispatcher { contract_address: opt_address }.maturity();
        let contr_side = IOptionTokenDispatcher { contract_address: opt_address }.side();

        assert(contr_opt_type == option_type, 'Option type input doesnt match');
        assert(contr_strike == strike_price, 'Strike price input doesnt match');
        assert(contr_maturity == maturity.into(), 'Maturity input doesnt match');
        assert(contr_side == option_side, 'Option side input doesnt match');

        if option_side == TRADE_SIDE_LONG {
            _burn_option_token_long(
                lptoken_address,
                opt_address,
                option_size,
                option_size_in_pool_currency,
                premia_including_fees,
                option_side,
                option_type,
                maturity,
                strike_price,
            );
        } else {
            _burn_option_token_short(
                lptoken_address,
                opt_address,
                option_size,
                option_size_in_pool_currency,
                premia_including_fees,
                option_side,
                option_type,
                maturity,
                strike_price,
            );
        }

        let hundred = FixedTrait::from_unscaled_felt(100);
        let adjspd_cubit = get_pool_volatility_adjustment_speed(lptoken_address);

        let max_opt_perc = get_max_option_size_percent_of_voladjspd();
        let max_opt_perc_cubit = FixedTrait::new_unscaled(max_opt_perc, false);
        let ratio = max_opt_perc_cubit / hundred;

        let max_optsize_cubit = ratio * adjspd_cubit;
        let max_optsize = toU256_balance(max_optsize_cubit, opt_address);

        assert(option_size_in_pool_currency <= max_optsize, 'Trade exceeds max optsize');
    }


    // @notice Burns LONG option token (closes position) for user and "sends" capital to the user.
    // @dev Burns users tokens, sends capital to the user and updates internal state.
    // @param lptoken_address: Address of lp token. Ie identifier of liquidity pool that will be
    //      providing liquidity for this option.
    // @param option_token_address: Address of the option token to be burned.
    // @param option_size: Size of option to be minted. In decimals of base token (ETH in case of
    //      ETH/USDC). For example size 0.1 is inputted as 0.1 * 10**18.
    // @param option_size_in_pool_currency: Same as option_size, just in the pool's currency
    //      (each option is assigned to given pool). For example for PUT option this is in USDC.
    //      This variable is used to lock in capital into the option. This means that
    //      option_size_in_pool_currency might be tiny bit bigger than option_size in value, but not
    //      smaller.
    // @param premia_including_fees: What the user gets for the option or what the user pays
    //      for the option in terms of premium. It's already adjusted for fees but not for locked
    //      capital if that is required.
    // @param option_side: Either 0 or 1. 0 for long option and 1 for short.
    // @param option_type: 0 or 1. 0 for call option and 1 for put option.
    // @param maturity: Maturity as unix timestamp.
    // @param strike_price: Option's strike price in terms of Fixed, ie strike 1500 is
    //      1500*2**64 = 27670116110564327424000 -> use FixedTrait::new(27670116110564327424000, false) as input value
    // @return: Doesn't return anything.
    fn _burn_option_token_long(
        lptoken_address: LPTAddress,
        option_token_address: ContractAddress,
        option_size: Int,
        option_size_in_pool_currency: u256,
        premia_including_fees: Fixed,
        option_side: OptionSide,
        option_type: OptionType,
        maturity: Timestamp,
        strike_price: Strike,
    ) {
        let curr_contract_address = get_contract_address();
        let user_address = get_caller_address();
        let currency_address = get_underlying_token_address(lptoken_address);
        let pool_definition = get_pool_definition_from_lptoken_address(lptoken_address);
        let base_address = pool_definition.base_token_address;
        let quote_address = pool_definition.quote_token_address;

        assert(!option_token_address.is_zero(), 'MOTL - opt addr is zero');
        assert(!lptoken_address.is_zero(), 'MOTL - lpt addr is zero');
        assert(!curr_contract_address.is_zero(), 'MOTL - curr addr is zero');
        assert(!user_address.is_zero(), 'MOTL - user addr is zero');

        let option_size_u256: u256 = option_size.into();
        let premia_including_fees_u256 = toU256_balance(premia_including_fees, currency_address);

        emit_event(
            TradeClose {
                caller: user_address,
                option_token: option_token_address,
                capital_transfered: premia_including_fees_u256,
                option_tokens_burned: option_size.into()
            }
        );

        // Decrease lpool_balance by premia_including_fees -> this also decreases unlocked capital
        // This decrease is happening because burning long is similar to minting short,
        // hence the payment.
        let current_balance = get_lpool_balance(lptoken_address);
        let new_balance = current_balance - premia_including_fees_u256;
        set_lpool_balance(lptoken_address, new_balance);

        let pool_short_position = get_option_position(
            lptoken_address, TRADE_SIDE_SHORT, maturity, strike_price
        );
        let pool_long_position = get_option_position(
            lptoken_address, TRADE_SIDE_LONG, maturity, strike_price
        );

        if pool_short_position == 0 {
            // If pool is LONG:
            // Burn long increases pool's long (if pool was already long)
            //      -> The locked capital was locked by users and not pool
            //      -> do not decrease pool_locked_capital by the option_size_in_pool_currency
            let new_option_position = pool_long_position + option_size;

            set_option_position(
                lptoken_address, option_side, maturity, strike_price, new_option_position
            );
        } else {
            // If pool is SHORT
            // Burn decreases the pool's short
            //     -> decrease the pool_locked_capital by
            //        min(size of pools short, amount_in_pool_currency)
            //        since the pools' short might not be covering all of the long

            let current_locked_balance = get_pool_locked_capital(lptoken_address);
            let pool_short_pos_u256: u256 = pool_short_position.into();
            let option_size_u256: u256 = option_size.into();

            let size_to_be_unlocked_in_base_u256 = min(pool_short_pos_u256, option_size_u256,);

            let strike_price_u256 = toU256_balance(strike_price, quote_address);

            let size_to_be_unlocked = convert_amount_to_option_currency_from_base_uint256(
                size_to_be_unlocked_in_base_u256, option_type, strike_price_u256, base_address
            );
            let new_locked_balance = current_locked_balance - size_to_be_unlocked;
            set_pool_locked_capital(lptoken_address, new_locked_balance);

            // Update pool's short position
            let new_pools_short_position = pool_short_pos_u256 - size_to_be_unlocked_in_base_u256;

            set_option_position(
                lptoken_address,
                TRADE_SIDE_SHORT,
                maturity,
                strike_price,
                new_pools_short_position.try_into().expect('BOTL - new short pos overflow')
            );

            // Update pool's long position
            let size_to_increase_long_position = option_size.into()
                - size_to_be_unlocked_in_base_u256;
                

            let new_pools_long_position = pool_long_position.into()
                + size_to_increase_long_position;
            
            set_option_position(
                lptoken_address,
                TRADE_SIDE_LONG,
                maturity,
                strike_price,
                new_pools_long_position.try_into().expect('BOTL - new long pos overflow')
            );
        }

        // Burn tokens
        IOptionTokenDispatcher { contract_address: option_token_address }
            .burn(user_address, option_size_u256);

        let transfer_res = IERC20Dispatcher { contract_address: currency_address }
            .transfer(user_address, premia_including_fees_u256,);
        assert(transfer_res, 'BOTL: unable to transfer premia');
    }


    // @notice Burns SHORT option token (closes position) for user and "sends" capital to the user.
    // @dev Burns users tokens, sends capital to the user and updates internal state.
    // @param lptoken_address: Address of lp token. Ie identifier of liquidity pool that will be
    //      providing liquidity for this option.
    // @param option_token_address: Address of the option token to be burned.
    // @param option_size: Size of option to be minted. In decimals of base token (ETH in case of
    //      ETH/USDC). For example size 0.1 is inputted as 0.1 * 10**18.
    // @param option_size_in_pool_currency: Same as option_size, just in the pool's currency
    //      (each option is assigned to given pool). For example for PUT option this is in USDC.
    //      This variable is used to lock in capital into the option. This means that
    //      option_size_in_pool_currency might be tiny bit bigger than option_size in value, but not
    //      smaller.
    // @param premia_including_fees: What the user gets for the option or what the user pays
    //      for the option in terms of premium. It's already adjusted for fees but not for locked
    //      capital if that is required.
    // @param option_side: Either 0 or 1. 0 for long option and 1 for short.
    // @param option_type: 0 or 1. 0 for call option and 1 for put option.
    // @param maturity: Maturity as unix timestamp.
    // @param strike_price: Option's strike price in terms of Fixed, ie strike 1500 is
    //      1500*2**64 = 27670116110564327424000 -> use FixedTrait::new(27670116110564327424000, false) as input value
    // @return: Doesn't return anything.
    fn _burn_option_token_short(
        lptoken_address: LPTAddress,
        option_token_address: ContractAddress,
        option_size: Int,
        option_size_in_pool_currency: u256,
        premia_including_fees: Fixed,
        option_side: OptionSide,
        option_type: OptionType,
        maturity: Timestamp,
        strike_price: Strike,
    ) {
        let curr_contract_address = get_contract_address();
        let user_address = get_caller_address();
        let currency_address = get_underlying_token_address(lptoken_address);
        let pool_definition = get_pool_definition_from_lptoken_address(lptoken_address);
        let base_address = pool_definition.base_token_address;
        let quote_address = pool_definition.quote_token_address;

        assert(!option_token_address.is_zero(), 'MOTL - opt addr is zero');
        assert(!lptoken_address.is_zero(), 'MOTL - lpt addr is zero');
        assert(!curr_contract_address.is_zero(), 'MOTL - curr addr is zero');
        assert(!user_address.is_zero(), 'MOTL - user addr is zero');

        let option_size_u256: u256 = option_size.into();
        let premia_including_fees_u256 = toU256_balance(premia_including_fees, currency_address);

        let total_user_payment = option_size_in_pool_currency - premia_including_fees_u256;

        emit_event(
            TradeClose {
                caller: user_address,
                option_token: option_token_address,
                capital_transfered: premia_including_fees_u256,
                option_tokens_burned: option_size.into()
            }
        );

        // Increase lpool_balance by premia_including_fees -> this also increases unlocked capital
        // This increase is happening because burning short is similar to minting long,
        // hence the payment.
        let current_balance = get_lpool_balance(lptoken_address);
        let new_balance = current_balance + premia_including_fees_u256;
        set_lpool_balance(lptoken_address, new_balance);

        // Find out pools position... if it has short position = 0 -> it is long or at 0
        let pool_short_position = get_option_position(
            lptoken_address, TRADE_SIDE_SHORT, maturity, strike_price
        );

        let current_locked_capital_u256 = get_pool_locked_capital(lptoken_address);
        // FIXME: the inside of the if (not the else) should work for both cases
        //      -> validate and update for more simple code

        if pool_short_position == 0 {
            // If pool is LONG
            // Burn decreases pool's long -> up to a size of the pool's long 
            //      -> if option_size_in_pool_currency > pool's long -> pool starts to accumulate
            //         the short and has to lock in it's own capital -> lock capital
            //      -> there might be a case, when there is not enough capital to be locked -> fail
            //         the transaction
            let pool_long_position = get_option_position(
                lptoken_address, TRADE_SIDE_LONG, maturity, strike_price
            );

            let pool_long_pos_u256: u256 = pool_long_position.into();
            let pool_short_pos_u256: u256 = pool_short_position.into();
            let opt_size_u256: u256 = option_size.into();

            let decrease_long_position_by = min(pool_long_pos_u256, opt_size_u256);
            let increase_short_position_by = option_size_u256 - decrease_long_position_by;
            

            let new_long_position = pool_long_pos_u256 - decrease_long_position_by;
            let new_short_position = pool_short_pos_u256 + increase_short_position_by;


            // The increase_short_position_by and capital_to_be_locked might both be zero,
            // if the long position is sufficient.

            let strike_price_u256: u256 = toU256_balance(strike_price, quote_address);
            let capital_to_be_locked = convert_amount_to_option_currency_from_base_uint256(
                increase_short_position_by, option_type, strike_price_u256, base_address
            );

            let new_locked_capital = current_locked_capital_u256 - capital_to_be_locked;

            // Set the option positions
            set_option_position(
                lptoken_address,
                TRADE_SIDE_LONG,
                maturity,
                strike_price,
                new_long_position.try_into().expect('BOTS - new long pos overflow')
            );
            set_option_position(
                lptoken_address,
                TRADE_SIDE_SHORT,
                maturity,
                strike_price,
                new_short_position.try_into().expect('BOTS - new short pos overflow')
            );

            // Set the pool_locked_capital_.
            set_pool_locked_capital(lptoken_address, new_locked_capital);

            // Assert there is enough capital to be locked       
            assert(new_locked_capital <= new_balance, 'BOTS - not enough capital');
        } else {
            // If pool is SHORT
            // Burn increases pool's short
            //      -> increase pool's locked capital by the option_size_in_pool_currency
            //      -> there might not be enough unlocked capital to be locked
            let current_unlocked_capital_u256 = get_unlocked_capital(lptoken_address);

            // Update locked capital
            let new_locked_capital = current_unlocked_capital_u256 + option_size_in_pool_currency;

            assert(
                option_size_in_pool_currency <= current_unlocked_capital_u256,
                'BOTS - not enough capital'
            );
            assert(new_locked_capital <= new_balance, 'BOTS - not enough lock cap');

            // checking that new_locked_capital is non negative is done in the set_pool_locked_capital
            set_pool_locked_capital(lptoken_address, new_locked_capital);

            // Update pools (short) position
            let new_pools_short_position = pool_short_position + option_size;
            
            set_option_position(
                lptoken_address, TRADE_SIDE_SHORT, maturity, strike_price, new_pools_short_position
            );
        // Burn tokens
        }

        IOptionTokenDispatcher { contract_address: option_token_address }
            .burn(user_address, option_size_u256);

        let transfer_res = IERC20Dispatcher { contract_address: currency_address }
            .transfer(user_address, total_user_payment,);

        assert(transfer_res, 'BOTL: unable to transfer premia');
    }

    // @notice Expires option token for the user.
    // @dev Not an external func, it is used through trade_settle.
    // @param lptoken_address: Address of lp token. Ie identifier of liquidity pool that will be
    //      providing liquidity for this option.
    // @param option_type: 0 or 1. 0 for call option and 1 for put option.
    // @param option_side: Either 0 or 1. 0 for long option and 1 for short.
    // @param strike_price: Option's strike price in terms of Fixed, ie strike 1500 is
    //      1500*2**64 = 27670116110564327424000 -> use FixedTrait::new(27670116110564327424000, false) as input value
    // @param terminal_price: Price at which the option get settled. In terms of Fixed
    // @param option_size: Size of option to be minted. In decimals of base token (ETH in case of
    //      ETH/USDC). For example size 0.1 is inputted as 0.1 * 10**18.
    // @param maturity: Maturity as unix timestamp.
    // @return: Doesn't return anything.
    fn expire_option_token(
        lptoken_address: LPTAddress,
        option_type: OptionType,
        option_side: OptionSide,
        strike_price: Strike,
        terminal_price: Fixed,
        option_size: Int,
        maturity: Timestamp,
    ) {
        // EXPIRES OPTIONS ONLY FOR USERS (OPTION TOKEN HOLDERS) NOT FOR POOL.
        // terminal price is price at which option is being settled

        let option_token_address = get_option_token_address(
            lptoken_address, option_side, maturity, strike_price
        );
        let currency_address = get_underlying_token_address(lptoken_address);
        let base_token_address = IOptionTokenDispatcher { contract_address: option_token_address }
            .base_token_address();

        // The option (underlying asset x maturity x option type x strike) has to be "expired"
        // (settled) on the pool's side in terms of locked capital. Ie check that SHORT position
        // has been settled, if pool is LONG then it did not lock capital and we can go on.
        let current_pool_position = get_option_position(
            lptoken_address, TRADE_SIDE_SHORT, maturity, strike_price
        );

        if (current_pool_position != 0) {
            expire_option_token_for_pool(lptoken_address, option_side, strike_price, maturity,);
        }
        // Check that the pool's position was expired correctly
        let current_pool_position_2 =
            get_option_position( // FIXME this is called twice in the happy case
            lptoken_address, option_side, maturity, strike_price
        );
        assert(current_pool_position_2 == 0, 'EOT - pool pos not zero');

        // Make sure that user owns the option tokens
        let user_address = get_caller_address();
        let user_tokens_owned = IOptionTokenDispatcher { contract_address: option_token_address }
            .balance_of(user_address);
        assert(user_tokens_owned > 0, 'EOT - User has no tokens');

        let current_block_time = get_block_timestamp();
        assert(maturity <= current_block_time, 'EOT - contract not ripe');

        // long_value and short_value are both in terms of locked capital
        let option_size_cubit = fromU256_balance(option_size.into(), base_token_address);
        let (long_value, short_value) = split_option_locked_capital(
            option_type,
            option_size_cubit, // TODO: This is wrong, it should stay in Int
            strike_price,
            terminal_price
        );

        let long_value_u256 = toU256_balance(long_value, currency_address);
        let short_value_u256 = toU256_balance(short_value, currency_address);

        let option_size_u256: u256 = option_size.into();

        assert(option_size_u256 <= user_tokens_owned, 'EOT - opt size > owned');

        IOptionTokenDispatcher { contract_address: option_token_address }
            .burn(user_address, option_size_u256);

        if (option_side == TRADE_SIDE_LONG) {
            // User is long
            // When user was long there is a possibility, that the pool is short,
            // which means that pool has locked in some capital.
            // We assume pool is able to "expire" it's functions pretty quickly so the updates
            // of storage_vars has already happened.

            let transfer_res = IERC20Dispatcher { contract_address: currency_address }
                .transfer(user_address, long_value_u256,);

            assert(transfer_res, 'EOT: unable to transfer funds');
            emit_event(
                TradeSettle {
                    caller: user_address,
                    option_token: option_token_address,
                    capital_transfered: long_value_u256,
                    option_tokens_burned: option_size_u256,
                }
            );
        } else {
            // User is short
            // User locked in capital (no locking happened from pool - no locked capital and similar
            // storage vars were updated).

            let transfer_res = IERC20Dispatcher { contract_address: currency_address }
                .transfer(user_address, short_value_u256,);

            assert(transfer_res, 'EOT: unable to transfer funds');

            emit_event(
                TradeSettle {
                    caller: user_address,
                    option_token: option_token_address,
                    capital_transfered: short_value_u256,
                    option_tokens_burned: option_size_u256,
                }
            );
        }
    }
}
