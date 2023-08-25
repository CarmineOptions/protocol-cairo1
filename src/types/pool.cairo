use carmine_protocol::traits::{IERC20Dispatcher, IERC20DispatcherTrait};
use cubit::f128::types::fixed::{Fixed, FixedTrait};
use starknet::ContractAddress;
use carmine_protocol::types::basic::OptionType;

use carmine_protocol::amm_core::state::State::{
    get_lptoken_address_for_given_option, get_lpool_balance, get_unlocked_capital,
    get_pool_definition_from_lptoken_address
};

use carmine_protocol::amm_core::liquidity_pool::LiquidityPool::{
    get_value_of_pool_position, get_underlying_for_lptokens
};

#[derive(Copy, Drop, Serde, starknet::Store)]
struct Pool {
    quote_token_address: ContractAddress,
    base_token_address: ContractAddress,
    option_type: OptionType,
}

#[generate_trait]
impl PoolImpl of PoolTrait {
    fn from_lpt_address(lpt_addr: ContractAddress) -> Pool {
        get_pool_definition_from_lptoken_address(lpt_addr)
    }

    fn lpt_addr(self: Pool) -> ContractAddress {
        get_lptoken_address_for_given_option(
            self.quote_token_address, self.base_token_address, self.option_type
        )
    }

    fn lpool_balance(self: Pool) -> u256 {
        get_lpool_balance(self.lpt_addr())
    }

    fn unlocked_capital(self: Pool) -> u256 {
        get_unlocked_capital(self.lpt_addr())
    }

    fn value_of_position(self: Pool) -> Fixed {
        get_value_of_pool_position(self.lpt_addr())
    }

    fn to_PoolInfo(self: Pool) -> PoolInfo {
        PoolInfo {
            pool: self,
            lptoken_address: self.lpt_addr(),
            staked_capital: self.lpool_balance(),
            unlocked_capital: self.unlocked_capital(),
            value_of_pool_position: self.value_of_position()
        }
    }
}


#[derive(Drop, Serde)]
struct PoolInfo {
    pool: Pool,
    lptoken_address: ContractAddress,
    staked_capital: u256, // lpool_balance
    unlocked_capital: u256,
    value_of_pool_position: Fixed
}

#[generate_trait]
impl PoolInfoImpl of PoolInfoTrait {
    fn to_UserPoolInfo(self: PoolInfo, user_address: ContractAddress) -> UserPoolInfo {
        let lptoken_balance = IERC20Dispatcher {
            contract_address: self.lptoken_address
        }.balanceOf(user_address);

        let stake_value = get_underlying_for_lptokens(self.lptoken_address, lptoken_balance);

        UserPoolInfo {
            value_of_user_stake: stake_value, size_of_users_tokens: lptoken_balance, pool_info: self
        }
    }
}

#[derive(Drop, Serde)]
struct UserPoolInfo {
    value_of_user_stake: u256,
    size_of_users_tokens: u256,
    pool_info: PoolInfo
}
