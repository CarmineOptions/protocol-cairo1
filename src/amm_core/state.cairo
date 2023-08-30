mod State {
    use starknet::get_caller_address;
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

    use carmine_protocol::amm_core::constants::{
        OPTION_CALL, OPTION_PUT, VOLATILITY_LOWER_BOUND, VOLATILITY_UPPER_BOUND
    };
    use carmine_protocol::amm_core::amm::AMM::{
        option_token_addressContractMemberStateTrait,
        new_option_token_addressContractMemberStateTrait,
        pool_volatility_separateContractMemberStateTrait, option_volatilityContractMemberStateTrait,
        pool_definition_from_lptoken_addressContractMemberStateTrait,
        available_lptoken_adressesContractMemberStateTrait,
        underlying_token_addressContractMemberStateTrait, trading_haltedContractMemberStateTrait,
        lptoken_addr_for_given_pooled_tokenContractMemberStateTrait,
        max_lpool_balanceContractMemberStateTrait, pool_locked_capital_ContractMemberStateTrait,
        lpool_balance_ContractMemberStateTrait, new_option_positionContractMemberStateTrait,
        max_option_size_percent_of_voladjspdContractMemberStateTrait,
        option_position_ContractMemberStateTrait, new_available_optionsContractMemberStateTrait,
        available_optionsContractMemberStateTrait,
        new_pool_volatility_adjustment_speedContractMemberStateTrait,
        new_available_options_usable_indexContractMemberStateTrait,
        pool_volatility_adjustment_speedContractMemberStateTrait, pool_volatility_separate,
        option_volatility, pool_volatility_adjustment_speed, new_pool_volatility_adjustment_speed,
        option_position_, new_option_position, option_token_address, new_option_token_address,
        available_options, new_available_options, new_available_options_usable_index,
        max_lpool_balance, lptoken_addr_for_given_pooled_token, trading_halted,
        available_lptoken_adresses, max_option_size_percent_of_voladjspd, underlying_token_address,
        pool_definition_from_lptoken_address, lpool_balance_, pool_locked_capital_
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
        state
            .option_token_address
            .write(
                (lptoken_address, option_side, maturity.into(), strike_price.to_legacyMath()),
                contract_address_try_from_felt252(0).unwrap()
            );

        state
            .new_option_token_address
            .write((lptoken_address, option_side, maturity, strike_price.mag), opt_address);
    }

    fn get_option_token_address(
        lptoken_address: LPTAddress,
        option_side: OptionSide,
        maturity: Timestamp,
        strike_price: Strike
    ) -> ContractAddress {
        let mut state = AMM::unsafe_new_contract_state();

        // First read the old value
        let option_token_addr = state
            .option_token_address
            .read((lptoken_address, option_side, maturity.into(), strike_price.to_legacyMath()));

        if contract_address_to_felt252(option_token_addr) != 0 {
            // Write value to new storage var
            set_option_token_address(
                lptoken_address, option_side, maturity, strike_price, option_token_addr
            );

            // Set old storage var to zero
            state
                .option_token_address
                .write(
                    (lptoken_address, option_side, maturity.into(), strike_price.to_legacyMath()),
                    contract_address_try_from_felt252(0).expect('Cannot create addr from 0')
                );

            return option_token_addr;
        }

        // Read from new storage var
        let res = state
            .new_option_token_address
            .read((lptoken_address, option_side, maturity, strike_price.mag));

        return res;
    }

    fn set_option_volatility(
        lptoken_address: LPTAddress,
        maturity: Timestamp,
        strike_price: Strike,
        volatility: Volatility
    ) {
        let mut state = AMM::unsafe_new_contract_state();

        assert(
            volatility < FixedTrait::from_felt(VOLATILITY_UPPER_BOUND),
            'Volatility exceeds upper bound'
        );
        assert(
            volatility > FixedTrait::from_felt(VOLATILITY_LOWER_BOUND),
            'Volatility below lower bound'
        );

        // Set old storage var to zero in case this function get called before the getter
        state
            .pool_volatility_separate
            .write((lptoken_address, maturity.into(), strike_price.to_legacyMath()), 0);

        state
            .option_volatility
            .write((lptoken_address, maturity.into(), strike_price.mag), volatility);
    }

    fn get_option_volatility(
        lptoken_address: LPTAddress, maturity: Timestamp, strike_price: Strike,
    ) -> Volatility {
        let mut state = AMM::unsafe_new_contract_state();

        // First let's try to read from the old storage var
        let res = state
            .pool_volatility_separate
            .read((lptoken_address, maturity.into(), strike_price.to_legacyMath()));

        if res != 0 {
            // First assert it's not negative
            assert(res.into() > 0_u256, 'Old opt vol adj spd negative');

            // If it's not zero then move the old value to new storage var and set the old one to zero

            let res_cubit = FixedHelpersTrait::from_legacyMath(res);

            // Write old value to new storage var
            set_option_volatility(lptoken_address, maturity, strike_price, res_cubit);

            // Set old value to zero
            state
                .pool_volatility_separate
                .write((lptoken_address, maturity.into(), strike_price.to_legacyMath()), 0);

            return res_cubit;
        }

        // If value in old storage var was zero then we can try to read from new storage var
        let res = state
            .option_volatility
            .read((lptoken_address, maturity.into(), strike_price.mag));

        res.assert_nn_not_zero('Opt vol <= 0');

        return res;
    }

    fn get_available_options_usable_index(lptoken_address: ContractAddress) -> u32 {
        AMM::unsafe_new_contract_state().new_available_options_usable_index.read(lptoken_address)
    }

    fn get_available_options(lptoken_address: LPTAddress, idx: u32) -> Option_ {
        let state = AMM::unsafe_new_contract_state();

        // In case this function is called before append_to_available_options
        let usable_index = get_available_options_usable_index(lptoken_address);
        if usable_index == 0 {
            let _ = migrate_old_options(lptoken_address, 0);
        }

        state.new_available_options.read((lptoken_address, idx))
    }

    fn append_to_available_options(option: Option_, lptoken_address: LPTAddress) {
        let mut state = AMM::unsafe_new_contract_state();

        // Read storage var containg the usable index
        let usable_index = get_available_options_usable_index(lptoken_address);

        // In this case we need to migrate the old options to the new storage var
        // since this storage var was introduced and is used only in c1 version
        if usable_index == 0 {
            let usable_index = migrate_old_options(lptoken_address, 0);
        }

        state.new_available_options.write((lptoken_address, usable_index), option);

        // Increase the usable index in available options
        state.new_available_options_usable_index.write(lptoken_address, usable_index + 1);
    }

    // Migrates old options and returns first empty index
    fn migrate_old_options(lptoken_address: ContractAddress, idx: u32) -> u32 {
        let mut state = AMM::unsafe_new_contract_state();

        // Get old option at index
        let old_option = state.available_options.read((lptoken_address, idx.into()));

        // This means we've reached the end of list, so return current index
        let option_sum = old_option.maturity + old_option.strike_price;
        if option_sum == 0 {
            return idx;
        }

        // Convert old option to new one and write at current index
        let new_option = LegacyOption_to_Option(old_option);
        state.new_available_options.write((lptoken_address, idx), new_option);

        // Continue to the next index
        migrate_old_options(lptoken_address, idx + 1)
    }

    fn set_pool_volatility_adjustment_speed(lptoken_address: LPTAddress, new_speed: Fixed) {
        new_speed.assert_nn_not_zero('Pool vol adjspd cant <= 0');

        let mut state = AMM::unsafe_new_contract_state();

        // Set old storage var to zero in case this function gets called before the getter
        state.pool_volatility_adjustment_speed.write(lptoken_address, 0);

        state.new_pool_volatility_adjustment_speed.write(lptoken_address, new_speed);
    }

    fn get_pool_volatility_adjustment_speed(lptoken_address: LPTAddress) -> Fixed {
        let mut state = AMM::unsafe_new_contract_state();

        // First let's try to read the old storage var
        let res = state.pool_volatility_adjustment_speed.read(lptoken_address);

        if res != 0 {
            // First assert that it's not negative
            assert(res.into() > 0_u256, 'Old pool vol adj spd negative');

            // if it's not zero then move the old value to new storage var and set the old one to zero
            let res_cubit = FixedHelpersTrait::from_legacyMath(res);

            // Write old value to new storage var
            set_pool_volatility_adjustment_speed(lptoken_address, res_cubit);

            // Set old value to zero
            state.pool_volatility_adjustment_speed.write(lptoken_address, 0);

            return res_cubit;
        }

        // If value in old storage var was zero then we can try to read from new storage var
        let res = state.new_pool_volatility_adjustment_speed.read(lptoken_address);

        res.assert_nn_not_zero('New pool vol adj spd is <= 0');

        return res;
    }

    fn get_max_option_size_percent_of_voladjspd() -> Int {
        AMM::unsafe_new_contract_state().max_option_size_percent_of_voladjspd.read()
    }

    fn set_max_option_size_percent_of_voladjspd(value: Int) {
        // TODO: Assert admin
        let mut state = AMM::unsafe_new_contract_state();
        state.max_option_size_percent_of_voladjspd.write(value)
    }

    fn get_pool_definition_from_lptoken_address(lptoken_address: LPTAddress) -> Pool {
        let state = AMM::unsafe_new_contract_state();
        let pool = state.pool_definition_from_lptoken_address.read(lptoken_address);

        assert(
            contract_address_to_felt252(pool.quote_token_address) != 0, 'Quote addr doesnt exist'
        );
        assert(contract_address_to_felt252(pool.base_token_address) != 0, 'Base addr doesnt exist');
        assert_option_type_exists(pool.option_type.into(), 'Unknown option type');

        return pool;
    }

    fn get_lpool_balance(lptoken_address: LPTAddress) -> u256 {
        let state = AMM::unsafe_new_contract_state();
        state.lpool_balance_.read(lptoken_address)
    }

    fn set_lpool_balance(lptoken_address: LPTAddress, balance: u256) {
        assert(balance >= 0, 'lpool_balance negative');

        let mut state = AMM::unsafe_new_contract_state();
        state.lpool_balance_.write(lptoken_address, balance)
    }

    fn get_option_position(
        lptoken_address: LPTAddress,
        option_side: OptionSide,
        maturity: Timestamp,
        strike_price: Strike
    ) -> Int {
        let mut state = AMM::unsafe_new_contract_state();

        // First let's try to read from the old storage var
        let res = state
            .option_position_
            .read((lptoken_address, option_side, maturity.into(), strike_price.to_legacyMath()));

        if res != 0 {
            // First assert it's not negative
            assert(res.into() > 0_u256, 'Old opt pos negative');

            // If it's not zero then move the old value to new storage var and set the old one to zero

            // Write old value to new storage var
            set_option_position(
                lptoken_address, option_side, maturity, strike_price, res.try_into().unwrap()
            );

            // Set old value to zero
            state
                .option_position_
                .write(
                    (lptoken_address, option_side, maturity.into(), strike_price.to_legacyMath()), 0
                );

            return res.try_into().unwrap();
        }

        // Otherwise just read and return from new storage var
        state.new_option_position.read((lptoken_address, option_side, maturity, strike_price.mag))
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
        state
            .option_position_
            .write(
                (lptoken_address, option_side, maturity.into(), strike_price.to_legacyMath()), 0
            );

        state
            .new_option_position
            .write((lptoken_address, option_side, maturity, strike_price.mag), position)
    }

    fn get_pool_locked_capital(lptoken_address: LPTAddress) -> u256 {
        let state = AMM::unsafe_new_contract_state();
        state.pool_locked_capital_.read(lptoken_address)
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
        state.pool_locked_capital_.write(lptoken_address, balance)
    }

    fn get_max_lpool_balance(lpt_addr: LPTAddress) -> u256 {
        AMM::unsafe_new_contract_state().max_lpool_balance.read(lpt_addr)
    }

    fn set_max_lpool_balance(lpt_addr: LPTAddress, max_bal: u256) {
        let mut state = AMM::unsafe_new_contract_state();
        // TODO: Assert admin only!!!!!!!!!!!

        assert(max_bal >= 0, 'Max lpool bal < 0'); // Kinda useless

        state.max_lpool_balance.write(lpt_addr, max_bal);
    }

    fn get_lptoken_address_for_given_option(
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        option_type: OptionType
    ) -> LPTAddress {
        let state = AMM::unsafe_new_contract_state();
        let lpt_address = state
            .lptoken_addr_for_given_pooled_token
            .read((quote_token_address, base_token_address, option_type));

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

        state
            .lptoken_addr_for_given_pooled_token
            .write((quote_token_address, base_token_address, option_type), lpt_address);
    }

    fn get_trading_halt() -> bool {
        AMM::unsafe_new_contract_state().trading_halted.read()
    }

    fn set_trading_halt(new_status: bool) {
        assert_trading_halt_allowed();

        assert_option_type_exists(new_status.into(), 'Unknown halt status');
        let mut state = AMM::unsafe_new_contract_state();

        state.trading_halted.write(new_status)
    }

    fn assert_trading_halt_allowed() {
        let caller_addr = get_caller_address();

        if caller_addr == 0x0583a9d956d65628f806386ab5b12dccd74236a3c6b930ded9cf3c54efc722a1
            .try_into()
            .unwrap() {
            return; // Ondra
        }
        if caller_addr == 0x06717eaf502baac2b6b2c6ee3ac39b34a52e726a73905ed586e757158270a0af
            .try_into()
            .unwrap() {
            return; // Andrej
        }
        if caller_addr == 0x0011d341c6e841426448ff39aa443a6dbb428914e05ba2259463c18308b86233
            .try_into()
            .unwrap() {
            return; // Marek
        }
        // TODO: Add david
        assert(1 == 0, 'Caller cant halt trading');
    }

    // @notice Returns the token that's underlying the given liquidity pool.
    fn get_underlying_token_address(lptoken_address: LPTAddress) -> ContractAddress {
        let state = AMM::unsafe_new_contract_state();
        let underlying_token_address_ = state.underlying_token_address.read(lptoken_address);
        assert_address_not_zero(underlying_token_address_, 'Underlying addr is zero');
        return underlying_token_address_;
    }

    fn set_underlying_token_address(lptoken_address: LPTAddress, underlying_addr: ContractAddress) {
        assert_address_not_zero(underlying_addr, 'Underlying addr is zero');
        assert_address_not_zero(lptoken_address, 'LPT addr is zero');

        let mut state = AMM::unsafe_new_contract_state();

        state.underlying_token_address.write(lptoken_address, underlying_addr);
    }

    fn get_available_lptoken_addresses(idx: felt252) -> LPTAddress {
        AMM::unsafe_new_contract_state().available_lptoken_adresses.read(idx)
    }

    fn append_to_available_lptoken_addresses(lptoken_addr: LPTAddress) {
        let usable_idx = get_available_lptoken_addresses_usable_index(0);
        let mut state = AMM::unsafe_new_contract_state();

        state.available_lptoken_adresses.write(usable_idx, lptoken_addr)
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
        let pool = state.pool_definition_from_lptoken_address.read(lpt_addr);

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
        let pool = state.pool_definition_from_lptoken_address.write(lptoken_address, pool);
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

