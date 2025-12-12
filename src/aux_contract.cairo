use starknet::ContractAddress;
use carmine_protocol::types::option_::OptionWithPremia;
use carmine_protocol::types::pool::{UserPoolInfo, PoolState};
use carmine_protocol::types::option_::{OptionWithAddress, OptionWithUsersPosition};
use carmine_protocol::types::price::Price;

#[starknet::interface]
trait IAuxContract<TContractState> {
    fn get_all_non_expired_options_with_premia(
        self: @TContractState, lpt_addr: ContractAddress
    ) -> Array<OptionWithPremia>;
    fn get_user_pool_info(
        self: @TContractState, user: ContractAddress, lpt_addr: ContractAddress
    ) -> UserPoolInfo;
    fn get_pool_state(self: @TContractState, lpt_addr: ContractAddress) -> PoolState;
    fn get_all_pools_states(self: @TContractState) -> Array<PoolState>;
    fn get_pool_options_with_address(
        self: @TContractState, lpt_addr: ContractAddress
    ) -> Array<OptionWithAddress>;
    fn get_price(self: @TContractState, token_address: ContractAddress) -> Price;
    fn get_all_token_prices(self: @TContractState) -> Array<Price>;
    fn get_option_with_position_of_user(
        self: @TContractState, user_address: ContractAddress, lp_address: ContractAddress
    ) -> Array<OptionWithUsersPosition>;
}

#[starknet::contract]
mod AuxContract {
    use core::zeroable::Zeroable;
    use core::traits::Into;
    use core::array::ArrayTrait;
    use starknet::ContractAddress;
    use starknet::get_block_timestamp;
    use starknet::contract_address_const;

    use carmine_protocol::types::option_::OptionWithPremia;
    use carmine_protocol::types::option_::Option_Trait;
    use carmine_protocol::amm_interface::IAMM;
    use carmine_protocol::amm_interface::{IAMMDispatcher, IAMMDispatcherTrait};
    use carmine_protocol::types::option_::{OptionWithAddress, OptionWithUsersPosition};
    use carmine_protocol::types::pool::{UserPoolInfo, PoolState};
    use carmine_protocol::types::pool::{PoolInfo, Pool};
    use carmine_protocol::erc20_interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use cubit::f128::types::fixed::{Fixed, FixedTrait};
    use carmine_protocol::amm_core::state::State;
    use carmine_protocol::amm_core::constants::{
        TOKEN_USDC_ADDRESS, TOKEN_ETH_ADDRESS, TOKEN_WBTC_ADDRESS, TOKEN_STRK_ADDRESS,
        TOKEN_EKUBO_ADDRESS
    };
    use carmine_protocol::types::price::Price;
    use carmine_protocol::amm_core::helpers::pow;
    use carmine_protocol::tokens::option_token::IOptionTokenDispatcher;
    use carmine_protocol::tokens::option_token::IOptionTokenDispatcherTrait;

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

            let underlying_token_address = amm.get_underlying_token_address(lpt_addr);
            assert(underlying_token_address.is_non_zero(), 'Invalid token address');
            let decimals = IERC20Dispatcher { contract_address: underlying_token_address }
                .decimals();
            let base = pow(10, decimals.into());

            let locked = amm.get_pool_locked_capital(lpt_addr);
            let unlocked = amm.get_unlocked_capital(lpt_addr);
            let balance = amm.get_lpool_balance(lpt_addr);
            let position = amm.get_value_of_pool_position(lpt_addr);
            let value = amm.get_lptokens_for_underlying(lpt_addr, base.into());

            PoolState { locked, unlocked, balance, position, value, lp_address: lpt_addr }
        }

        fn get_all_pools_states(self: @ContractState) -> Array<PoolState> {
            let amm = IAMMDispatcher { contract_address: AMM_ADDR.try_into().unwrap() };
            let mut i: felt252 = 0;
            let mut arr = ArrayTrait::<PoolState>::new();

            loop {
                let lpt_addr = amm.get_available_lptoken_addresses(i);

                if lpt_addr.is_zero() {
                    break;
                }

                i += 1;
                arr.append(self.get_pool_state(lpt_addr));
            };

            arr
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
                let opt_address = amm
                    .get_option_token_address(
                        lpt_addr, opt.option_side, opt.maturity, opt.strike_price
                    );
                arr
                    .append(
                        OptionWithAddress {
                            option_side: opt.option_side,
                            maturity: opt.maturity,
                            strike_price: opt.strike_price,
                            address: opt_address,
                        }
                    );
            };

            arr
        }

        fn get_price(self: @ContractState, token_address: ContractAddress) -> Price {
            let amm = IAMMDispatcher { contract_address: AMM_ADDR.try_into().unwrap() };
            let price = amm
                .get_current_price(TOKEN_USDC_ADDRESS.try_into().unwrap(), token_address);
            Price { token_address, price: price.mag }
        }

        fn get_all_token_prices(self: @ContractState) -> Array<Price> {
            let mut arr = ArrayTrait::<Price>::new();

            arr.append(self.get_price(TOKEN_ETH_ADDRESS.try_into().unwrap()));
            arr.append(self.get_price(TOKEN_WBTC_ADDRESS.try_into().unwrap()));
            arr.append(self.get_price(TOKEN_STRK_ADDRESS.try_into().unwrap()));
            arr.append(self.get_price(TOKEN_EKUBO_ADDRESS.try_into().unwrap()));

            // USDC price in USDC is 1
            arr
                .append(
                    Price {
                        token_address: TOKEN_USDC_ADDRESS.try_into().unwrap(),
                        price: FixedTrait::ONE().mag
                    }
                );

            arr
        }

        // @notice Getter for list of all options with position of a given user(if they have any)
        // @param user_address: user's address
        // @return array: Array of OptionWithUsersPosition
        fn get_option_with_position_of_user(
            self: @ContractState, user_address: ContractAddress, lp_address: ContractAddress
        ) -> Array<OptionWithUsersPosition> {
            let amm = IAMMDispatcher { contract_address: AMM_ADDR.try_into().unwrap() };
            let mut opt_idx: u32 = 0;
            let mut arr = ArrayTrait::<OptionWithUsersPosition>::new();

            loop {
                let option = amm.get_available_options(lp_address, opt_idx);

                if option.sum() == 0 {
                    break;
                }

                let pos_size = IOptionTokenDispatcher { contract_address: option.opt_address() }
                    .balance_of(user_address);

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

            arr
        }
    }
}
