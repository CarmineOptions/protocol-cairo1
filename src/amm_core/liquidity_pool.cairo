mod LiquidityPool {
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use starknet::info::get_contract_address;
    use starknet::get_block_timestamp;

    use starknet::contract_address::{
        contract_address_to_felt252, contract_address_try_from_felt252
    };
    use traits::{Into, TryInto};
    use option::OptionTrait;
    use cubit::f128::types::fixed::{Fixed, FixedTrait};
    use integer::U256DivRem;

    use carmine_protocol::traits::{IERC20Dispatcher, IERC20DispatcherTrait};

    use carmine_protocol::types::basic::{LPTAddress, OptionType, OptionSide, Int, Timestamp};
    use carmine_protocol::types::option_::{Option_, Option_Trait};
    use carmine_protocol::types::pool::{Pool};


    use carmine_protocol::amm_core::amm::AMM::{
        DepositLiquidity, WithdrawLiquidity, ExpireOptionTokenForPool, emit_event
    };

    use carmine_protocol::amm_core::oracles::agg::OracleAgg::get_terminal_price;

    use carmine_protocol::amm_core::state::State::{
        get_available_options, get_option_position, get_option_volatility,
        get_lptoken_address_for_given_option, get_pool_volatility_adjustment_speed,
        get_unlocked_capital, get_underlying_token_address,
        fail_if_existing_pool_definition_from_lptoken_address,
        append_to_available_lptoken_addresses, set_lptoken_address_for_given_option,
        set_pool_definition_from_lptoken_address, set_underlying_token_address,
        set_pool_volatility_adjustment_speed, set_max_lpool_balance, get_lpool_balance,
        set_lpool_balance, get_max_lpool_balance, get_pool_locked_capital, set_pool_locked_capital,
        get_option_info, set_option_position
    };

    use carmine_protocol::amm_core::helpers::{
        toU256_balance, assert_option_type_exists, assert_address_not_zero,
        get_underlying_from_option_data, fromU256_balance, split_option_locked_capital
    };

    use carmine_protocol::amm_core::constants::{
        OPTION_CALL, OPTION_PUT, TRADE_SIDE_LONG, TRADE_SIDE_SHORT
    };

    fn get_value_of_position(
        option: Option_, position_size: Int
    ) -> Fixed {
        option.value_of_position(position_size)
    }

    fn get_value_of_pool_position(lptoken_address: LPTAddress) -> Fixed {
        let mut i: u32 = 0;
        let mut pool_pos: Fixed = FixedTrait::from_felt(0);

        loop {
            let option = get_available_options(lptoken_address, i);

            if option.sum() == 0 {
                break;
            }
            i += 1;

            let option_position = option.pools_position();
            if option_position == 0 {
                continue;
            }

            pool_pos += option.value_of_position(option_position);
        };

        return pool_pos;
    }


    // # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
    // Provide/remove liquidity
    // # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
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

    fn add_lptoken(
        quote_token_address: LPTAddress,
        base_token_address: LPTAddress,
        option_type: OptionType,
        lptoken_address: LPTAddress,
        pooled_token_addr: LPTAddress,
        volatility_adjustment_speed: Fixed,
        max_lpool_bal: u256
    ) {
        // TODO: Proxy.assrt_only_admin()

        assert_option_type_exists(option_type, 'Unknown option type');

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

        let pool = Pool { quote_token_address, base_token_address, option_type,  };
        set_pool_definition_from_lptoken_address(lptoken_address, pool);

        if option_type == OPTION_CALL {
            set_underlying_token_address(lptoken_address, base_token_address);
        } else {
            set_underlying_token_address(lptoken_address, quote_token_address);
        }

        set_pool_volatility_adjustment_speed(lptoken_address, volatility_adjustment_speed);
        set_max_lpool_balance(lptoken_address, max_lpool_bal);
    }

    fn deposit_liquidity(
        pooled_token_address: ContractAddress,
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        option_type: OptionType,
        amount: u256
    ) {
        // TODO: ReentrancyGuard.start()

        assert(amount > 0, 'Amount <= 0');
        assert_address_not_zero(pooled_token_address, 'pooled_token_addr is zero');
        assert_address_not_zero(base_token_address, 'base_token_addr is zero');
        assert_address_not_zero(quote_token_address, 'quote_token_addr is zero');

        let caller_addr = get_caller_address();
        let own_addr = get_contract_address();

        assert_address_not_zero(caller_addr, 'Caller address is zero');
        assert_address_not_zero(own_addr, 'Own address is zero');

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

        assert(current_balance <= max_balance, 'Lpool bal exceeds maximum');

        IERC20Dispatcher { contract_address: lptoken_address }.mint(caller_addr, mint_amount);

        IERC20Dispatcher {
            contract_address: pooled_token_address
        }.transferFrom(caller_addr, own_addr, amount);
    // TODO: reentrancyGuard.end()
    }

    fn withdraw_liquidity(
        pooled_token_address: ContractAddress,
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        option_type: OptionType,
        lp_token_amount: u256
    ) {
        // TODO: ReentrancyGuard.start();

        let caller_addr = get_caller_address();

        assert_address_not_zero(caller_addr, 'Caller address is zero');

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

        IERC20Dispatcher {
            contract_address: pooled_token_address
        }.transfer(caller_addr, underlying_amount);

        IERC20Dispatcher { contract_address: lptoken_address }.burn(caller_addr, lp_token_amount);
    // TODO: ReentrancyGuard.end();
    }


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

            assert(new_lpool_balance >= 0, 'Not enough lpool bal');
            assert(new_locked_balance >= 0, 'Not enough locked bal');

            set_lpool_balance(lptoken_address, new_lpool_balance);
            set_pool_locked_capital(lptoken_address, new_locked_balance);
        }
    }

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

        let option = get_option_info(lptoken_address, option_side, strike_price, maturity, );
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
            option.option_type, option_side, option_size_cubit, strike_price, terminal_price
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

        assert(new_pool_position.into() > 0_u256, 'New pool pos negative');
        assert(opt_size_u256 <= current_pool_position.into(), 'Opt size > curr pool pos');

        set_option_position(lptoken_address, option_side, maturity, strike_price, 0);
    }
}
