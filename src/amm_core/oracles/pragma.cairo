mod Pragma {
    use starknet::get_block_timestamp;

    use carmine_protocol::traits::{IPragmaOracleDispatcher, IPragmaOracleDispatcherTrait};
    use super::PragmaUtils::{IOracleABIDispatcher, IOracleABIDispatcherTrait, DataType, PragmaPricesResponse, AggregationMode, Checkpoint};

    use carmine_protocol::amm_core::oracles::oracle_helpers::{convert_from_int_to_Fixed};
    use carmine_protocol::types::basic::{Timestamp};

    use starknet::ContractAddress;
    use starknet::contract_address::contract_address_const;
    use traits::{TryInto, Into};
    use option::OptionTrait;

    use cubit::f128::types::fixed::{Fixed, FixedTrait};

    use carmine_protocol::amm_core::constants::{TOKEN_USDC_ADDRESS, TOKEN_ETH_ADDRESS};

    // Mainnet
    // const PRAGMA_ORACLE_ADDRESS: felt252 =
    //     0x0346c57f094d641ad94e43468628d8e9c574dcb2803ec372576ccc60a40be2c4;

    // Testnet TODO: Check before mainnet launch
    const PRAGMA_ORACLE_ADDRESS: felt252 = 
        0x1ab2b1d9d084ed2c9fe185ac32b3bc7fa42f85e129b97459b4fe315f4247978; // C1 version

    const PRAGMA_AGGREGATION_MODE: felt252 = 0; // 0 is default for median

    const PRAGMA_BTC_USD_KEY: felt252 = 18669995996566340;
    const PRAGMA_ETH_USD_KEY: felt252 = 19514442401534788;
    const PRAGMA_SOL_USD_KEY: felt252 = 23449611697214276;
    const PRAGMA_AVAX_USD_KEY: felt252 = 4708022307469480772;
    const PRAGMA_DOGE_USD_KEY: felt252 = 4922231280211678020;
    const PRAGMA_SHIB_USD_KEY: felt252 = 6001127052081976132;
    const PRAGMA_BNB_USD_KEY: felt252 = 18663394631832388;
    const PRAGMA_ADA_USD_KEY: felt252 = 18370920243876676;
    const PRAGMA_XRP_USD_KEY: felt252 = 24860302295520068;
    const PRAGMA_MATIC_USD_KEY: felt252 = 1425106761739050242884;

    // Stablecoins
    const PRAGMA_USDT_USD_KEY: felt252 = 6148333044652921668;
    const PRAGMA_DAI_USD_KEY: felt252 = 19212080998863684;
    const PRAGMA_USDC_USD_KEY: felt252 = 6148332971638477636;

    #[derive(Copy, Drop, Serde)]
    struct PragmaCheckpoint {
        timestamp: felt252,
        value: felt252,
        aggregation_mode: felt252,
        num_sources_aggregated: felt252,
    }


    fn _get_stablecoin_key(quote_token_addr: ContractAddress) -> Option<felt252> {
        
        if quote_token_addr == TOKEN_USDC_ADDRESS
            .try_into()
            .expect('Pragma/GSK - Failed to convert') {
            Option::Some(PRAGMA_USDC_USD_KEY)
        } else {
            Option::None(())
        }
    }

    fn _get_ticker_key(
        quote_token_addr: ContractAddress, base_token_addr: ContractAddress
    ) -> felt252 {
        if base_token_addr == TOKEN_ETH_ADDRESS
            .try_into()
            .expect('Pragma/GTK - Failed to convert') {
            if quote_token_addr == TOKEN_USDC_ADDRESS
                .try_into()
                .expect('Pragma/GTK - Failed to convert') {
                PRAGMA_ETH_USD_KEY
            } else {
                0
            }
        } else {
            0
        }
    }

    use debug::PrintTrait;

    fn _get_pragma_median_price(key: felt252) -> Fixed {

        let res: PragmaPricesResponse = IOracleABIDispatcher {
            contract_address: PRAGMA_ORACLE_ADDRESS.try_into().expect('Pragma/_GPMP - Cant convert')
        }.get_data(DataType::SpotEntry(key), AggregationMode::Median(()));

        let curr_time = get_block_timestamp();
        let time_diff = if curr_time < res.last_updated_timestamp {
            0
        } else {
            curr_time - res.last_updated_timestamp
        };

        assert(time_diff < 3600, 'Pragma/_GPMP - Price too old');
        assert(
            res.price > 0_u128,
            'Pragma/-GPMP - Price <= 0'
        );

        convert_from_int_to_Fixed(res.price, res.decimals.try_into().expect('Pragma/_GPMP - decimals err'))
    }

    fn get_pragma_median_price(
        quote_token_addr: ContractAddress, base_token_addr: ContractAddress,
    ) -> Fixed {
        let key = _get_ticker_key(quote_token_addr, base_token_addr);
        // .expect('Pragma/GPMP - Cant get spot key');
        let res = _get_pragma_median_price(key);
        account_for_stablecoin_divergence(res, quote_token_addr, 0)
    }

    // TODO Check that checkpoint is not after expiry
    fn _get_pragma_terminal_price(key: felt252, maturity: Timestamp) -> Fixed {

        let (res, _) = IOracleABIDispatcher {
            contract_address: PRAGMA_ORACLE_ADDRESS.try_into().expect('Pragma/_GPMP - Cant convert')
        }.get_last_checkpoint_before(DataType::SpotEntry(key), maturity, AggregationMode::Median(()));

        // TODO: Handle negative time diff gracefully, it'll fail with sub overflow
        let time_diff = maturity - res.timestamp;

        assert(time_diff < 7200, 'Pragma/GPTP - Price too old');
        assert(
            res.value > 0_u128,
            'Pragma/GPTP - Price <= 0'
        );

        //  Pragma checkpoints should always have 8 decimals
        convert_from_int_to_Fixed(res.value, 8)
    }

    fn get_pragma_terminal_price(
        quote_token_addr: ContractAddress, base_token_addr: ContractAddress, maturity: Timestamp
    ) -> Fixed {
        let key = _get_ticker_key(quote_token_addr, base_token_addr);
        // .expect('Pragma/GPMP - Cant get spot key');
        let res = _get_pragma_terminal_price(key, maturity);
        account_for_stablecoin_divergence(res, quote_token_addr, maturity)
    }

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
            Option::None(_) => {
                return price;
            }
        }
    }
}

/////////////////////
// Pragma Structs/Abi
/////////////////////

mod PragmaUtils {
    #[starknet::interface]
    trait IOracleABI<TContractState> {
        fn get_data(
            self: @TContractState, data_type: DataType, aggregation_mode: AggregationMode
        ) -> PragmaPricesResponse;
        fn get_last_checkpoint_before(
            self: @TContractState,
            data_type: DataType,
            timestamp: u64,
            aggregation_mode: AggregationMode,
        ) -> (Checkpoint, u64);
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
    
}