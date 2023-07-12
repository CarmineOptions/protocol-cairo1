use core::traits::TryInto;

mod State {
    use starknet::ContractAddress;
    use traits::Into;
    use starknet::contract_address::contract_address_to_felt252;

    use cubit::types::fixed::{Fixed, FixedTrait};

    use carmine_protocol::amm_core::helpers::{
        legacyMath_to_cubit
    };
    
    use carmine_protocol::amm_core::constants::{
        SEPARATE_VOLATILITIES_FOR_DIFFERENT_STRIKES,
        VOLATILITY_LOWER_BOUND,
        VOLATILITY_UPPER_BOUND,   
        OPTION_CALL,
        OPTION_PUT
    };
    use carmine_protocol::amm_core::amm::AMM::{
        option_token_address,
        pool_volatility_separate,
        available_options,
        pool_volatility_adjustment_speed,
        max_option_size_percent_of_voladjspd,
        underlying_token_address,
        pool_definition_from_lptoken_address,
        lpool_balance_,
        option_position_,
        pool_locked_capital_
    };

    use carmine_protocol::amm_core::amm::AMM;

    use carmine_protocol::types::{
        LPTAddress,
        OptionSide,
        OptionType,
        Maturity,
        Math64x61_,
        Volatility,
        Strike,
        Option_,
        Int,
        Pool
    };

    fn get_option_token_address(
        lptoken_address: LPTAddress, 
        option_side: OptionSide, 
        maturity: Maturity, 
        strike_price: Math64x61_
    ) -> ContractAddress {

        let state = AMM::unsafe_new_contract_state();

        let option_token_addr = option_token_address::InternalContractStateTrait::read(
            @state.option_token_address,
            (lptoken_address, option_side, maturity, strike_price)
        );

        return option_token_addr;
    }

    // TODO: Maybe setters/getters could return true/false instead of failing?
    // so that we can raise the error in function that actually calls the setters/getters

    fn set_pool_volatility_separate(
        lptoken_address: LPTAddress,
        maturity: Maturity,
        strike_price: Strike,
        volatility: Volatility
    ) {
        let mut state = AMM::unsafe_new_contract_state();

        let vol_u: u256 = volatility.into();
        let vol_upper: u256 = (VOLATILITY_UPPER_BOUND - 1).into();
        let vol_lower: u256 = VOLATILITY_LOWER_BOUND.into();
        
        assert(SEPARATE_VOLATILITIES_FOR_DIFFERENT_STRIKES == 1, 'Unable to use separate vols');
        assert(vol_u < vol_upper, 'Volatility exceeds upper bound');
        assert(vol_u > vol_lower, 'Volatility below lower bound');

        pool_volatility_separate::InternalContractStateTrait::write(
            ref state.pool_volatility_separate,
            (lptoken_address, maturity, strike_price), 
            volatility
        );
    }

    fn append_to_available_options(
        option: Option_,
        lptoken_address: ContractAddress
    ) {

        let usable_index = get_available_options_usable_index(lptoken_address);
        let mut state = AMM::unsafe_new_contract_state();

        available_options::InternalContractStateTrait::write(
            ref state.available_options,
            (lptoken_address, usable_index), 
            option
        );
    }

    fn get_available_options_usable_index(lptoken_address: LPTAddress) -> felt252 {
        _get_available_option_usable_index(lptoken_address, 0)
    }

    fn _get_available_option_usable_index(lptoken_address: LPTAddress, idx: felt252) -> felt252 {
        let state = AMM::unsafe_new_contract_state();
        let option = available_options::InternalContractStateTrait::read(
            @state.available_options,
            (lptoken_address, idx)
        );

        // Because of how the defined options are stored we have to verify that we have not run
        // at the end of the stored values. The end is with "empty" Option.
        let opt_sum = option.maturity + option.strike_price;

        if opt_sum == 0 {
            idx
        } else {
            _get_available_option_usable_index(lptoken_address, idx + 1)
        }
    }


    fn get_pool_volatility_adjustment_speed(lptoken_address: LPTAddress) -> Fixed {
        let state = AMM::unsafe_new_contract_state();
        let res = pool_volatility_adjustment_speed::InternalContractStateTrait::read(
            @state.pool_volatility_adjustment_speed,
            lptoken_address
        );
        assert(res != 0, 'Pool vol adj spd is 0');
        assert(res.into() > 0_u256, 'Pool vol adj spd negative');

        legacyMath_to_cubit(res)
    }

