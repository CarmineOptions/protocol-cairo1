mod Pragma {
    use starknet::get_block_timestamp;
    use starknet::ContractAddress;
    use starknet::contract_address::contract_address_const;
    use traits::{TryInto, Into};
    use option::OptionTrait;

    use cubit::f128::types::fixed::{Fixed, FixedTrait};

    use super::PragmaUtils;
    use super::PragmaUtils::IOracleABIDispatcher;
    use super::PragmaUtils::IOracleABIDispatcherTrait;
    use super::PragmaUtils::DataType;
    use super::PragmaUtils::PragmaPricesResponse;
    use super::PragmaUtils::AggregationMode;
    use super::PragmaUtils::Checkpoint;

    use carmine_protocol::amm_core::oracles::oracle_helpers::{convert_from_int_to_Fixed};
    use carmine_protocol::types::basic::{Timestamp};


    use carmine_protocol::amm_core::constants::{
        TOKEN_USDC_ADDRESS, TOKEN_ETH_ADDRESS, TOKEN_WBTC_ADDRESS, TOKEN_STRK_ADDRESS
    };

    // Mainnet
    // const PRAGMA_ORACLE_ADDRESS: felt252 =
    //     0x2a85bd616f912537c50a49a4076db02c00b29b2cdc8a197ce92ed1837fa875b; // C1 version
    const PRAGMA_ORACLE_ADDRESS: felt252 =
        0x036031daa264c24520b11d93af622c848b2499b66b41d611bac95e13cfca131a; // sepolia

    // @notice Returns Pragma key identifier for stablecoins
    // @param quote_token_addr: Address of given stablecoin 
    // @return stablecoin_key: Stablecoin key identifier
    fn _get_stablecoin_key(quote_token_addr: ContractAddress) -> Option<felt252> {
        if quote_token_addr == TOKEN_USDC_ADDRESS
            .try_into()
            .expect('Pragma/GSK - Failed to convert') {
            Option::Some(PragmaUtils::PRAGMA_USDC_USD_KEY)
        } else {
            Option::None(())
        }
    }

    // @notice Returns Pragma key identifier for spot pairs
    // @param quote_token_addr: Address of quote token in given ticker
    // @param base_token_addr: Address of base token in given ticker
    // @return stablecoin_key: Spot pair key identifier
    fn _get_ticker_key(
        quote_token_addr: ContractAddress, base_token_addr: ContractAddress
    ) -> felt252 {
        if base_token_addr.into() == TOKEN_ETH_ADDRESS {
            if quote_token_addr.into() == TOKEN_USDC_ADDRESS {
                PragmaUtils::PRAGMA_ETH_USD_KEY
            } else {
                0
            }
        } else if base_token_addr.into() == TOKEN_WBTC_ADDRESS {
            if quote_token_addr.into() == TOKEN_USDC_ADDRESS {
                PragmaUtils::PRAGMA_WBTC_USD_KEY
            } else {
                0
            }
        } else if base_token_addr.into() == TOKEN_STRK_ADDRESS {
            if quote_token_addr.into() == TOKEN_USDC_ADDRESS {
                PragmaUtils::PRAGMA_STRK_USD_KEY
            } else {
                0
            }
        } else {
            0
        }
    }

    // @notice Returns current Pragma median price for given key
    // @dev This function does not account for stablecoin divergence
    // @param key: Pragma key identifier
    // @return median_price: Pragma current median price in Fixed
    fn _get_pragma_median_price(key: felt252) -> Fixed {
        let res: PragmaPricesResponse = IOracleABIDispatcher {
            contract_address: PRAGMA_ORACLE_ADDRESS.try_into().expect('Pragma/_GPMP - Cant convert')
        }
            .get_data(DataType::SpotEntry(key), AggregationMode::Median(()));

        let curr_time = get_block_timestamp();
        let time_diff = if curr_time < res.last_updated_timestamp {
            0
        } else {
            curr_time - res.last_updated_timestamp
        };

        assert(time_diff < 3600, 'Pragma/_GPMP - Price too old');

        convert_from_int_to_Fixed(
            res.price, res.decimals.try_into().expect('Pragma/_GPMP - decimals err')
        )
    }

    // @notice Returns current Pragma median price for given key
    // @dev This function accounts for stablecoin divergence
    // @param quote_token_addr: Address of quote token in given ticker
    // @param base_token_addr: Address of base token in given ticker
    // @return median_price: Pragma current median price in Fixed
    fn get_pragma_median_price(
        quote_token_addr: ContractAddress, base_token_addr: ContractAddress,
    ) -> Fixed {
        // STRK/ETH gets special treatment
        if base_token_addr.into() == TOKEN_ETH_ADDRESS
            && quote_token_addr.into() == TOKEN_STRK_ADDRESS {
            let eth_in_usd = _get_pragma_median_price(PragmaUtils::PRAGMA_ETH_USD_KEY);
            let strk_in_usd = _get_pragma_median_price(PragmaUtils::PRAGMA_STRK_USD_KEY);

            let eth_in_strk = eth_in_usd / strk_in_usd;

            return eth_in_strk;
        } else {
            let key = _get_ticker_key(quote_token_addr, base_token_addr);

            let res = _get_pragma_median_price(key);
            account_for_stablecoin_divergence(res, quote_token_addr, 0)
        }
    }


    // @notice Returns terminal Pragma median price for given key
    // @dev This function does not account for stablecoin divergence
    // @param key: Pragma key identifier
    // @param maturity: Timestamp for which to get the terminal price
    // @return median_price: Pragma terminal median price in Fixed
    fn _get_pragma_terminal_price(key: felt252, maturity: Timestamp) -> Fixed {
        let (res, _) = IOracleABIDispatcher {
            contract_address: PRAGMA_ORACLE_ADDRESS.try_into().expect('Pragma/_GPMP - Cant convert')
        }
            .get_last_checkpoint_before(
                DataType::SpotEntry(key), maturity, AggregationMode::Median(())
            );

        let decs = IOracleABIDispatcher {
            contract_address: PRAGMA_ORACLE_ADDRESS.try_into().expect('Pragma/_GPMP - Cant convert')
        }
            .get_decimals(DataType::SpotEntry(key));

        assert(decs > 0, 'Pragma/GPTP - decs zero');

        let time_diff = maturity - res.timestamp;

        assert(time_diff < 7200, 'Pragma/GPTP - Term price old');
        assert(res.value > 0_u128, 'Pragma/GPTP - Price <= 0');
        convert_from_int_to_Fixed(res.value, decs.try_into().unwrap())
    }


    // @notice Returns terminal Pragma median price for given key
    // @dev This function accounts for stablecoin divergence
    // @param quote_token_addr: Address of quote token in given ticker
    // @param base_token_addr: Address of base token in given ticker
    // @param maturity: Timestamp for which to get the terminal price
    // @return median_price: Pragma terminal median price in Fixed
    fn get_pragma_terminal_price(
        quote_token_addr: ContractAddress, base_token_addr: ContractAddress, maturity: Timestamp
    ) -> Fixed {
        if base_token_addr.into() == TOKEN_ETH_ADDRESS
            && quote_token_addr.into() == TOKEN_STRK_ADDRESS {
            let eth_in_usd = _get_pragma_terminal_price(PragmaUtils::PRAGMA_ETH_USD_KEY, maturity);
            let strk_in_usd = _get_pragma_terminal_price(
                PragmaUtils::PRAGMA_STRK_USD_KEY, maturity
            );

            let eth_in_strk = eth_in_usd / strk_in_usd;

            return eth_in_strk;
        } else {
            let key = _get_ticker_key(quote_token_addr, base_token_addr);
            let res = _get_pragma_terminal_price(key, maturity);
            return account_for_stablecoin_divergence(res, quote_token_addr, maturity);
        }
    }

    // @notice Takes in current or terminal price and returns it after accounting for stablecoin divergence
    // @param price: Current or terminal price, Fixed
    // @param quote_token_addr: Address of quote token in given ticker
    // @param maturity: Timestamp for which to get the terminal price if its used, "0" for spot price
    // @return price: Price, accounted for stablecoin divergence
    fn account_for_stablecoin_divergence(
        price: Fixed, quote_token_addr: ContractAddress, maturity: Timestamp
    ) -> Fixed {
        let key = _get_stablecoin_key(quote_token_addr);

        match key {
            Option::Some(key) => {
                let stable_coin_price = if maturity == 0 {
                    _get_pragma_median_price(key)
                } else {
                    _get_pragma_terminal_price(key, maturity)
                };
                return price / stable_coin_price;
            },
            // If key is zero, it means that quote_token isn't stablecoin(or at least one we use)
            Option::None(_) => { return price; }
        }
    }

    // @notice Calls Pragma to set checkpoint
    // @param key: Pragma key identifier
    fn set_pragma_checkpoint(key: felt252) {
        IOracleABIDispatcher {
            contract_address: PRAGMA_ORACLE_ADDRESS.try_into().expect('Pragma/_GPMP - Cant convert')
        }
            .set_checkpoint(DataType::SpotEntry(key), AggregationMode::Median(()))
    }

    // @notice Calls Pragma to set checkpoints we use
    fn set_pragma_required_checkpoints() {
        // Just add needed checkpoints here
        set_pragma_checkpoint(PragmaUtils::PRAGMA_ETH_USD_KEY);
        set_pragma_checkpoint(PragmaUtils::PRAGMA_USDC_USD_KEY);
        set_pragma_checkpoint(PragmaUtils::PRAGMA_WBTC_USD_KEY);
        set_pragma_checkpoint(PragmaUtils::PRAGMA_STRK_USD_KEY);
    }
}

