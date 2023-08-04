mod Trading {
    use starknet::ContractAddress;
    use traits::{TryInto, Into};
    use carmine_protocol::types::{Math64x61_, OptionType, OptionSide, LPTAddress, Int};
    use carmine_protocol::amm_core::helpers::{toU256_balance, legacyMath_to_cubit, };
    use carmine_protocol::amm_core::fees::get_fees;
    use option::OptionTrait;
    use carmine_protocol::amm_core::state::State::{
        get_option_volatility, get_pool_volatility_adjustment_speed, set_option_volatility,
    };

    use carmine_protocol::amm_core::options::{mint_option_token, };

    use carmine_protocol::amm_core::constants::{
        RISK_FREE_RATE, TRADE_SIDE_LONG, TRADE_SIDE_SHORT,
    };
    use cubit::types::fixed::{Fixed, FixedTrait};
    use carmine_protocol::amm_core::option_pricing_helpers::{
        convert_amount_to_option_currency_from_base_uint256, get_new_volatility,
        get_time_till_maturity, select_and_adjust_premia, add_premia_fees,
    };
    use carmine_protocol::amm_core::helpers::{fromU256_balance, };

    use carmine_protocol::amm_core::oracles::agg::OracleAgg::{
        get_current_price, get_terminal_price,
    };

    use carmine_protocol::amm_core::option_pricing::{black_scholes, };


    fn do_trade(
        option_type: OptionType,
        strike_price: Fixed,
        maturity: Int,
        side: OptionSide,
        option_size: Int,
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        lptoken_address: LPTAddress,
        limit_total_premia: Fixed,
    ) -> Fixed {
        // TODO: ReentrancyGuard.start();

        // Helper Values
        let option_size_cubit = fromU256_balance(
            u256 {
                low: option_size.try_into().expect(''), high: 0
            }, // TODO: I guess this is ugly/add errmsg
            base_token_address
        );

        let opt_size_u256: u256 = u256 {
            low: option_size.try_into().expect('DT - opt size too big'), high: 0
        };

        let option_size_in_pool_currency = convert_amount_to_option_currency_from_base_uint256(
            opt_size_u256,
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
        let risk_free_rate = FixedTrait::from_felt(0);

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
            assert(limit_total_premia <= total_premia, 'Premia out of slippage bounds');
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

        // TODO: ReentrancyGuard.end()
        return premia;
    }
}
