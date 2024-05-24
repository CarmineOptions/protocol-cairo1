mod State {
    use starknet::get_caller_address;
    use starknet::ContractAddress;
    use traits::{Into, TryInto};
    use starknet::contract_address::contract_address_try_from_felt252;
    use core::option::OptionTrait;
    use cubit::f128::types::fixed::Fixed;
    use cubit::f128::types::fixed::FixedTrait;

    use carmine_protocol::amm_core::helpers::assert_option_side_exists;
    use carmine_protocol::amm_core::helpers::assert_option_type_exists;
    use carmine_protocol::amm_core::helpers::FixedHelpersTrait;

    use carmine_protocol::amm_core::constants::OPTION_CALL;
    use carmine_protocol::amm_core::constants::OPTION_PUT;
    use carmine_protocol::amm_core::constants::VOLATILITY_LOWER_BOUND;
    use carmine_protocol::amm_core::constants::VOLATILITY_UPPER_BOUND;

    use carmine_protocol::amm_core::amm::AMM::new_option_token_addressContractMemberStateTrait;
    use carmine_protocol::amm_core::amm::AMM::option_volatilityContractMemberStateTrait;
    use carmine_protocol::amm_core::amm::AMM::pool_definition_from_lptoken_addressContractMemberStateTrait;
    use carmine_protocol::amm_core::amm::AMM::available_lptoken_adressesContractMemberStateTrait;
    use carmine_protocol::amm_core::amm::AMM::underlying_token_addressContractMemberStateTrait;
    use carmine_protocol::amm_core::amm::AMM::trading_haltedContractMemberStateTrait;
    use carmine_protocol::amm_core::amm::AMM::lptoken_addr_for_given_pooled_tokenContractMemberStateTrait;
    use carmine_protocol::amm_core::amm::AMM::max_lpool_balanceContractMemberStateTrait;
    use carmine_protocol::amm_core::amm::AMM::pool_locked_capital_ContractMemberStateTrait;
    use carmine_protocol::amm_core::amm::AMM::lpool_balance_ContractMemberStateTrait;
    use carmine_protocol::amm_core::amm::AMM::new_option_positionContractMemberStateTrait;
    use carmine_protocol::amm_core::amm::AMM::max_option_size_percent_of_voladjspdContractMemberStateTrait;
    use carmine_protocol::amm_core::amm::AMM::new_available_optionsContractMemberStateTrait;
    use carmine_protocol::amm_core::amm::AMM::new_pool_volatility_adjustment_speedContractMemberStateTrait;
    use carmine_protocol::amm_core::amm::AMM::new_available_options_usable_indexContractMemberStateTrait;
    use carmine_protocol::amm_core::amm::AMM::trading_halt_permissionContractMemberStateTrait;
    use carmine_protocol::amm_core::amm::AMM::trading_halt_permission;
    use carmine_protocol::amm_core::amm::AMM::option_volatility;
    use carmine_protocol::amm_core::amm::AMM::new_pool_volatility_adjustment_speed;
    use carmine_protocol::amm_core::amm::AMM::new_option_position;
    use carmine_protocol::amm_core::amm::AMM::new_option_token_address;
    use carmine_protocol::amm_core::amm::AMM::new_available_options;
    use carmine_protocol::amm_core::amm::AMM::new_available_options_usable_index;
    use carmine_protocol::amm_core::amm::AMM::max_lpool_balance;
    use carmine_protocol::amm_core::amm::AMM::lptoken_addr_for_given_pooled_token;
    use carmine_protocol::amm_core::amm::AMM::trading_halted;
    use carmine_protocol::amm_core::amm::AMM::available_lptoken_adresses;
    use carmine_protocol::amm_core::amm::AMM::max_option_size_percent_of_voladjspd;
    use carmine_protocol::amm_core::amm::AMM::underlying_token_address;
    use carmine_protocol::amm_core::amm::AMM::pool_definition_from_lptoken_address;
    use carmine_protocol::amm_core::amm::AMM::lpool_balance_;
    use carmine_protocol::amm_core::amm::AMM::pool_locked_capital_;

    use carmine_protocol::amm_core::amm::AMM;

    use carmine_protocol::types::basic::LPTAddress;
    use carmine_protocol::types::basic::OptionSide;
    use carmine_protocol::types::basic::OptionType;
    use carmine_protocol::types::basic::Volatility;
    use carmine_protocol::types::basic::Strike;
    use carmine_protocol::types::basic::Int;
    use carmine_protocol::types::basic::Timestamp;

    use carmine_protocol::types::pool::Pool;
    use carmine_protocol::types::option_::Option_;
    use carmine_protocol::types::option_::Option_Trait;

    // @notice Writes option token address into storage var, mapped against option definition
    // @param lptoken_addres: Address of a pool which the option belongs to
    // @param option_side: 0 for long, 1 for short
    // @param maturity: Maturity of given option
    // @param strike_price: Strike price of given option
    // @param opt_address: Option token address
    fn set_option_token_address(
        lptoken_address: LPTAddress,
        option_side: OptionSide,
        maturity: Timestamp,
        strike_price: Strike,
        opt_address: ContractAddress
    ) {
        let mut state = AMM::unsafe_new_contract_state();

        assert_option_side_exists(option_side.into(), 'SOTA - opt side non existent');
        assert(!lptoken_address.is_zero(), 'SOTA - lpt addr 0');
        assert(maturity > 0, 'SOTA - maturity <= 0');
        strike_price.assert_nn_not_zero('SOTA - strike <= 0');
        assert(!opt_address.is_zero(), 'SOTA - opt addr 0');

        state
            .new_option_token_address
            .write((lptoken_address, option_side, maturity, strike_price.mag), opt_address);
    }


    // @notice Retrieves option token address based on option definition
    // @param lptoken_addres: Address of a pool which the option belongs to
    // @param option_side: 0 for long, 1 for short
    // @param maturity: Maturity of given option
    // @param strike_price: Strike price of given option
    // @returns opt_address: Option token address
    fn get_option_token_address(
        lptoken_address: LPTAddress,
        option_side: OptionSide,
        maturity: Timestamp,
        strike_price: Strike
    ) -> ContractAddress {
        let mut state = AMM::unsafe_new_contract_state();

        // Read from new storage var
        let res = state
            .new_option_token_address
            .read((lptoken_address, option_side, maturity, strike_price.mag));

        return res;
    }

    // @notice Sets option volatility based on it's definition
    // @param lptoken_addres: Address of a pool which the option belongs to
    // @param maturity: Maturity of given option
    // @param strike_price: Strike price of given option
    // @param volatility: volatility of given option
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

        state
            .option_volatility
            .write((lptoken_address, maturity.into(), strike_price.mag), volatility);
    }

    // @notice Retrieves option volatility based on it's definition
    // @param lptoken_addres: Address of a pool which the option belongs to
    // @param maturity: Maturity of given option
    // @param strike_price: Strike price of given option
    // @returns volatility: volatility of given option
    fn get_option_volatility(
        lptoken_address: LPTAddress, maturity: Timestamp, strike_price: Strike
    ) -> Volatility {
        let mut state = AMM::unsafe_new_contract_state();

        let res = state
            .option_volatility
            .read((lptoken_address, maturity.into(), strike_price.mag));

        res.assert_nn_not_zero('Opt vol <= 0');

        return res;
    }

    // @notice Returns the first free option index for the given lptoken address.
    // @dev Returns lowest index that does not contain any specified option (only zeros).
    // @param lptoken_address: Address of liquidity pool
    // @returns available_index: first available index in storage var
    fn get_available_options_usable_index(lptoken_address: ContractAddress) -> u32 {
        AMM::unsafe_new_contract_state().new_available_options_usable_index.read(lptoken_address)
    }

    // @notice Returns the option for given pool and index
    // @param lptoken_address: Address of liquidity pool
    // @param idx: Index in storage var
    // @returns option: Option struct stored under the given index
    fn get_available_options(lptoken_address: LPTAddress, idx: u32) -> Option_ {
        let state = AMM::unsafe_new_contract_state();

        state.new_available_options.read((lptoken_address, idx))
    }


    // @notice Appends new option to available options for given pool
    // @param option: Option struct to be stored
    // @param lptoken_address: Address of liquidity pool correspending to the option
    fn append_to_available_options(option: Option_, lptoken_address: LPTAddress) {
        let mut state = AMM::unsafe_new_contract_state();

        // Read storage var containg the usable index
        let mut usable_index = get_available_options_usable_index(lptoken_address);

        state.new_available_options.write((lptoken_address, usable_index), option);

        // Increase the usable index in available options
        state.new_available_options_usable_index.write(lptoken_address, usable_index + 1);
    }

    // @notice Sets pool volatility adjustment speed
    // @param lptoken_addres: Address of a liquidity pool
    // @param new_speed: New volatility adjustment speed
    fn set_pool_volatility_adjustment_speed(lptoken_address: LPTAddress, new_speed: Fixed) {
        new_speed.assert_nn_not_zero('Pool vol adjspd cant <= 0');

        let mut state = AMM::unsafe_new_contract_state();

        state.new_pool_volatility_adjustment_speed.write(lptoken_address, new_speed);
    }

    // @notice Retrieves pool volatility adjustment speed
    // @param lptoken_addres: Address of a liquidity pool
    // @returns pool volatility adjustment speed: Pool adjustment speed
    fn get_pool_volatility_adjustment_speed(lptoken_address: LPTAddress) -> Fixed {
        let mut state = AMM::unsafe_new_contract_state();

        let res = state.new_pool_volatility_adjustment_speed.read(lptoken_address);

        res.assert_nn_not_zero('New pool vol adj spd is <= 0');

        return res;
    }


    // @notice Sets max option size as a percentage of pool volatility adjustment speed
    // @param value: percentage, ie 20
    fn set_max_option_size_percent_of_voladjspd(value: Int) {
        let mut state = AMM::unsafe_new_contract_state();
        state.max_option_size_percent_of_voladjspd.write(value.into())
    }

    // @notice Returns maximal option size as a percentage of pool volatility adjustment speed
    // @returns max option size as percentage of pool volatility adjustment speed
    fn get_max_option_size_percent_of_voladjspd() -> Int {
        AMM::unsafe_new_contract_state()
            .max_option_size_percent_of_voladjspd
            .read()
            .try_into()
            .unwrap()
    }

    // @notice Returns pool definition for given lptoken address
    // @param lptoken_address: Liquidity pool token address
    // @returns pool: Pool struct containg the definition
    fn get_pool_definition_from_lptoken_address(lptoken_address: LPTAddress) -> Pool {
        let state = AMM::unsafe_new_contract_state();
        let pool = state.pool_definition_from_lptoken_address.read(lptoken_address);

        assert(!pool.quote_token_address.is_zero(), 'Quote addr doesnt exist');
        assert(!pool.base_token_address.is_zero(), 'Base addr doesnt exist');
        assert_option_type_exists(pool.option_type.into(), 'Unknown option type');

        return pool;
    }

    // @notice Sets liquidity pool balance
    // @param lptoken_address: Address of liquidity pool token under which the balance is stored
    // @param balance: New lpool balance in u256
    fn set_lpool_balance(lptoken_address: LPTAddress, balance: u256) {
        let mut state = AMM::unsafe_new_contract_state();

        let locked = state.pool_locked_capital_.read(lptoken_address);
        assert(balance >= locked, 'Cant set lpool < locked');

        state.lpool_balance_.write(lptoken_address, balance)
    }

    // @notice Returns liquidity pool balance
    // @param lptoken_address: Address of liquidity pool token under which the balance is stored
    // @returns balance: New lpool balance in u256
    fn get_lpool_balance(lptoken_address: LPTAddress) -> u256 {
        let state = AMM::unsafe_new_contract_state();
        state.lpool_balance_.read(lptoken_address)
    }

    // @notice Returns the given liqpool's position in a given option
    // @param lptoken_address: Address of given liqpool
    // @param option_side: Side of the given option
    // @param maturity: Maturity of the given option 
    // @param strike_price: Strike price of the given option
    // @return option_position: Int. Has same amount of decimals as base token.
    fn get_option_position(
        lptoken_address: LPTAddress,
        option_side: OptionSide,
        maturity: Timestamp,
        strike_price: Strike
    ) -> Int {
        let mut state = AMM::unsafe_new_contract_state();

        state.new_option_position.read((lptoken_address, option_side, maturity, strike_price.mag))
    }

    // @notice Sets the given liqpool's position in a given option
    // @param lptoken_address: Address of given liqpool
    // @param option_side: Side of the given option
    // @param maturity: Maturity of the given option 
    // @param strike_price: Strike price of the given option
    // @param option_position: Int. Has same amount of decimals as base token.
    fn set_option_position(
        lptoken_address: LPTAddress,
        option_side: OptionSide,
        maturity: Timestamp,
        strike_price: Strike,
        position: Int
    ) {
        let mut state = AMM::unsafe_new_contract_state();

        strike_price.assert_nn_not_zero('Strike zero/neg in set_opt_pos');

        state
            .new_option_position
            .write((lptoken_address, option_side, maturity, strike_price.mag), position)
    }

    // @notice Returns pool's locked capital
    // @param  lptoken_address: Address of liquidity pool token that corresponds to the pool
    // @retuns locked_capital: Amount of locked pooled tokens in u256
    fn get_pool_locked_capital(lptoken_address: LPTAddress) -> u256 {
        let state = AMM::unsafe_new_contract_state();
        state.pool_locked_capital_.read(lptoken_address)
    }

    // @notice Returns pool's unlocked capital
    // @dev Unlocked capital is calculated as lpool_balance - locked_capital
    // @param  lptoken_address: Address of liquidity pool token that corresponds to the pool
    // @retuns unlocked_capital: Amount of unlocked pooled tokens in u256
    fn get_unlocked_capital(lptoken_address: LPTAddress) -> u256 {
        // Capital locked by the pool
        let locked_capital = get_pool_locked_capital(lptoken_address);

        // Get capital that is sum of unlocked (available) and locked capital.
        let contract_balance = get_lpool_balance(lptoken_address);

        return contract_balance - locked_capital;
    }

    // @notice Sets pool's locked capital
    // @param  lptoken_address: Address of liquidity pool token that corresponds to the pool
    // @param  balance: New amount of locked pooled tokens in u256
    fn set_pool_locked_capital(lptoken_address: LPTAddress, balance: u256) {
        let mut state = AMM::unsafe_new_contract_state();

        let lpool_bal = state.lpool_balance_.read(lptoken_address);
        assert(lpool_bal >= balance, 'Cant set locked > lpool');

        state.pool_locked_capital_.write(lptoken_address, balance)
    }


    // @notice Returns the current maximum total balance of the pooled token for given pool
    // @param lpt_addr: Address of liquidity pool token for given liqpool
    // @returns max balance: Maximum balance of pooled token for given pool
    fn get_max_lpool_balance(lpt_addr: LPTAddress) -> u256 {
        AMM::unsafe_new_contract_state().max_lpool_balance.read(lpt_addr)
    }

    // @notice Sets the maximum total balance of the pooled token for given pool
    // @param lpt_addr: Address of liquidity pool token for given liqpool
    // @param max bal: Maximum balance of pooled token for given pool
    fn set_max_lpool_balance(lpt_addr: LPTAddress, max_bal: u256) {
        let mut state = AMM::unsafe_new_contract_state();

        state.max_lpool_balance.write(lpt_addr, max_bal);
    }

    // @notice Returns lptoken address based on some option parameters
    // @param quote_token_address: Option's quote token's address
    // @param base_token_address: Option's base token's address
    // @param option_type: Option type
    // @returns lptoken_address: Address of corresponding lp token
    fn get_lptoken_address_for_given_option(
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        option_type: OptionType
    ) -> LPTAddress {
        let state = AMM::unsafe_new_contract_state();
        let lpt_address = state
            .lptoken_addr_for_given_pooled_token
            .read((quote_token_address, base_token_address, option_type));

        assert(!lpt_address.is_zero(), 'GLAFGO - pool non existent');

        lpt_address
    }

    // @notice Sets lptoken address based on some option parameters
    // @param quote_token_address: Option's quote token's address
    // @param base_token_address: Option's base token's address
    // @param option_type: Option type
    // @param lptoken_address: Address of corresponding lp token
    fn set_lptoken_address_for_given_option(
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        option_type: OptionType,
        lpt_address: LPTAddress
    ) {
        assert(!quote_token_address.is_zero(), 'SLAFGO - Quote addr zero');
        assert(!base_token_address.is_zero(), 'SLAFGO - Base addr zero');
        assert(!lpt_address.is_zero(), 'SLAFGO - LPT addr zero');
        assert_option_type_exists(option_type.into(), 'SLAFGO - Unknown opt type');

        let mut state = AMM::unsafe_new_contract_state();

        // Assert that there is no lptoken address for given option existing yet
        let curr_lpt_addr = state
            .lptoken_addr_for_given_pooled_token
            .read((quote_token_address, base_token_address, option_type));

        assert(curr_lpt_addr.is_zero(), 'LPT for given params existing');

        state
            .lptoken_addr_for_given_pooled_token
            .write((quote_token_address, base_token_address, option_type), lpt_address);
    }

    // @notice Returns trading halt status
    // @returns trading_halted: true if trading is halted, false otherwise
    fn get_trading_halt() -> bool {
        AMM::unsafe_new_contract_state().trading_halted.read()
    }

    // @notice Sets trading halt status
    // @param new_status: true if trading is halted, false otherwise
    fn set_trading_halt(new_status: bool) {
        let mut state = AMM::unsafe_new_contract_state();
        state.trading_halted.write(new_status)
    }

    fn set_trading_halt_permission(address: ContractAddress, permission: bool) {
        let mut state = AMM::unsafe_new_contract_state();
        state.trading_halt_permission.write(address, permission);
    }

    fn get_trading_halt_permission(address: ContractAddress) -> bool {
        let mut state = AMM::unsafe_new_contract_state();
        state.trading_halt_permission.read(address)
    }

    // @notice  Returns the token that's underlying the given liquidity pool.
    // @param   lptoken_address: Address of given liquidity pool token
    // @returns Underlying token address
    fn get_underlying_token_address(lptoken_address: LPTAddress) -> ContractAddress {
        let state = AMM::unsafe_new_contract_state();
        let underlying_token_address_ = state.underlying_token_address.read(lptoken_address);
        assert(!underlying_token_address_.is_zero(), 'Underlying addr is zero');
        return underlying_token_address_;
    }

    // @notice Sets the token that's underlying the given liquidity pool.
    // @param lptoken_address: Address of given liquidity pool token
    // @param underlying_addr: Underlying token address
    fn set_underlying_token_address(lptoken_address: LPTAddress, underlying_addr: ContractAddress) {
        assert(!underlying_addr.is_zero(), 'Underlying addr is zero');
        assert(!lptoken_address.is_zero(), 'LPT addr is zero');

        let mut state = AMM::unsafe_new_contract_state();

        state.underlying_token_address.write(lptoken_address, underlying_addr);
    }

    // @notice Reads lptoken address at given index. Useful for e.g. retrieving all lptokens.
    // @param idx: Index
    // @returns lptoken address stored under provided index
    fn get_available_lptoken_addresses(idx: felt252) -> LPTAddress {
        AMM::unsafe_new_contract_state().available_lptoken_adresses.read(idx)
    }

    // @notice Appends lptoken address to corresponding storage var
    // @param lptoken_addr: Address of lptoken to be stored
    fn append_to_available_lptoken_addresses(lptoken_addr: LPTAddress) {
        let usable_idx = get_available_lptoken_addresses_usable_index(0);
        let mut state = AMM::unsafe_new_contract_state();

        state.available_lptoken_adresses.write(usable_idx, lptoken_addr)
    }

    // @notice Returns available index in available_lptoken_address storage var
    // @returns idx: Available index
    fn get_available_lptoken_addresses_usable_index(idx: felt252) -> felt252 {
        let addr = get_available_lptoken_addresses(idx);
        if addr.is_zero() {
            return idx;
        }
        get_available_lptoken_addresses_usable_index(idx + 1)
    }

    // @notice Checks if AMM is aware of an option based on it's definition
    // @param lptoken_address: Address of liquidity pool that corresponds to the option
    // @param option_side: Option's side
    // @param strike_price: Option's strike price
    // @param maturity: Options's maturity
    // @returns bool: True if option is available, false otherwise
    fn is_option_available(
        lptoken_address: ContractAddress,
        option_side: OptionSide,
        strike_price: Fixed,
        maturity: Timestamp
    ) -> bool {
        let option_addr = get_option_token_address(
            lptoken_address, option_side, maturity, strike_price
        );

        if option_addr.is_zero() {
            false
        } else {
            true
        }
    }

    // @notice Fails if pool definition is already stored in the amm
    // @dev Used in set_pool_definition_from_lptoken_address to prevent overwritting
    // @dev already existing definition
    // @param lpt_addr: LP token address
    fn fail_if_existing_pool_definition_from_lptoken_address(lpt_addr: LPTAddress) {
        let state = AMM::unsafe_new_contract_state();
        let pool = state.pool_definition_from_lptoken_address.read(lpt_addr);

        assert(pool.quote_token_address.is_zero(), 'Given lpt registered - 0');
        assert(pool.base_token_address.is_zero(), 'Given lpt registered - 1');
    }

    // @notice Sets pool definition for the given LP token address
    // @param lptoken_address: LP token address
    // @param pool: Pool struct containing pool information
    fn set_pool_definition_from_lptoken_address(lptoken_address: LPTAddress, pool: Pool) {
        fail_if_existing_pool_definition_from_lptoken_address(lptoken_address);

        let mut state = AMM::unsafe_new_contract_state();
        let pool = state.pool_definition_from_lptoken_address.write(lptoken_address, pool);
    }

    // @notice Returns Option struct with addition info based on several option parameters
    // @param lptoken_address: Address of liquidity pool that corresponds to the option
    // @param option_side: Option's side
    // @param strike_price: Option's strike price
    // @param maturity: Options's maturity
    // @return option: Option struct containing addition info
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