/////////////////////
// Pragma Structs/Abi
/////////////////////

mod PragmaUtils {
    #[starknet::interface]
    trait IOracleABI<TContractState> {
        fn get_decimals(self: @TContractState, data_type: DataType) -> u32;
        fn get_data(
            self: @TContractState, data_type: DataType, aggregation_mode: AggregationMode
        ) -> PragmaPricesResponse;
        fn get_last_checkpoint_before(
            self: @TContractState,
            data_type: DataType,
            timestamp: u64,
            aggregation_mode: AggregationMode,
        ) -> (Checkpoint, u64);
        fn set_checkpoint(
            ref self: TContractState, data_type: DataType, aggregation_mode: AggregationMode
        );
    }

    #[derive(Drop, Copy, Serde)]
    enum DataType {
        SpotEntry: felt252,
        FutureEntry: (felt252, u64),
        GenericEntry: felt252,
    }

    #[derive(Serde, Drop, Copy)]
    struct PragmaPricesResponse {
        price: u128,
        decimals: u32,
        last_updated_timestamp: u64,
        num_sources_aggregated: u32,
        expiration_timestamp: Option<u64>,
    }

    #[derive(Serde, Drop)]
    struct Checkpoint {
        timestamp: u64,
        value: u128,
        aggregation_mode: AggregationMode,
        num_sources_aggregated: u32,
    }

