mod LiquidityPool {
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use starknet::info::get_contract_address;
    use starknet::get_block_timestamp;
    use integer::U256DivRem;

    use traits::Into;
    use traits::TryInto;
    use option::OptionTrait;

    use cubit::f128::types::fixed::Fixed;
    use cubit::f128::types::fixed::FixedTrait;

    use carmine_protocol::erc20_interface::IERC20Dispatcher;
    use carmine_protocol::erc20_interface::IERC20DispatcherTrait;

    use carmine_protocol::types::basic::LPTAddress;
    use carmine_protocol::types::basic::OptionType;
    use carmine_protocol::types::basic::OptionSide;
    use carmine_protocol::types::basic::Int;
    use carmine_protocol::types::basic::Timestamp;

    use carmine_protocol::types::option_::Option_;
    use carmine_protocol::types::option_::Option_Trait;
    use carmine_protocol::types::pool::Pool;

    use carmine_protocol::amm_core::amm::AMM::DepositLiquidity;
    use carmine_protocol::amm_core::amm::AMM::WithdrawLiquidity;
    use carmine_protocol::amm_core::amm::AMM::ExpireOptionTokenForPool;
    use carmine_protocol::amm_core::amm::AMM::emit_event;

    use carmine_protocol::amm_core::oracles::agg::OracleAgg::get_terminal_price;

    use carmine_protocol::amm_core::state::State::get_available_options;
    use carmine_protocol::amm_core::state::State::get_option_position;
    use carmine_protocol::amm_core::state::State::get_option_volatility;
    use carmine_protocol::amm_core::state::State::get_lptoken_address_for_given_option;
    use carmine_protocol::amm_core::state::State::get_pool_volatility_adjustment_speed;
    use carmine_protocol::amm_core::state::State::get_unlocked_capital;
    use carmine_protocol::amm_core::state::State::get_underlying_token_address;
    use carmine_protocol::amm_core::state::State::fail_if_existing_pool_definition_from_lptoken_address;
    use carmine_protocol::amm_core::state::State::append_to_available_lptoken_addresses;
    use carmine_protocol::amm_core::state::State::set_lptoken_address_for_given_option;
    use carmine_protocol::amm_core::state::State::set_pool_definition_from_lptoken_address;
    use carmine_protocol::amm_core::state::State::set_underlying_token_address;
    use carmine_protocol::amm_core::state::State::set_pool_volatility_adjustment_speed;
    use carmine_protocol::amm_core::state::State::set_max_lpool_balance;
    use carmine_protocol::amm_core::state::State::get_lpool_balance;
    use carmine_protocol::amm_core::state::State::set_lpool_balance;
    use carmine_protocol::amm_core::state::State::get_max_lpool_balance;
    use carmine_protocol::amm_core::state::State::get_pool_locked_capital;
    use carmine_protocol::amm_core::state::State::set_pool_locked_capital;
    use carmine_protocol::amm_core::state::State::get_option_info;
    use carmine_protocol::amm_core::state::State::set_option_position;
    use carmine_protocol::amm_core::state::State::get_available_options_usable_index;

    use carmine_protocol::amm_core::helpers::toU256_balance;
    use carmine_protocol::amm_core::helpers::assert_option_type_exists;
    use carmine_protocol::amm_core::helpers::get_underlying_from_option_data;
    use carmine_protocol::amm_core::helpers::fromU256_balance;
    use carmine_protocol::amm_core::helpers::split_option_locked_capital;

    use carmine_protocol::amm_core::constants::OPTION_CALL;
    use carmine_protocol::amm_core::constants::OPTION_PUT;
    use carmine_protocol::amm_core::constants::TRADE_SIDE_LONG;
    use carmine_protocol::amm_core::constants::TRADE_SIDE_SHORT;


    // @notice Retrieves the value of a single position, independent of the holder.
    // @param option: Struct containing option definition data
    // @param position_size: Size of the position, in of Int(u128)
    // @return position_value: Value of the position in terms of Fixed
    fn get_value_of_position(option: Option_, position_size: Int) -> Fixed {
        option.value_of_position(position_size)
    }


    // @notice Retrieves the value of the position within the pool
    // @dev Returns a total value of pools position (sum of value of all options held by pool, even the matured ones).
    // @dev Used in get_lptokens_for_underlying, which is why it isn't in view.cairo.
    // @param lptoken_address: Address of the liquidity pool token
    // @return res: Value of the position within specified liquidity pool
    fn get_value_of_pool_position(lptoken_address: LPTAddress) -> Fixed {
        let non_expired = get_value_of_pool_non_expired_position(lptoken_address);
        let expired = get_value_of_pool_expired_position(lptoken_address);
        non_expired + expired
    }

