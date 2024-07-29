mod OracleAgg {
    use starknet::ContractAddress;
    use starknet::get_block_info;

    use cubit::f128::types::fixed::{Fixed};

    use carmine_protocol::types::basic::{Timestamp};
    use carmine_protocol::amm_core::oracles::pragma::Pragma::{
        get_pragma_median_price, get_pragma_terminal_price
    };

    use carmine_protocol::amm_core::state::State::{
        read_latest_oracle_price, write_latest_oracle_price
    };

    // @notice Returns current spot price for given ticker (quote and base token)
    // @param quote_token_addr: Address of quote token in given ticker
    // @param base_token_addr: Address of base token in given ticker
    // @return current_price: Current spot price
    fn get_current_price(
        quote_token_addr: ContractAddress, base_token_addr: ContractAddress
    ) -> Fixed {
        let curr_block = get_block_info().unbox().block_number;
        let (last_price, last_price_block_num) = read_latest_oracle_price(
            base_token_addr, quote_token_addr
        );

        if last_price_block_num == curr_block {
            last_price
        } else {
            let price_pragma = get_pragma_median_price(quote_token_addr, base_token_addr);
            write_latest_oracle_price(base_token_addr, quote_token_addr, price_pragma, curr_block);

            price_pragma
        }
    }

    // @notice Returns terminal spot price for given ticker (quote and base token)
    // @dev This function first checks if a price has been cached in the current block.
    //      If so, it returns the cached price to avoid unnecessary oracle calls within
    //      the same block. This optimization reduces external calls and gas costs.
    // @param quote_token_addr: Address of quote token in given ticker
    // @param base_token_addr: Address of base token in given ticker
    // @return terminal_price: Terminal spot price
    fn get_terminal_price(
        quote_token_addr: ContractAddress, base_token_addr: ContractAddress, maturity: Timestamp
    ) -> Fixed {
        let price_pragma = get_pragma_terminal_price(quote_token_addr, base_token_addr, maturity);
        price_pragma
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use starknet::{ContractAddress, get_block_info};
    use cubit::f128::types::fixed::{Fixed, FixedTrait};
    use carmine_protocol::testing::setup::deploy_setup;
    use carmine_protocol::amm_core::oracles::agg::OracleAgg;
    use carmine_protocol::amm_core::state::State;
    use carmine_protocol::amm_core::oracles::pragma::Pragma::PRAGMA_ORACLE_ADDRESS;
    use carmine_protocol::amm_core::oracles::pragma::PragmaUtils::{PragmaPricesResponse};
    use carmine_protocol::amm_core::state::State::{
        write_latest_oracle_price, read_latest_oracle_price
    };
    use snforge_std::{
        start_prank, stop_prank, start_mock_call, stop_mock_call, start_warp, stop_warp
    };

    #[test]
    fn test_get_current_price() {
        let (ctx, dsps) = deploy_setup();
        // Setup: Create mock addresses
        let quote_token_addr = starknet::contract_address_const::<0x1>();
        let base_token_addr = starknet::contract_address_const::<0x2>();

        // Test case 1: When last_price_block_num == curr_block
        write_latest_oracle_price(
            base_token_addr, quote_token_addr, FixedTrait::from_unscaled_felt(1000), 2000
        );

        let result1 = OracleAgg::get_current_price(quote_token_addr, base_token_addr);
        assert(result1 == FixedTrait::from_unscaled_felt(1000), 'Wrong price when block matches');

        // Test case 2: When last_price_block_num != curr_block
        write_latest_oracle_price(
            base_token_addr, quote_token_addr, FixedTrait::from_unscaled_felt(1000), 1999
        );

        // Mock Pragma oracle call
        start_mock_call(
            PRAGMA_ORACLE_ADDRESS.try_into().unwrap(),
            'get_data',
            PragmaPricesResponse {
                price: 150000000000, // 1500 with 8 decimals
                decimals: 8,
                last_updated_timestamp: 1000000000,
                num_sources_aggregated: 3,
                expiration_timestamp: Option::None(())
            }
        );

        let result2 = OracleAgg::get_current_price(quote_token_addr, base_token_addr);
        assert(result2 == FixedTrait::from_unscaled_felt(1500), 'Wrong price from Pragma');

        // Test case 3: When last_price_block_num != curr_block, price in state is updated
        write_latest_oracle_price(
            base_token_addr, quote_token_addr, FixedTrait::from_unscaled_felt(1000), 1999
        );

        // Mock Pragma oracle call
        start_mock_call(
            PRAGMA_ORACLE_ADDRESS.try_into().unwrap(),
            'get_data',
            PragmaPricesResponse {
                price: 150000000000, // 1500 with 8 decimals
                decimals: 8,
                last_updated_timestamp: 1000000000,
                num_sources_aggregated: 3,
                expiration_timestamp: Option::None(())
            }
        );

        let current_price = OracleAgg::get_current_price(quote_token_addr, base_token_addr);
        let (new_price_in_state, last_block_in_state) = read_latest_oracle_price(
            base_token_addr, quote_token_addr
        );
        assert(
            new_price_in_state == FixedTrait::from_unscaled_felt(1500),
            'Price in state was not updated.'
        );
    }
}
