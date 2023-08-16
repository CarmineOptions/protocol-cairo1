mod View {
    use cubit::f128::types::fixed::{Fixed, FixedTrait};
    use core::traits::{TryInto, Into};
    use starknet::get_block_timestamp;
    use starknet::ContractAddress;
    use array::ArrayTrait;

    use core::option::OptionTrait;

    use carmine_protocol::traits::{IERC20Dispatcher, IERC20DispatcherTrait};

    use starknet::contract_address::{
        contract_address_to_felt252, contract_address_try_from_felt252
    };
    use carmine_protocol::amm_core::state::State::{
        get_available_options, get_option_volatility, get_pool_volatility_adjustment_speed,
        get_available_lptoken_addresses
    };

    use carmine_protocol::types::option_::{
        Option_, Option_Trait, OptionWithPremia, OptionWithUsersPosition
    };
    use carmine_protocol::types::pool::{UserPoolInfo, PoolInfo, PoolInfoTrait, PoolTrait, Pool};

    use carmine_protocol::types::basic::{LPTAddress, Int};

    use carmine_protocol::amm_core::helpers::fromU256_balance;


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
        };

        arr
    }

    fn get_all_non_expired_options_with_premia(lpt_addr: LPTAddress) -> Array<OptionWithPremia> {
        let mut i: u32 = 0;
        let current_block_time = get_block_timestamp();
        let mut arr = ArrayTrait::<OptionWithPremia>::new();

        loop {
            let opt = get_available_options(lpt_addr, i);

            if opt.sum() == 0 {
                // This means we've reached the end, so break
                break;
            }

            if !(opt.maturity > current_block_time) {
                continue;
            }

            let total_premia = opt.premia_with_fees(1, // TODO: Resolve this type
             );

            arr.append(OptionWithPremia { option: opt, premia: total_premia });
        };
        arr
    }

    fn get_option_with_position_of_user(
        user_address: ContractAddress
    ) -> Array<OptionWithUsersPosition> {
        let mut pool_idx: felt252 = 0;
        let mut opt_idx: u32 = 0;
        let mut arr = ArrayTrait::<OptionWithUsersPosition>::new();

        loop {
            let lptoken_addr = get_available_lptoken_addresses(pool_idx);
            if contract_address_to_felt252(lptoken_addr) == 0 {
                break;
            }

            loop {
                let option = get_available_options(lptoken_addr, opt_idx);

                if option.sum() == 0 {
                    pool_idx += 1;
                    opt_idx = 0;
                    break;
                }

                let pos_size = IERC20Dispatcher {
                    contract_address: option.opt_address()
                }.balanceOf(user_address);

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

    fn get_all_lptoken_addresses() -> Array<ContractAddress> {
        let mut i: felt252 = 0;
        let mut arr = ArrayTrait::<ContractAddress>::new();

        loop {
            let lpt_addr = get_available_lptoken_addresses(i);

            if contract_address_to_felt252(lpt_addr) == 0 {
                break;
            }

            i += 1;
            arr.append(lpt_addr);
        };

        arr
    }

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

    // fn get_option_info_from_addresses(lptoken, optiontoken) // TODO: Do we even need this?

    fn get_total_premia(option: Option_, position_size: u256, is_closing: bool) -> (Fixed, Fixed) {
        let correct_option = option.correct_side(is_closing);
        let pos_size_int: Int = position_size.try_into().unwrap();

        (
            correct_option.premia_before_fees(pos_size_int),
            correct_option.premia_with_fees(pos_size_int)
        )
    }
}