    // @notice Retrieves the value of the non expired position within the pool
    // @dev Returns a total value of pools non expired position (sum of value of all options held by pool).
    // @dev Goes through all options in storage var "available_options"... is able to iterate by i
    // @dev (from 0 to n)
    // @dev It gets 0 from available_option(n), if the n-1 is the "last" option.
    // @param lptoken_address: Address of the liquidity pool token
    // @return res: Value of the non_expired position within specified liquidity pool
    fn get_value_of_pool_non_expired_position(lptoken_address: LPTAddress) -> Fixed {
        let mut i: u32 = 0;
        let mut pool_pos: Fixed = FixedTrait::from_felt(0);
        let now = get_block_timestamp();

        loop {
            let option = get_available_options(lptoken_address, i);
            i += 1;

            if option.sum() == 0 {
                break;
            }

            let option_position = option.pools_position();
            if option_position == 0 {
                continue;
            }

            if option.maturity < now {
                // Option is expired
                continue;
            }

            pool_pos += option.value_of_position(option_position);
        };

        return pool_pos;
    }

    // @notice Retrieves the value of the expired position within the pool
    // @dev Returns a total value of pools non expired position.
    // @dev Walks backwards (iteration starts from last index) all options in storage var "available_options" 
    // @dev     that expired in last 8 weeks
    // @param lptoken_address: Address of the liquidity pool token
    // @return res: Value of the expired position within specified liquidity pool
    fn get_value_of_pool_expired_position(lptoken_address: LPTAddress) -> Fixed {
        let LOOKBACK = 24 * 3600 * 7 * 8;
        // ^ Only look back 8 weeks, all options should be long expired by then
        let now = get_block_timestamp();
        let last_ix = get_available_options_usable_index(lptoken_address);

        if last_ix == 0 {
            return FixedTrait::ZERO();
        }

        let mut ix = last_ix - 1;
        let mut pool_pos: Fixed = FixedTrait::from_felt(0);

        loop {

            // Get option stored under given index
            let option = get_available_options(lptoken_address, ix);
            assert(option.sum() != 0, 'GVoEO - opt sum zero');

            // This function only calculates value of expired position, 
            // so if maturity is in the future just decrease the index
            // for next iteration and continue
            if (option.maturity >= now) {
                // ix = 0 means there are no more options to consider
                // so break the loop
                if ix == 0 {
                    break;
                }

                // We're not at the end (beginning) of array 
                // so decrease index and continue
                ix -= 1;
                continue; 
            };

            if (now - option.maturity) > LOOKBACK {
                // We're over lookback window so break the loop
                break;
            };

            // Get pool's position in given option
            let option_position = option.pools_position();

            // Add value of the given position
            pool_pos += option.value_of_position(option_position);

            // ix = 0 means there are no more options to consider
            // so break the loop
            if ix == 0 {
                break;
            }

            // Decrease ix for next iteration
            ix -= 1;
        };

        pool_pos
    }


    // # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
    // Provide/remove liquidity
    // # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

    // @notice Calculates how many LP tokens correspond to the given amount of underlying token
    // @dev Quote or base tokens are used based on the pool being put/call
    // @param lptoken_address: Address of the liquidity pool token
    // @param underlying_amt: Amount of underlying tokens, in Uint256!!!
    // @return lpt_amt: How many LP tokens correspond to the given amount of underlying token in u256
    fn get_lptokens_for_underlying(lptoken_address: LPTAddress, underlying_amt: u256) -> u256 {
        let free_capital = get_unlocked_capital(lptoken_address);
        let currency_address = get_underlying_token_address(lptoken_address);
        let value_of_position_cubit = get_value_of_pool_position(lptoken_address);
        let value_of_position_u256 = toU256_balance(value_of_position_cubit, currency_address);

        let value_of_pool = free_capital + value_of_position_u256;

        if value_of_pool == 0 {
            return underlying_amt;
        }

        let lpt_supply = IERC20Dispatcher { contract_address: lptoken_address }.totalSupply();
        let (q, r) = U256DivRem::div_rem(
            lpt_supply, value_of_pool.try_into().expect('Div by zero in GLfU')
        );
        let to_mint = q * underlying_amt;

        let to_div = r * underlying_amt;

        let (to_mint_additional_q, _) = U256DivRem::div_rem(
            to_div, value_of_pool.try_into().expect('Div by zero in GLfU')
        );

        to_mint_additional_q + to_mint
    }

