mod OracleAgg {
    use starknet::ContractAddress;
    use cubit::f128::types::fixed::{Fixed};

    use carmine_protocol::types::basic::{Timestamp};

    use carmine_protocol::amm_core::oracles::pragma::Pragma::{
        get_pragma_median_price, get_pragma_terminal_price
    };

    use carmine_protocol::amm_core::state::State::read_latest_oracle_price;
    use carmine_protocol::amm_core::state::State::write_latest_oracle_price;

    use starknet::get_block_info;
    

    // @notice Returns current spot price for given ticker (quote and base token)
    // @param quote_token_addr: Address of quote token in given ticker
    // @param base_token_addr: Address of base token in given ticker
    // @return current_price: Current spot price
    fn get_current_price(
        quote_token_addr: ContractAddress, base_token_addr: ContractAddress
    ) -> Fixed {
        let curr_block = get_block_info().unbox().block_number;
        let (last_price, last_price_block_num) = read_latest_oracle_price(
            base_token_addr,
            quote_token_addr
        );

        if last_price_block_num == curr_block {
            last_price
        } else {
            let price_pragma = get_pragma_median_price(quote_token_addr, base_token_addr);

            write_latest_oracle_price(
                base_token_addr, 
                quote_token_addr, 
                price_pragma,
                curr_block
            );

            price_pragma
        }
    }


    // @notice Returns terminal spot price for given ticker (quote and base token)
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
