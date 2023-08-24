mod State {
    use starknet::ContractAddress;
    use traits::{Into, TryInto};
    use starknet::contract_address::{
        contract_address_to_felt252, contract_address_try_from_felt252
    };
    use core::option::OptionTrait;

    use cubit::f128::types::fixed::{Fixed, FixedTrait};

    use carmine_protocol::amm_core::helpers::{
        assert_option_side_exists, assert_option_type_exists, assert_address_not_zero,
        FixedHelpersTrait
    };

    use carmine_protocol::amm_core::constants::{OPTION_CALL, OPTION_PUT};
    use carmine_protocol::amm_core::amm::AMM::{
        pool_volatility_separate, option_volatility, pool_volatility_adjustment_speed,
        new_pool_volatility_adjustment_speed, option_position_, new_option_position,
        option_token_address, new_option_token_address, available_options, new_available_options,
        new_available_options_usable_index, max_lpool_balance, lptoken_addr_for_given_pooled_token,
        trading_halted, available_lptoken_adresses, max_option_size_percent_of_voladjspd,
        underlying_token_address, pool_definition_from_lptoken_address, lpool_balance_,
        pool_locked_capital_
    };

    use carmine_protocol::amm_core::amm::AMM;

    use carmine_protocol::types::basic::{
        LPTAddress, OptionSide, OptionType, Math64x61_, LegacyVolatility, LegacyStrike, Volatility,
        Strike, Int, Timestamp
    };

    use carmine_protocol::types::pool::{Pool};
    use carmine_protocol::types::option_::{
        LegacyOption, Option_, LegacyOption_to_Option, Option_to_LegacyOption, Option_Trait
    };

    fn set_option_token_address(
        lptoken_address: LPTAddress,
        option_side: OptionSide,
        maturity: Timestamp,
        strike_price: Strike,
        opt_address: ContractAddress
    ) {
        let mut state = AMM::unsafe_new_contract_state();

        assert_option_side_exists(option_side.into(), 'SOTA - opt side 0');
        assert(contract_address_to_felt252(lptoken_address) != 0, 'SOTE - lpt addr 0');
        assert(maturity > 0, 'SOTA - maturity <= 0');
        strike_price.assert_nn_not_zero('sota - maturity <= 0');
        assert(contract_address_to_felt252(opt_address) != 0, 'SOTE - opt addr 0');

        // Set old storage var to zero in case this function get called before the getter
        // option_token_address::InternalContractStateTrait::write(
        option_token_address::InternalContractStateTrait::write(
            ref state.option_token_address,
            (lptoken_address, option_side, maturity.into(), strike_price.to_legacyMath()),
            contract_address_try_from_felt252(0).unwrap()
        );

        new_option_token_address::InternalContractStateTrait::write(
            ref state.new_option_token_address,
            (lptoken_address, option_side, maturity, strike_price.mag),
            opt_address
        );
    }

    fn get_option_token_address(
        lptoken_address: LPTAddress,
        option_side: OptionSide,
        maturity: Timestamp,
        strike_price: Strike
    ) -> ContractAddress {
        let mut state = AMM::unsafe_new_contract_state();

        // First read the old value
        let option_token_addr = option_token_address::InternalContractStateTrait::read(
            @state.option_token_address,
            (lptoken_address, option_side, maturity.into(), strike_price.to_legacyMath())
        );

        if contract_address_to_felt252(option_token_addr) != 0 {
            // Write value to new storage var
            set_option_token_address(
                lptoken_address, option_side, maturity, strike_price, option_token_addr
            );

            // Set old storage var to zero
            option_token_address::InternalContractStateTrait::write(
                ref state.option_token_address,
                (lptoken_address, option_side, maturity.into(), strike_price.to_legacyMath()),
                contract_address_try_from_felt252(0).expect('Cannot create addr from 0')
            );

            return option_token_addr;
        }

        // Read from new storage var
        let res = new_option_token_address::InternalContractStateTrait::read(
            @state.new_option_token_address,
            (lptoken_address, option_side, maturity, strike_price.mag)
        );

        return res;
    }

    // TODO: Maybe setters/getters could return true/false instead of failing?
    // so that we can raise the error in function that actually calls the setters/getters

    fn set_option_volatility(
        lptoken_address: LPTAddress,
        maturity: Timestamp,
        strike_price: Strike,
        volatility: Volatility
    ) {
        let mut state = AMM::unsafe_new_contract_state();

        // let volatility = cubit_to_legacyMath(volatility);
        // let strike_price = cubit_to_legacyMath(strike_price);

        // let vol_u: u256 = volatility.into();
        // let vol_upper: u256 = (VOLATILITY_UPPER_BOUND - 1).into();
        // let vol_lower: u256 = VOLATILITY_LOWER_BOUND.into();

        // TODO: Use checks below       
        // assert(SEPARATE_VOLATILITIES_FOR_DIFFERENT_STRIKES == 1, 'Unable to use separate vols');
        // assert(vol_u < vol_upper, 'Volatility exceeds upper bound');
        // assert(vol_u > vol_lower, 'Volatility below lower bound');

        // Set old storage var to zero in case this function get called before the getter
        pool_volatility_separate::InternalContractStateTrait::write(
            ref state.pool_volatility_separate,
            (lptoken_address, maturity.into(), strike_price.to_legacyMath()),
            0
        );

        option_volatility::InternalContractStateTrait::write(
            ref state.option_volatility,
            (lptoken_address, maturity.into(), strike_price.mag),
            volatility
        );
    }

    fn get_option_volatility(
        lptoken_address: LPTAddress, maturity: Timestamp, strike_price: Strike, 
    ) -> Volatility {
        let mut state = AMM::unsafe_new_contract_state();

        // First let's try to read from the old storage var
        let res = pool_volatility_separate::InternalContractStateTrait::read(
            @state.pool_volatility_separate,
            (lptoken_address, maturity.into(), strike_price.to_legacyMath())
        );

        if res != 0 {
            // First assert it's not negative
            assert(res.into() > 0_u256, 'Old opt vol adj spd negative');

            // If it's not zero then move the old value to new storage var and set the old one to zero

            let res_cubit = FixedHelpersTrait::from_legacyMath(res);

            // Write old value to new storage var
            set_option_volatility(lptoken_address, maturity, strike_price, res_cubit);

            // Set old value to zero
            pool_volatility_separate::InternalContractStateTrait::write(
                ref state.pool_volatility_separate,
                (lptoken_address, maturity.into(), strike_price.to_legacyMath()),
                0
            );

            return res_cubit;
        }

        // If value in old storage var was zero then we can try to read from new storage var
        let res = option_volatility::InternalContractStateTrait::read(
            @state.option_volatility, (lptoken_address, maturity.into(), strike_price.mag)
        );

        res.assert_nn_not_zero('Opt vol <= 0');

        return res;
    }

    // TODO: finish function below
    fn get_available_options(lptoken_address: LPTAddress, idx: u32) -> Option_ {
        let state = AMM::unsafe_new_contract_state();

        // In case this function is called before append_to_available_options
        let usable_index = new_available_options_usable_index::InternalContractStateTrait::read(
            @state.new_available_options_usable_index
        );
        if usable_index == 0 {
            let idx = migrate_old_options(lptoken_address, 0);
        }

        new_available_options::InternalContractStateTrait::read(
            @state.new_available_options, (lptoken_address, idx)
        )
    }

    fn append_to_available_options(option: Option_, lptoken_address: LPTAddress) {
        let mut state = AMM::unsafe_new_contract_state();

        // Read storage var containg the usable index
        let usable_index = new_available_options_usable_index::InternalContractStateTrait::read(
            @state.new_available_options_usable_index
        );

        // In this case we need to migrate the old options to the new storage var
        // since this storage var was introduced and is used only in c1 version
        if usable_index == 0 {
            let usable_index = migrate_old_options(lptoken_address, 0);
        }

        new_available_options::InternalContractStateTrait::write(
            ref state.new_available_options, (lptoken_address, usable_index), option
        );

        // Increase the usable index in available options
        new_available_options_usable_index::InternalContractStateTrait::write(
            ref state.new_available_options_usable_index, usable_index + 1
        );
    }

    // Migrates old options and returns first empty index
    fn migrate_old_options(lptoken_address: ContractAddress, idx: u32) -> u32 {
        let mut state = AMM::unsafe_new_contract_state();

        // Get old option at index
        let old_option = available_options::InternalContractStateTrait::read(
            @state.available_options, (lptoken_address, idx.into())
        );

        // This means we've reached the end of list, so return current index
        let option_sum = old_option.maturity + old_option.strike_price;
        if option_sum == 0 {
            return idx;
        }

        // Convert old option to new one and write at current index
        let new_option = LegacyOption_to_Option(old_option);
        new_available_options::InternalContractStateTrait::write(
            ref state.new_available_options, (lptoken_address, idx), new_option
        );

        // TODO: Should we alse set old option at current index to zero to "delete" it? 

        // Continue to the next index
        migrate_old_options(lptoken_address, idx + 1)
    }

    fn set_pool_volatility_adjustment_speed(lptoken_address: LPTAddress, new_speed: Fixed) {
        new_speed.assert_nn_not_zero('Pool vol adjspd cant <= 0');

        let mut state = AMM::unsafe_new_contract_state();

        // Set old storage var to zero in case this function gets called before the getter
        pool_volatility_adjustment_speed::InternalContractStateTrait::write(
            ref state.pool_volatility_adjustment_speed, lptoken_address, 0
        );

        new_pool_volatility_adjustment_speed::InternalContractStateTrait::write(
            ref state.new_pool_volatility_adjustment_speed, lptoken_address, new_speed
        );
    }

    fn get_pool_volatility_adjustment_speed(lptoken_address: LPTAddress) -> Fixed {
        let mut state = AMM::unsafe_new_contract_state();

        // First let's try to read the old storage var
        let res = pool_volatility_adjustment_speed::InternalContractStateTrait::read(
            @state.pool_volatility_adjustment_speed, lptoken_address
        );

        if res != 0 {
            // First assert that it's not negative
            assert(res.into() > 0_u256, 'Old pool vol adj spd negative');

            // if it's not zero then move the old value to new storage var and set the old one to zero
            let res_cubit = FixedHelpersTrait::from_legacyMath(res);

            // Write old value to new storage var
            set_pool_volatility_adjustment_speed(lptoken_address, res_cubit);

            // Set old value to zero
            pool_volatility_adjustment_speed::InternalContractStateTrait::write(
                ref state.pool_volatility_adjustment_speed, lptoken_address, 0
            );

            return res_cubit;
        }

        // If value in old storage var was zero then we can try to read from new storage var
        let res = new_pool_volatility_adjustment_speed::InternalContractStateTrait::read(
            @state.new_pool_volatility_adjustment_speed, lptoken_address
        );

        res.assert_nn_not_zero('New pool vol adj spd is <= 0');

        return res;
    }

    fn get_max_option_size_percent_of_voladjspd() -> Int {
        max_option_size_percent_of_voladjspd::InternalContractStateTrait::read(
            @AMM::unsafe_new_contract_state().max_option_size_percent_of_voladjspd
        )
    }

    fn set_max_option_size_percent_of_voladjspd(value: Int) {
        // TODO: Assert admin
        let mut state = AMM::unsafe_new_contract_state();
        max_option_size_percent_of_voladjspd::InternalContractStateTrait::write(
            ref state.max_option_size_percent_of_voladjspd, value
        )
    }

    fn get_pool_definition_from_lptoken_address(lptoken_address: LPTAddress) -> Pool {
        let state = AMM::unsafe_new_contract_state();
        let pool = pool_definition_from_lptoken_address::InternalContractStateTrait::read(
            @state.pool_definition_from_lptoken_address, lptoken_address
        );

        assert(
            contract_address_to_felt252(pool.quote_token_address) != 0, 'Quote addr doesnt exist'
        );
        assert(contract_address_to_felt252(pool.base_token_address) != 0, 'Base addr doesnt exist');
        assert_option_type_exists(pool.option_type.into(), 'Unknown option type');

        return pool;
    }

    fn get_lpool_balance(lptoken_address: LPTAddress) -> u256 {
        let state = AMM::unsafe_new_contract_state();
        lpool_balance_::InternalContractStateTrait::read(@state.lpool_balance_, lptoken_address)
    }

    fn set_lpool_balance(lptoken_address: LPTAddress, balance: u256) {
        assert(balance >= 0, 'lpool_balance negative');

        let mut state = AMM::unsafe_new_contract_state();
        lpool_balance_::InternalContractStateTrait::write(
            ref state.lpool_balance_, lptoken_address, balance
        )
    }

    fn get_option_position(
        lptoken_address: LPTAddress,
        option_side: OptionSide,
        maturity: Timestamp,
        strike_price: Strike
    ) -> Int {
        let mut state = AMM::unsafe_new_contract_state();

        // First let's try to read from the old storage var
        let res = option_position_::InternalContractStateTrait::read(
            @state.option_position_,
            (lptoken_address, option_side, maturity.into(), strike_price.to_legacyMath())
        );

        if res != 0 {
            // First assert it's not negative
            assert(res.into() > 0_u256, 'Old opt pos negative');

            // If it's not zero then move the old value to new storage var and set the old one to zero

            // Write old value to new storage var
            set_option_position(
                lptoken_address, option_side, maturity, strike_price, res.try_into().unwrap()
            );

            // Set old value to zero
            option_position_::InternalContractStateTrait::write(
                ref state.option_position_,
                (lptoken_address, option_side, maturity.into(), strike_price.to_legacyMath()),
                0
            );

            return res.try_into().unwrap();
        }

        // Otherwise just read and return from new storage var
        new_option_position::InternalContractStateTrait::read(
            @state.new_option_position, (lptoken_address, option_side, maturity, strike_price.mag)
        )
    }

    fn set_option_position(
        lptoken_address: LPTAddress,
        option_side: OptionSide,
        maturity: Timestamp,
        strike_price: Strike,
        position: Int
    ) {
        let mut state = AMM::unsafe_new_contract_state();

        strike_price.assert_nn_not_zero('Strike zero/neg in set_opt_pos');
        assert(position > 0, 'Pos zero/neg in set_opt_pos');

        // Also it's important to set corresponding option position in old storage var to zero se that if this function is called before get_option_position then the value in new storage var won't be overwritten by the old one
        option_position_::InternalContractStateTrait::write(
            ref state.option_position_,
            (lptoken_address, option_side, maturity.into(), strike_price.to_legacyMath()),
            0
        );

        new_option_position::InternalContractStateTrait::write(
            ref state.new_option_position,
            (lptoken_address, option_side, maturity, strike_price.mag),
            position
        )
    }

    fn get_pool_locked_capital(lptoken_address: LPTAddress) -> u256 {
        let state = AMM::unsafe_new_contract_state();
        pool_locked_capital_::InternalContractStateTrait::read(
            @state.pool_locked_capital_, lptoken_address
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
            ref state.pool_locked_capital_, lptoken_address, balance
        )
    }

    fn get_max_lpool_balance(lpt_addr: LPTAddress) -> u256 {
        max_lpool_balance::InternalContractStateTrait::read(
            @AMM::unsafe_new_contract_state().max_lpool_balance, lpt_addr
        )
    }

    fn set_max_lpool_balance(lpt_addr: LPTAddress, max_bal: u256) {
        let mut state = AMM::unsafe_new_contract_state();
        // TODO: Assert admin only!!!!!!!!!!!

        // TODO: Can uint be even negative lol
        assert(max_bal >= 0, 'Max lpool bal < 0');

        max_lpool_balance::InternalContractStateTrait::write(
            ref state.max_lpool_balance, lpt_addr, max_bal
        );
    }

    // TODO: Rename, there is no option here
    fn get_lptoken_address_for_given_option(
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        option_type: OptionType
    ) -> LPTAddress {
        let lpt_address = lptoken_addr_for_given_pooled_token::InternalContractStateTrait::read(
            @AMM::unsafe_new_contract_state().lptoken_addr_for_given_pooled_token,
            (quote_token_address, base_token_address, option_type)
        );

        assert_address_not_zero(lpt_address, 'GLAFGO - pool non existent');

        lpt_address
    }

    fn set_lptoken_address_for_given_option(
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        option_type: OptionType,
        lpt_address: LPTAddress
    ) {
        assert_address_not_zero(quote_token_address, 'SLAFGO - Quote addr zero');
        assert_address_not_zero(base_token_address, 'SLAFGO - Base addr zero');
        assert_address_not_zero(lpt_address, 'SLAFGO - LPT addr zero');
        assert_option_type_exists(option_type.into(), 'SLAFGO - Unknown opt type');

        let mut state = AMM::unsafe_new_contract_state();

        lptoken_addr_for_given_pooled_token::InternalContractStateTrait::write(
            ref state.lptoken_addr_for_given_pooled_token,
            (quote_token_address, base_token_address, option_type),
            lpt_address
        );
    }

    fn get_trading_halt() -> bool {
        trading_halted::InternalContractStateTrait::read(
            @AMM::unsafe_new_contract_state().trading_halted
        )
    }

    fn set_trading_halt(new_status: bool) {
        // TODO: implement check below
        // let caller_addr = get_caller_address();
        // let can_halt = can_halt_trading(caller_addr);
        // assert(can_halt, 'Noperrino')

        // assert_option_type_exists(new_status, 'This is unacceptableeeeeeeeeeee'); TODO: this check
        let mut state = AMM::unsafe_new_contract_state();

        trading_halted::InternalContractStateTrait::write(ref state.trading_halted, new_status)
    }

    // @notice Returns the token that's underlying the given liquidity pool.
    fn get_underlying_token_address(lptoken_address: LPTAddress) -> ContractAddress {
        let state = AMM::unsafe_new_contract_state();
        let underlying_token_address_ = underlying_token_address::InternalContractStateTrait::read(
            @state.underlying_token_address, lptoken_address
        );
        assert_address_not_zero(underlying_token_address_, 'Underlying addr is zero');
        return underlying_token_address_;
    }

    fn set_underlying_token_address(lptoken_address: LPTAddress, underlying_addr: ContractAddress) {
        assert_address_not_zero(underlying_addr, 'Underlying addr is zero');
        assert_address_not_zero(lptoken_address, 'LPT addr is zero');

        let mut state = AMM::unsafe_new_contract_state();

        underlying_token_address::InternalContractStateTrait::write(
            ref state.underlying_token_address, lptoken_address, underlying_addr
        );
    }

    fn get_available_lptoken_addresses(idx: felt252) -> LPTAddress {
        available_lptoken_adresses::InternalContractStateTrait::read(
            @AMM::unsafe_new_contract_state().available_lptoken_adresses, idx
        )
    }

    fn append_to_available_lptoken_addresses(lptoken_addr: LPTAddress) {
        let usable_idx = get_available_lptoken_addresses_usable_index(0);
        let mut state = AMM::unsafe_new_contract_state();
        available_lptoken_adresses::InternalContractStateTrait::write(
            ref state.available_lptoken_adresses, usable_idx, lptoken_addr
        )
    }

    fn get_available_lptoken_addresses_usable_index(idx: felt252) -> felt252 {
        let addr = get_available_lptoken_addresses(idx);
        if contract_address_to_felt252(addr) == 0 { // TODO: Does this check work?
            return idx;
        }
        get_available_lptoken_addresses_usable_index(idx + 1)
    }

    fn is_option_available(
        lptoken_address: ContractAddress,
        option_side: OptionSide,
        strike_price: Fixed,
        maturity: Timestamp
    ) -> bool {
        let option_addr = get_option_token_address(
            lptoken_address, option_side, maturity, strike_price
        );

        if contract_address_to_felt252(option_addr) == 0 {
            false
        } else {
            true
        }
    }

    fn fail_if_existing_pool_definition_from_lptoken_address(lpt_addr: LPTAddress) {
        let state = AMM::unsafe_new_contract_state();
        let pool = pool_definition_from_lptoken_address::InternalContractStateTrait::read(
            @state.pool_definition_from_lptoken_address, lpt_addr
        );

        assert(
            contract_address_to_felt252(pool.quote_token_address) == 0, 'Given lpt registered - 0'
        );
        assert(
            contract_address_to_felt252(pool.base_token_address) == 0, 'Given lpt registered - 1'
        );
    }

    fn set_pool_definition_from_lptoken_address(lptoken_address: LPTAddress, pool: Pool) {
        fail_if_existing_pool_definition_from_lptoken_address(lptoken_address);

        let mut state = AMM::unsafe_new_contract_state();
        let pool = pool_definition_from_lptoken_address::InternalContractStateTrait::write(
            ref state.pool_definition_from_lptoken_address, lptoken_address, pool
        );
    }

    fn get_option_info(
        lptoken_address: ContractAddress,
        option_side: OptionSide,
        strike_price: Fixed,
        maturity: Timestamp,
    ) -> Option_ {
        let mut i: u32 = 0;

        let match_opt: Option_ = loop {
            let option_ = get_available_options(lptoken_address, i);
            assert(option_.sum() != 0, 'Specified option unavailable');

            i += 1;
            if !(option_.option_side == option_side) {
                continue;
            }
            if !(option_.strike_price == strike_price) {
                continue;
            }
            if !(option_.maturity == maturity) {
                continue;
            }
            break option_;
        };

        match_opt
    }
}