    // @notice Computes the amount of underlying token that corresponds to a given amount of LP token
    // @dev Doesn't take into account whether this underlying is actually free to be withdrawn.
    // @dev computes this essentially: my_underlying = (total_underlying/total_lpt)*my_lpt
    // @dev notation used: ... = (a)*my_lpt = b
    // @param lptoken_address: Address of the liquidity pool token
    // @param lpt_amt: Amount of liquidity pool tokens, in Uint256!!!
    // @return underlying_amt: Amount of underlying token that correspond to the given amount of
    //      LP token, in u256
    fn get_underlying_for_lptokens(lptoken_address: LPTAddress, lpt_amt: u256) -> u256 {
        let lpt_supply = IERC20Dispatcher { contract_address: lptoken_address }.totalSupply();
        let free_capital = get_unlocked_capital(lptoken_address);

        let value_of_position_cubit = get_value_of_pool_position(lptoken_address);
        let currency_address = get_underlying_token_address(lptoken_address);
        let value_of_position = toU256_balance(value_of_position_cubit, currency_address);

        let total_underlying_amt = free_capital + value_of_position;

        let (aq, ar) = U256DivRem::div_rem(
            total_underlying_amt, lpt_supply.try_into().expect('Div by zero in GUfL')
        );
        let b = aq * lpt_amt;
        let tmp = ar * lpt_amt;

        let (to_burn_addition_q, _) = U256DivRem::div_rem(
            tmp, lpt_supply.try_into().expect('Div by zero in GUfL')
        );

        to_burn_addition_q + b
    }


    // @notice Adds a new liqudity pool through registering LP token in the AMM.
    // @dev This function initializes new pool
    // @param quote_token_address: Address of the quote token (USDC in ETH/USDC)
    // @param base_token_address: Address of the base token (ETH in ETH/USDC)
    // @param option_type: Type of the option 0 for Call, 1 for Put
    // @param lptoken_address: Address of the liquidity pool token
    // @param pooled_token_addr: Address of the pooled token
    // @param volatility_adjustment_speed: Constant that determines how fast the volatility is changing
    // @param max_lpool_bal: Maximum balance of the bool for given pooled token
    fn add_lptoken(
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        option_type: OptionType,
        lptoken_address: LPTAddress,
        pooled_token_addr: LPTAddress,
        volatility_adjustment_speed: Fixed,
        max_lpool_bal: u256
    ) {
        assert_option_type_exists(option_type.into(), 'Unknown option type');

        fail_if_existing_pool_definition_from_lptoken_address(lptoken_address);
        // Check that base/quote token even exists - use total supply for now I guess

        let supply_base = IERC20Dispatcher { contract_address: base_token_address }.totalSupply();
        let supply_quote = IERC20Dispatcher { contract_address: quote_token_address }.totalSupply();

        assert(supply_base > 0, 'Base token supply <= 0');
        assert(supply_quote > 0, 'Quote token supply <= 0');

        append_to_available_lptoken_addresses(lptoken_address);

        set_lptoken_address_for_given_option(
            quote_token_address, base_token_address, option_type, lptoken_address
        );

        let pool = Pool { quote_token_address, base_token_address, option_type, };
        set_pool_definition_from_lptoken_address(lptoken_address, pool);

        if option_type == OPTION_CALL {
            set_underlying_token_address(lptoken_address, base_token_address);
        } else {
            set_underlying_token_address(lptoken_address, quote_token_address);
        }

        // Assert that the tokens has not been minted yet - it should be brand new one
        let supply_lpt = IERC20Dispatcher { contract_address: lptoken_address }.totalSupply();
        assert(supply_lpt == 0, 'LPT minted != 0');

        set_pool_volatility_adjustment_speed(lptoken_address, volatility_adjustment_speed);
        set_max_lpool_balance(lptoken_address, max_lpool_bal);
    }


