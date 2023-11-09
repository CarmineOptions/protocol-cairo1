mod View {
    use core::traits::{TryInto, Into};
    use starknet::get_block_timestamp;
    use starknet::ContractAddress;
    use array::ArrayTrait;
    use core::option::OptionTrait;

    use cubit::f128::types::fixed::Fixed;
    use cubit::f128::types::fixed::FixedTrait;
    

    use carmine_protocol::amm_core::helpers::pow;

    use carmine_protocol::traits::IERC20Dispatcher;
    use carmine_protocol::traits::IERC20DispatcherTrait;

    use carmine_protocol::tokens::option_token::IOptionTokenDispatcher;
    use carmine_protocol::tokens::option_token::IOptionTokenDispatcherTrait;

    use carmine_protocol::amm_core::constants::TOKEN_ETH_ADDRESS;
    use carmine_protocol::amm_core::constants::TOKEN_WBTC_ADDRESS;

    use carmine_protocol::amm_core::state::State::get_available_options;
    use carmine_protocol::amm_core::state::State::get_option_volatility;
    use carmine_protocol::amm_core::state::State::get_pool_volatility_adjustment_speed;
    use carmine_protocol::amm_core::state::State::get_available_lptoken_addresses;

    use carmine_protocol::types::pool::UserPoolInfo;
    use carmine_protocol::types::pool::PoolInfo;
    use carmine_protocol::types::pool::PoolInfoTrait;
    use carmine_protocol::types::pool::PoolTrait;
    use carmine_protocol::types::pool::Pool;

    use carmine_protocol::types::option_::Option_;
    use carmine_protocol::types::option_::Option_Trait;
    use carmine_protocol::types::option_::OptionWithPremia;
    use carmine_protocol::types::option_::OptionWithUsersPosition;

    use carmine_protocol::types::basic::{LPTAddress, Int};

    use carmine_protocol::amm_core::helpers::fromU256_balance;


    //
    // @title View Functions
    // @notice Collection of view functions used by the frontend and traders
    //

    // @notice Getter for all options
    // @param lptoken_address: Address of the liquidity pool token
    // @return array: Array of all options
    fn get_all_options(lpt_addr: LPTAddress) -> Array<Option_> {
        let mut i: u32 = 0;
        let mut arr = ArrayTrait::<Option_>::new();

        loop {
            let opt = get_available_options(lpt_addr, i);

            if opt.sum() == 0 {
                // This means we've reached the end, so break
                break;
            }

            arr.append(opt);
            i += 1;
        };

        arr
    }

    // @notice Getter for all non-expired options with premia
    // @param lptoken_address: Address of the liquidity pool token
    // @return array: Array of non-expired options
    fn get_all_non_expired_options_with_premia(lpt_addr: LPTAddress) -> Array<OptionWithPremia> {
        let mut i: u32 = 0;
        let current_block_time = get_block_timestamp();
        let mut arr = ArrayTrait::<OptionWithPremia>::new();

        let pool = PoolTrait::from_lpt_address(lpt_addr);

        let decs = IERC20Dispatcher { contract_address: pool.base_token_address }.decimals();

        let one = pow(10, decs.into());

        loop {
            let opt = get_available_options(lpt_addr, i);
            i += 1;

            if opt.sum() == 0 {
                // This means we've reached the end, so break
                break;
            }

            if !(opt.maturity > current_block_time) {
                continue;
            }

            let total_premia = opt.premia_with_fees(one);

            arr.append(OptionWithPremia { option: opt, premia: total_premia });
        };
        arr
    }

    // @notice Getter for list of all options with position of a given user(if they have any)
    // @param user_address: user's address
    // @return array: Array of OptionWithUsersPosition
    fn get_option_with_position_of_user(
        user_address: ContractAddress
    ) -> Array<OptionWithUsersPosition> {
        let mut pool_idx: felt252 = 0;
        let mut opt_idx: u32 = 0;
        let mut arr = ArrayTrait::<OptionWithUsersPosition>::new();

        loop {
            let lptoken_addr = get_available_lptoken_addresses(pool_idx);
            if lptoken_addr.is_zero() {
                break;
            }

            loop {
                let option = get_available_options(lptoken_addr, opt_idx);

                if option.sum() == 0 {
                    pool_idx += 1;
                    opt_idx = 0;
                    break;
                }

                let pos_size = IOptionTokenDispatcher { contract_address: option.opt_address() }
                    .balance_of(user_address); // TODO: Add camel case function to opt token

                if pos_size == 0 {
                    opt_idx += 1;
                    break;
                }

                let premia_with_fees = option.value_of_user_position(pos_size.try_into().unwrap());

                let new_opt = OptionWithUsersPosition {
                    option: option, position_size: pos_size, value_of_position: premia_with_fees
                };

                arr.append(new_opt);
                opt_idx += 1;
            };
        };

        arr
    }

    // @notice Getter for all liquidity pool addresses
    // @return array: Array of liquidity pool addresses
    fn get_all_lptoken_addresses() -> Array<ContractAddress> {
        let mut i: felt252 = 0;
        let mut arr = ArrayTrait::<ContractAddress>::new();

        loop {
            let lpt_addr = get_available_lptoken_addresses(i);

            if lpt_addr.is_zero() {
                break;
            }

            i += 1;
            arr.append(lpt_addr);
        };

        arr
    }

    // @notice Retrieve pool information for the given user
    // @param user: User's wallet address
    // @return user_pool_infos: Information about user's stake in the liquidity pools
    fn get_user_pool_infos(user: ContractAddress) -> Array<UserPoolInfo> {
        let mut lptoken_addrs = get_all_lptoken_addresses();
        let mut user_pool_infos = ArrayTrait::<UserPoolInfo>::new();

        loop {
            match lptoken_addrs.pop_front() {
                Option::Some(lpt_addr) => {
                    let pool_info = PoolTrait::from_lpt_address(lpt_addr).to_PoolInfo();
                    let user_pool_info = pool_info.to_UserPoolInfo(user);
                    user_pool_infos.append(user_pool_info);
                },
                Option::None(()) => {
                    break ();
                },
            };
        };
        user_pool_infos
    }

    // @notice Retrieves PoolInfo for all liquidity pools
    // @return pool_info: Array of PoolInfo
    fn get_all_poolinfo() -> Array<PoolInfo> {
        let mut lptoken_addrs = get_all_lptoken_addresses();
        let mut pool_infos = ArrayTrait::<PoolInfo>::new();

        loop {
            match lptoken_addrs.pop_front() {
                Option::Some(lpt_addr) => {
                    let pool = PoolTrait::from_lpt_address(lpt_addr);

                    pool_infos.append(pool.to_PoolInfo());
                },
                Option::None(()) => {
                    break ();
                },
            };
        };

        pool_infos
    }

    // @notice Calculates premia for the provided option
    // @param _option: Option for which premia is being calculated
    // @param position_size: Size of the position
    // @param is_closing: Is the position being closed or opened
    // @return total_premia_before_fees: Premia
    // @return total_premia_including_fees: Premia with fees
    fn get_total_premia(option: Option_, position_size: u256, is_closing: bool) -> (Fixed, Fixed) {
        let correct_option = option.correct_side(is_closing);
        let pos_size_int: Int = position_size.try_into().unwrap();

        (
            correct_option.premia_before_fees(pos_size_int),
            correct_option.premia_with_fees(pos_size_int)
        )
    }
}

