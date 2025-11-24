use starknet::ContractAddress;
use carmine_protocol::types::option_::OptionWithPremia;
use carmine_protocol::types::pool::{UserPoolInfo, PoolState};
use carmine_protocol::types::option_::OptionWithAddress;

#[starknet::interface]
trait IAuxContract<TContractState> {
    fn get_all_non_expired_options_with_premia(
        self: @TContractState, lpt_addr: ContractAddress
    ) -> Array<OptionWithPremia>;
    fn get_user_pool_info(
        self: @TContractState, user: ContractAddress, lpt_addr: ContractAddress
    ) -> UserPoolInfo;
    fn get_pool_state(self: @TContractState, lpt_addr: ContractAddress) -> PoolState;
    fn get_pool_options_with_address(
        self: @TContractState, lpt_addr: ContractAddress
    ) -> Array<OptionWithAddress>;
}

#[starknet::contract]
mod AuxContract {
    use starknet::ContractAddress;
    use starknet::get_block_timestamp;
    use starknet::contract_address_const;

    use carmine_protocol::types::option_::OptionWithPremia;
    use carmine_protocol::types::option_::Option_Trait;
    use carmine_protocol::amm_interface::IAMM;
    use carmine_protocol::amm_interface::{IAMMDispatcher, IAMMDispatcherTrait};
    use carmine_protocol::types::option_::OptionWithAddress;
    use carmine_protocol::types::pool::{UserPoolInfo, PoolState};
    use carmine_protocol::types::pool::{PoolInfo, Pool};
    use carmine_protocol::erc20_interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use cubit::f128::types::fixed::{Fixed, FixedTrait};

    use carmine_protocol::amm_core::constants::{
        TOKEN_USDC_ADDRESS, TOKEN_ETH_ADDRESS, TOKEN_WBTC_ADDRESS
    };


    #[generate_trait]
    impl PoolImpl of PoolTrait {
        fn from_lpt_address(lpt_addr: ContractAddress, amm: IAMMDispatcher) -> Pool {
            amm.get_pool_definition_from_lptoken_address(lpt_addr)
        }

        fn lpt_addr(self: Pool, amm: IAMMDispatcher) -> ContractAddress {
            amm
                .get_lptoken_address_for_given_option(
                    self.quote_token_address, self.base_token_address, self.option_type
                )
        }

        fn lpool_balance(self: Pool, amm: IAMMDispatcher) -> u256 {
            amm.get_lpool_balance(self.lpt_addr(amm))
        }

        fn unlocked_capital(self: Pool, amm: IAMMDispatcher) -> u256 {
            amm.get_unlocked_capital(self.lpt_addr(amm))
        }

        fn value_of_position(self: Pool, amm: IAMMDispatcher) -> Fixed {
            amm.get_value_of_pool_position(self.lpt_addr(amm))
        }

        fn to_PoolInfo(self: Pool, amm: IAMMDispatcher) -> PoolInfo {
            PoolInfo {
                pool: self,
                lptoken_address: self.lpt_addr(amm),
                staked_capital: self.lpool_balance(amm),
                unlocked_capital: self.unlocked_capital(amm),
                value_of_pool_position: self.value_of_position(amm)
            }
        }
    }
    #[generate_trait]
    impl PoolInfoImpl of PoolInfoTrait {
        fn to_UserPoolInfo(
            self: PoolInfo, user_address: ContractAddress, amm: IAMMDispatcher
        ) -> UserPoolInfo {
            let lptoken_balance = IERC20Dispatcher { contract_address: self.lptoken_address }
                .balanceOf(user_address);

            let stake_value = amm
                .get_underlying_for_lptokens(self.lptoken_address, lptoken_balance);

            UserPoolInfo {
                value_of_user_stake: stake_value,
                size_of_users_tokens: lptoken_balance,
                pool_info: self
            }
        }
    }


    #[storage]
    struct Storage {}

    const AMM_ADDR: felt252 = 0x047472e6755afc57ada9550b6a3ac93129cc4b5f98f51c73e0644d129fd208d9;


    #[external(v0)]
    impl AuxContract of super::IAuxContract<ContractState> {
        fn get_all_non_expired_options_with_premia(
            self: @ContractState, lpt_addr: ContractAddress
        ) -> Array<OptionWithPremia> {
            let amm = IAMMDispatcher { contract_address: AMM_ADDR.try_into().unwrap() };
            let pool = amm.get_pool_definition_from_lptoken_address(lpt_addr);
            let base: felt252 = pool.base_token_address.into();

            let opt_size = if base == TOKEN_ETH_ADDRESS {
                1000000000000000000 // 10**18 * 1
            } else {
                10000000 // 10**8 * 0.1
            };

            let mut i: u32 = 0;
            let current_block_time = get_block_timestamp();
            let mut arr = ArrayTrait::<OptionWithPremia>::new();

            loop {
                let opt = amm.get_available_options(lpt_addr, i);
                i += 1;

                if opt.sum() == 0 {
                    // This means we've reached the end, so break
                    break;
                }

                if !(opt.maturity > current_block_time) {
                    continue;
                }

                let (_, total_premia_with_fees) = amm.get_total_premia(opt, opt_size, false);

                arr.append(OptionWithPremia { option: opt, premia: total_premia_with_fees });
            };

            arr
        }

        fn get_user_pool_info(
            self: @ContractState, user: ContractAddress, lpt_addr: ContractAddress
        ) -> UserPoolInfo {
            let amm = IAMMDispatcher { contract_address: AMM_ADDR.try_into().unwrap() };
            let pool_info = PoolTrait::from_lpt_address(lpt_addr, amm).to_PoolInfo(amm);
            pool_info.to_UserPoolInfo(user, amm)
        }

        fn get_pool_state(self: @ContractState, lpt_addr: ContractAddress) -> PoolState {
            let amm = IAMMDispatcher { contract_address: AMM_ADDR.try_into().unwrap() };
            let locked = amm.get_pool_locked_capital(lpt_addr);
            let unlocked = amm.get_unlocked_capital(lpt_addr);
            let balance = amm.get_lpool_balance(lpt_addr);
            let position = amm.get_value_of_pool_position(lpt_addr);
            let value = amm
                .get_lptokens_for_underlying(
                    lpt_addr, 1000000000000000000
                ); // 10**18 - get value of size 1

            PoolState { locked, unlocked, balance, position, value, }
        }

        fn get_pool_options_with_address(
            self: @ContractState, lpt_addr: ContractAddress
        ) -> Array<OptionWithAddress> {
            let amm = IAMMDispatcher { contract_address: AMM_ADDR.try_into().unwrap() };

            let mut i: u32 = 0;
            let mut arr = ArrayTrait::<OptionWithAddress>::new();

            loop {
                let opt = amm.get_available_options(lpt_addr, i);
                i += 1;
                if opt.sum() == 0 {
                    // This means we've reached the end, so break
                    break;
                }
                let opt_address = opt.opt_address();
                arr
                    .append(
                        OptionWithAddress {
                            option_side: opt.option_side,
                            maturity: opt.maturity,
                            strike_price: opt.strike_price,
                            option_type: opt.option_type,
                            address: opt_address,
                        }
                    );
            };

            arr
        }
    }
}