    fn get_max_option_size_percent_of_voladjspd() -> Int {
        let state = AMM::unsafe_new_contract_state();
        max_option_size_percent_of_voladjspd::InternalContractStateTrait::read(
            @state.max_option_size_percent_of_voladjspd
        )
    }

    // @notice Returns the token that's underlying the given liquidity pool.
    fn get_underlying_token_address(lptoken_address: LPTAddress) -> ContractAddress {
        let state = AMM::unsafe_new_contract_state();
        let underlying_token_address_ = underlying_token_address::InternalContractStateTrait::read(
            @state.underlying_token_address,
            lptoken_address
        );

        assert(contract_address_to_felt252(underlying_token_address_) != 0, 'Underlying addr is zero');

        return underlying_token_address_;
    }


    fn get_pool_definition_from_lptoken_address(lptoken_address: LPTAddress) -> Pool {
        let state = AMM::unsafe_new_contract_state();
        let pool = pool_definition_from_lptoken_address::InternalContractStateTrait::read(
            @state.pool_definition_from_lptoken_address,
            lptoken_address
        );

        assert(contract_address_to_felt252(pool.quote_token_address) != 0, 'Quote addr doesnt exist');
        assert(contract_address_to_felt252(pool.base_token_address) != 0, 'Quote addr doesnt exist');
        assert((pool.option_type - OPTION_CALL) * (pool.option_type - OPTION_PUT) == 0, 'Unknown option type');

        return pool;
    }

    fn get_lpool_balance(lptoken_address: LPTAddress) -> u256 {
        let state = AMM::unsafe_new_contract_state();
        lpool_balance_::InternalContractStateTrait::read(
            @state.lpool_balance_,
            lptoken_address
        )
    }

    fn set_lpool_balance(lptoken_address: LPTAddress, balance: u256) {
        assert(balance >= 0, 'lpool_balance negative');

        let mut state = AMM::unsafe_new_contract_state();
        lpool_balance_::InternalContractStateTrait::write(
            ref state.lpool_balance_,
            lptoken_address,
            balance
        )
    }

    fn get_option_position(
        lptoken_address: LPTAddress,
        option_side: OptionSide,
        maturity: Maturity,
        strike_price: Math64x61_
    ) -> Int {
        let state = AMM::unsafe_new_contract_state();
        option_position_::InternalContractStateTrait::read(
            @state.option_position_,
            (lptoken_address, option_side, maturity, strike_price)
        )       
    }

    fn set_option_position(
        lptoken_address: LPTAddress,
        option_side: OptionSide,
        maturity: Int,
        strike_price: Math64x61_,
        position: Int
    ) {
        assert(strike_price.into() > 0_u256, 'Strike zero/neg in set_opt_pos');
        assert(position.into() > 0_u256, 'Pos zero/neg in set_opt_pos');

        let mut state = AMM::unsafe_new_contract_state();
        option_position_::InternalContractStateTrait::write(
            ref state.option_position_,
            (lptoken_address, option_side, maturity, strike_price),
            position
        )       
    }

    fn get_pool_locked_capital(lptoken_address: LPTAddress) -> u256 {
        let state = AMM::unsafe_new_contract_state();
        pool_locked_capital_::InternalContractStateTrait::read(
            @state.pool_locked_capital_,
            lptoken_address
        )
    }

    fn get_unlocked_capital(lptoken_address: LPTAddress) -> u256 {
        let state = AMM::unsafe_new_contract_state();

        // Capital locked by the pool
        let locked_capital = get_pool_locked_capital(lptoken_address);

        // Get capital that is sum of unlocked (available) and locked capital.
        let contract_balance = get_lpool_balance(lptoken_address);

        return contract_balance - locked_capital;
        
    }

    fn set_pool_locked_capital(lptoken_address: LPTAddress, balance: u256) {
        assert(balance >= 0, 'Balance negative in set locked');

        let mut state = AMM::unsafe_new_contract_state();
        pool_locked_capital_::InternalContractStateTrait::write(
            ref state.pool_locked_capital_,
            lptoken_address,
            balance
        )
    }

}