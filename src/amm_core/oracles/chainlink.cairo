mod Chainlink {
    use starknet::ContractAddress;


    use cubit::f128::types::fixed::Fixed;
    use cubit::f128::types::fixed::FixedTrait;

    use carmine_protocol::amm_core::constants::TOKEN_USDC_ADDRESS;
    use carmine_protocol::amm_core::constants::TOKEN_ETH_ADDRESS;
    use carmine_protocol::amm_core::constants::TOKEN_WBTC_ADDRESS;
    use carmine_protocol::amm_core::constants::TOKEN_STRK_ADDRESS;

    use carmine_protocol::amm_core::oracles::oracle_helpers::convert_from_int_to_Fixed;

    use super::ChainlinkUtils;

    fn get_chainlink_current_price(
        quote_token_addr: ContractAddress, base_token_addr: ContractAddress,
    ) -> Fixed {
        let base_chainlink_proxy_address = ChainlinkUtils::get_chainlink_proxy_address(
            base_token_addr
        );
        let quote_chainlink_proxy_address = ChainlinkUtils::get_chainlink_proxy_address(
            quote_token_addr
        );

        let base_price = ChainlinkUtils::get_current_price_for_proxy(base_chainlink_proxy_address);
        let quote_price = ChainlinkUtils::get_current_price_for_proxy(
            quote_chainlink_proxy_address
        );

        assert(base_price != 0, 'Unable to fetch base price');
        assert(quote_price != 0, 'Unable to fetch quote price');

        let base_price_fixed = convert_from_int_to_Fixed(
            base_price, ChainlinkUtils::CHAINLINK_DECIMALS
        );
        let quote_price_fixed = convert_from_int_to_Fixed(
            quote_price, ChainlinkUtils::CHAINLINK_DECIMALS
        );

        base_price_fixed / quote_price_fixed
    }
}


mod ChainlinkUtils {
    use starknet::ContractAddress;
    use core::panic_with_felt252;

    use carmine_protocol::amm_core::constants::TOKEN_USDC_ADDRESS;
    use carmine_protocol::amm_core::constants::TOKEN_ETH_ADDRESS;
    use carmine_protocol::amm_core::constants::TOKEN_WBTC_ADDRESS;
    use carmine_protocol::amm_core::constants::TOKEN_STRK_ADDRESS;


    const CHAINLINK_DECIMALS: u8 = 8;

    #[derive(Copy, Drop, Serde, PartialEq, starknet::Store)]
    struct Round {
        round_id: felt252,
        answer: u128,
        block_num: u64,
        started_at: u64,
        updated_at: u64,
    }

    #[starknet::interface]
    trait IAggregatorProxy<TContractState> {
        fn latest_round_data(self: @TContractState) -> Round;
        fn round_data(self: @TContractState, round_id: felt252) -> Round;
        fn description(self: @TContractState) -> felt252;
        fn decimals(self: @TContractState) -> u8;
        fn latest_answer(self: @TContractState) -> u128;
    }

    mod Mainnet {
        const CHAINLINK_WBTC_USD_ADDRESS: felt252 =
            0x6275040a2913e2fe1a20bead3feb40694920a7fea98e956b042e082b9e1adad;
        const CHAINLINK_ETH_USD_ADDRESS: felt252 =
            0x6b2ef9b416ad0f996b2a8ac0dd771b1788196f51c96f5b000df2e47ac756d26;
        const CHAINLINK_STRK_USD_ADDRESS: felt252 =
            0x76a0254cdadb59b86da3b5960bf8d73779cac88edc5ae587cab3cedf03226ec;
        const CHAINLINK_USDC_USD_ADDRESS: felt252 =
            0x72495dbb867dd3c6373820694008f8a8bff7b41f7f7112245d687858b243470;
    }

    mod Testnet {
        const CHAINLINK_BTC_USD_ADDRESS: felt252 = 0;
        const CHAINLINK_ETH_USD_ADDRESS: felt252 = 0;
        const CHAINLINK_STRK_USD_ADDRESS: felt252 = 0;
        const CHAINLINK_USDC_USD_ADDRESS: felt252 = 0;
    }

    fn get_current_price_for_proxy(proxy: ContractAddress) -> u128 {
        let contract = IAggregatorProxyDispatcher { contract_address: proxy };
        contract.latest_round_data().answer
    }

    fn get_chainlink_proxy_address(token_address: ContractAddress) -> ContractAddress {
        let address_felt: felt252 = token_address.into();

        if address_felt == TOKEN_ETH_ADDRESS {
            return Mainnet::CHAINLINK_ETH_USD_ADDRESS.try_into().unwrap();
        }
        if address_felt == TOKEN_WBTC_ADDRESS {
            return Mainnet::CHAINLINK_WBTC_USD_ADDRESS.try_into().unwrap();
        }
        if address_felt == TOKEN_STRK_ADDRESS {
            return Mainnet::CHAINLINK_STRK_USD_ADDRESS.try_into().unwrap();
        }
        if address_felt == TOKEN_USDC_ADDRESS {
            return Mainnet::CHAINLINK_USDC_USD_ADDRESS.try_into().unwrap();
        }

        panic_with_felt252('unknown address for price')
    }
}
