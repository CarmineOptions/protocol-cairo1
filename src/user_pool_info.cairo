use starknet::ContractAddress;
use carmine_protocol::types::pool::UserPoolInfo;

#[starknet::interface]
trait IUserPoolInfoContract<TContractState> {
    fn get_user_pool_info(
        self: @TContractState, user: ContractAddress, lpt_addr: ContractAddress
    ) -> UserPoolInfo;
}

#[starknet::contract]
mod UserPoolInfoContract {
    use starknet::ContractAddress;

    use carmine_protocol::types::pool::UserPoolInfo;
    use carmine_protocol::types::pool::{PoolInfo, Pool};
    use carmine_protocol::erc20_interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use cubit::f128::types::fixed::{Fixed, FixedTrait};

    #[generate_trait]
    impl PoolImpl of PoolTrait {
        fn from_lpt_address(lpt_addr: ContractAddress, amm: IAMMDispatcher) -> Pool {
            amm.get_pool_definition_from_lptoken_address(lpt_addr)
        }

        fn lpt_addr(self: Pool, amm: IAMMDispatcher) -> ContractAddress {
            amm.get_lptoken_address_for_given_option(
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
    use carmine_protocol::amm_interface::IAMM;
    use carmine_protocol::amm_interface::{IAMMDispatcher, IAMMDispatcherTrait};

    use carmine_protocol::amm_core::constants::{
        TOKEN_USDC_ADDRESS, TOKEN_ETH_ADDRESS, TOKEN_WBTC_ADDRESS
    };

    #[storage]
    struct Storage {}

    const AMM_ADDR: felt252 = 0x02614962c68c76e51d622aa3f57445a980802f02be340d3c7cdc6c0c7bda5ef5;


    #[external(v0)]
    impl UserPoolInfoContract of super::IUserPoolInfoContract<ContractState> {
        fn get_user_pool_info(
            self: @ContractState, user: ContractAddress, lpt_addr: ContractAddress
        ) -> UserPoolInfo {
            let amm = IAMMDispatcher { contract_address: AMM_ADDR.try_into().unwrap() };
            let pool_info = PoolTrait::from_lpt_address(lpt_addr, amm).to_PoolInfo(amm);
            pool_info.to_UserPoolInfo(user, amm)
        }
    }
}