    #[derive(Serde, Drop, Copy)]
    enum AggregationMode {
        Median: (),
        Mean: (),
        Error: (),
    }

    // Pragma keys
    // Spot
    const PRAGMA_WBTC_USD_KEY: felt252 = 6287680677296296772;
    const PRAGMA_ETH_USD_KEY: felt252 = 19514442401534788;
    const PRAGMA_SOL_USD_KEY: felt252 = 23449611697214276;
    const PRAGMA_AVAX_USD_KEY: felt252 = 4708022307469480772;
    const PRAGMA_DOGE_USD_KEY: felt252 = 4922231280211678020;
    const PRAGMA_SHIB_USD_KEY: felt252 = 6001127052081976132;
    const PRAGMA_BNB_USD_KEY: felt252 = 18663394631832388;
    const PRAGMA_ADA_USD_KEY: felt252 = 18370920243876676;
    const PRAGMA_XRP_USD_KEY: felt252 = 24860302295520068;
    const PRAGMA_MATIC_USD_KEY: felt252 = 1425106761739050242884;
    const PRAGMA_STRK_USD_KEY: felt252 = 6004514686061859652;

    // Stablecoins
    const PRAGMA_USDT_USD_KEY: felt252 = 6148333044652921668;
    const PRAGMA_DAI_USD_KEY: felt252 = 19212080998863684;
    const PRAGMA_USDC_USD_KEY: felt252 = 6148332971638477636;
}
