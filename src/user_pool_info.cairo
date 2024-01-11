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
    use carmine_protocol::types::pool::PoolTrait;
    use carmine_protocol::types::pool::PoolInfoTrait;
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
            let pool_info = PoolTrait::from_lpt_address(lpt_addr).to_PoolInfo();
            pool_info.to_UserPoolInfo(user)
        }
    }
}

