use starknet::ContractAddress;
use carmine_protocol::types::option_::OptionWithPremia;

#[starknet::interface]
trait IAuxContract<TContractState> {
    fn get_all_non_expired_options_with_premia(
        self: @TContractState, lpt_addr: ContractAddress
    ) -> Array<OptionWithPremia>;
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

    use carmine_protocol::amm_core::constants::{
        TOKEN_USDC_ADDRESS, TOKEN_ETH_ADDRESS, TOKEN_WBTC_ADDRESS
    };

    #[storage]
    struct Storage {}

    const AMM_ADDR: felt252 = 0x01007d87af0a2b9b6199f5f09ab9c230f415470eeceb5a8b01590c51229da562;


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
    }
}

