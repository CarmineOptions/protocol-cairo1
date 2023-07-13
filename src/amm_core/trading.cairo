
mod Trading {
    use starknet::ContractAddress;
    use traits::{TryInto, Into};
    use carmine_protocol::types::{
        Math64x61_,
        OptionType,
        OptionSide,
        LPTAddress,
        Int
    };
    use carmine_protocol::amm_core::helpers::{
        toU256_balance,
        legacyMath_to_cubit,
    };

    use carmine_protocol::amm_core::option_pricing_helpers::{
        convert_amount_to_option_currency_from_base_uint256
    };

    fn do_trade(
        option_type: OptionType,
        strike_price: Math64x61_,
        maturity: Int,
        side: OptionSide,
        option_size: Int,
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        lptoken_address: LPTAddress,
        limit_total_premia: Math64x61_,
    ) -> Math64x61_ {
        // TODO: ReentrancyGuard.start();
        let option_size_u256: u256 = option_size.into();
        let strike_price_u256 = toU256_balance(
            legacyMath_to_cubit(strike_price), quote_token_address
        );
        let option_size_in_pool_currency = convert_amount_to_option_currency_from_base_uint256(
            option_size_u256,
            option_type,
            strike_price_u256,
            base_token_address
        );

        // 1) Get current volatility
        // let current_volatility = get_pool_volatility_auto(
        //     lptoken_address=lptoken_address,
        //     maturity=maturity,
        //     strike_price=strike_price
        // );
        
        1
    }





}