    // @notice Mints LP tokens and deposits liquidity into the LP
    // @dev Assumes the underlying token is already approved (directly call approve() on the token being
    // @dev deposited to allow this contract to claim them)
    // @param pooled_token_addr: Address that should correspond to the underlying token address of the pool
    // @param quote_token_address: Address of the quote token (USDC in ETH/USDC)
    // @param base_token_address: Address of the base token (ETH in ETH/USDC)
    // @param option_type: Type of the option 0 for Call, 1 for Put
    // @param amount: Amount of underlying token to deposit - in u256
    fn deposit_liquidity(
        pooled_token_address: ContractAddress,
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        option_type: OptionType,
        amount: u256
    ) {
        assert(amount > 0, 'Amount <= 0');
        assert(!pooled_token_address.is_zero(), 'pooled_token_addr is zero');
        assert(!base_token_address.is_zero(), 'base_token_addr is zero');
        assert(!quote_token_address.is_zero(), 'quote_token_addr is zero');

        let caller_addr = get_caller_address();
        let own_addr = get_contract_address();

        assert(!caller_addr.is_zero(), 'Caller address is zero');
        assert(!own_addr.is_zero(), 'Own address is zero');

        let lptoken_address = get_lptoken_address_for_given_option(
            quote_token_address, base_token_address, option_type
        );

        let underlying_token_address = get_underlying_from_option_data(
            option_type, base_token_address, quote_token_address
        );
        assert(underlying_token_address == pooled_token_address, 'Pooled doesnt match underlying');

        let mint_amount = get_lptokens_for_underlying(lptoken_address, amount);

        emit_event(
            DepositLiquidity {
                caller: caller_addr,
                lp_token: lptoken_address,
                capital_transfered: amount,
                lp_tokens_minted: mint_amount,
            }
        );

        // Update the lpool_balance after the mint_amount has been computed
        // (get_lptokens_for_underlying uses lpool_balance)
        let current_balance = get_lpool_balance(lptoken_address);
        let new_balance = current_balance + amount;
        set_lpool_balance(lptoken_address, new_balance);

        let max_balance = get_max_lpool_balance(lptoken_address);

        assert(new_balance <= max_balance, 'Lpool bal exceeds maximum');

        IERC20Dispatcher { contract_address: lptoken_address }.mint(caller_addr, mint_amount);

        IERC20Dispatcher { contract_address: pooled_token_address }
            .transferFrom(caller_addr, own_addr, amount);
    }

    // @notice Withdraw liquidity from the LP
    // @dev Withdraws liquidity only if there is enough available liquidity (ie enough unlocked
    //      capital). If that is not the case the transaction fails.
    // @param pooled_token_addr: Address that should correspond to the underlying token address of the pool
    // @param quote_token_address: Address of the quote token (USDC in ETH/USDC)
    // @param base_token_address: Address of the base token (ETH in ETH/USDC)
    // @param option_type: Type of the option 0 for Call, 1 for Put
    // @param lp_token_amount: LP token amount in terms of LP tokens, not underlying tokens
    //       as in deposit_liquidity
    fn withdraw_liquidity(
        pooled_token_address: ContractAddress,
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        option_type: OptionType,
        lp_token_amount: u256
    ) {
        let caller_addr = get_caller_address();

        assert(!caller_addr.is_zero(), 'Caller address is zero');

        let lptoken_address = get_lptoken_address_for_given_option(
            quote_token_address, base_token_address, option_type
        );

        assert(lp_token_amount > 0, 'LP token amt <= 0');
        let underlying_token_address = get_underlying_from_option_data(
            option_type, base_token_address, quote_token_address
        );
        assert(underlying_token_address == pooled_token_address, 'Pooled doesnt match underlying');

        let underlying_amount = get_underlying_for_lptokens(lptoken_address, lp_token_amount);

        let free_capital = get_unlocked_capital(lptoken_address);

        assert(underlying_amount <= free_capital, 'Not enough capital');
        assert(free_capital != 0, 'Free capital is zero');

        emit_event(
            WithdrawLiquidity {
                caller: caller_addr,
                lp_token: lptoken_address,
                capital_transfered: underlying_amount,
                lp_tokens_burned: lp_token_amount,
            }
        );

        let current_balance = get_lpool_balance(lptoken_address);
        let unlocked_capital = get_unlocked_capital(lptoken_address);
        let new_balance = current_balance - underlying_amount;

        set_lpool_balance(lptoken_address, new_balance);

        IERC20Dispatcher { contract_address: pooled_token_address }
            .transfer(caller_addr, underlying_amount);

        IERC20Dispatcher { contract_address: lptoken_address }.burn(caller_addr, lp_token_amount);
    }


