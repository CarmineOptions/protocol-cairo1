mod OracleAgg {
    use starknet::ContractAddress;
    use cubit::f128::types::fixed::{Fixed};

    // use carmine_protocol::basic::{Timestamp};
    type Timestamp = u64; // In seconds, Block timestamps are also u64

    use carmine_protocol::oracles::pragma::Pragma::{
        get_pragma_median_price, get_pragma_terminal_price
    };

    fn get_current_price(
        quote_token_addr: ContractAddress, base_token_addr: ContractAddress
    ) -> Fixed {
        let price_pragma = get_pragma_median_price(quote_token_addr, base_token_addr);
        // Add other oracles here

        // Aggregate them here
        // let res = aggregate_oracles(price_pragma, ....);
        // return res;

        price_pragma
    }

    fn get_terminal_price(
        quote_token_addr: ContractAddress, base_token_addr: ContractAddress, maturity: Timestamp
    ) -> Fixed {
        let price_pragma = get_pragma_terminal_price(quote_token_addr, base_token_addr, maturity);

        // Add other oracles here

        // Aggregate them here
        // let res = aggregate_oracles(price_pragma, ....);
        // return res;

        price_pragma
    }
}