    // @notice Helper function for expiring pool's options.
    // @dev It basically adjusts the internal state of the AMM.
    // @param lptoken_address: Address of the LP token
    // @param long_value: Pool's long position
    // @param short_value: Pool's short position
    // @param option_size: Size of the position
    // @param option_side: Option's side from the perspective of the pool
    // @param maturity: Option's maturity
    // @param strike_price: Option's strike price
    fn adjust_lpool_balance_and_pool_locked_capital_expired_options(
        lptoken_address: ContractAddress,
        long_value: u256,
        short_value: u256,
        option_size: Int,
        option_side: OptionSide,
        maturity: Timestamp,
        strike_price: Fixed
    ) {
        let current_lpool_balance = get_lpool_balance(lptoken_address);
        let current_locked_balance = get_pool_locked_capital(lptoken_address);

        if option_side == TRADE_SIDE_LONG {
            // Pool is LONG
            // Capital locked by user(s)
            // Increase lpool_balance by long_value, since pool either made profit (profit >=0).
            //      The cost (premium) was paid before.
            // Nothing locked by pool -> locked capital not affected
            // Unlocked capital should increas by profit from long option, in total:
            //      Unlocked capital = lpool_balance - pool_locked_capital
            //      diff_capital = diff_lpool_balance - diff_pool_locked
            //      diff_capital = long_value - 0
            let new_lpool_balance = current_lpool_balance + long_value;
            set_lpool_balance(lptoken_address, new_lpool_balance);
        } else {
            // Pool is SHORT
            // Decrease the lpool_balance by the long_value.
            //      The extraction of long_value might have not happened yet from transacting the tokens.
            //      But from perspective of accounting it is happening now.
            //          -> diff lpool_balance = -long_value
            // Decrease the pool_locked_capital by the locked capital. Locked capital for this option
            // (option_size * strike in terms of pool's currency (ETH vs USD))
            //          -> locked capital = long_value + short_value
            //          -> diff pool_locked_capital = - locked capital
            //      You may ask why not just the short_value. That is because the total capital
            //      (locked + unlocked) is decreased by long_value as in the point above (loss from short).
            //      The unlocked capital is increased by short_value - what gets returned from locked.
            //      To check the math
            //          -> lpool_balance = pool_locked_capital + unlocked
            //          -> diff lpool_balance = diff pool_locked_capital + diff unlocked
            //          -> -long_value = -locked capital + short_value
            //          -> -long_value = -(long_value + short_value) + short_value
            //          -> -long_value = -long_value - short_value + short_value
            //          -> -long_value +long_value = - short_value + short_value
            //          -> 0=0
            // The long value is left in the pool for the long owner to collect it.

            assert(current_lpool_balance >= long_value, 'ALBPLCEO - curr bal < long val');
            let new_lpool_balance = current_lpool_balance - long_value;
            // Substracting the combination of long and short rather than separately because of rounding error
            // More specifically transfering the combo to uint256 rather than separate values because
            // of the rounding error

            let long_plus_short_value = long_value + short_value;

            assert(
                current_locked_balance >= long_plus_short_value, 'ALBPLCEO - currlock < longshort'
            );
            let new_locked_balance = current_locked_balance - long_plus_short_value;

            set_lpool_balance(lptoken_address, new_lpool_balance);
            set_pool_locked_capital(lptoken_address, new_locked_balance);
        }
    }

    // @notice Expires option token but only for pool.
    // @dev First pool's position has to be expired, before any user's position is expired (settled).
    // @param lptoken_address: Address of the LP token
    // @param option_side: Option's side from the perspective of the pool
    // @param strike_price: Option's strike price
    // @param maturity: Option's maturity
    fn expire_option_token_for_pool(
        lptoken_address: ContractAddress,
        option_side: OptionSide,
        strike_price: Fixed,
        maturity: Timestamp,
    ) {
        emit_event(
            ExpireOptionTokenForPool {
                lptoken_address: lptoken_address,
                option_side: option_side,
                strike_price: strike_price,
                maturity: maturity,
            }
        );

        let option = get_option_info(lptoken_address, option_side, strike_price, maturity,);
        let option_size = get_option_position(lptoken_address, option_side, maturity, strike_price);

        if option_size == 0 {
            return;
        }

        let current_block_time = get_block_timestamp();

        assert(maturity <= current_block_time, 'Option not expired');

        // Get terminal price of the option
        let terminal_price = get_terminal_price(
            option.quote_token_address, option.base_token_address, maturity
        );

        let option_size_cubit = fromU256_balance(option_size.into(), option.base_token_address);

        let (long_value, short_value) = split_option_locked_capital(
            option.option_type, option_size_cubit, strike_price, terminal_price
        );

        let lpool_underlying_token = get_underlying_token_address(lptoken_address);
        let long_value = toU256_balance(long_value, lpool_underlying_token);
        let short_value = toU256_balance(short_value, lpool_underlying_token);

        adjust_lpool_balance_and_pool_locked_capital_expired_options(
            lptoken_address,
            long_value,
            short_value,
            option_size,
            option_side,
            maturity,
            strike_price
        );

        let current_pool_position = get_option_position(
            lptoken_address, option_side, maturity, strike_price
        );

        let new_pool_position = current_pool_position - option_size;

        let opt_size_u256: u256 = option_size.into();

        assert(opt_size_u256 <= current_pool_position.into(), 'Opt size > curr pool pos');

        set_option_position(lptoken_address, option_side, maturity, strike_price, 0);
    }
}
