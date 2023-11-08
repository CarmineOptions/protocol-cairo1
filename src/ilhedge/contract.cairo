use core::array::SpanTrait;
use starknet::ContractAddress;
use starknet::ClassHash;

#[starknet::interface]
trait IILHedge<TContractState> {
    fn hedge(
        ref self: TContractState,
        notional: u128,
        quote_token_addr: ContractAddress,
        base_token_addr: ContractAddress,
        expiry: u64
    );
    fn price_hedge(
        self: @TContractState,
        notional: u128,
        quote_token_addr: ContractAddress,
        base_token_addr: ContractAddress,
        expiry: u64
    ) -> (u128, u128);
    fn upgrade(ref self: TContractState, impl_hash: ClassHash);
    fn get_pragma_price(self: @TContractState) -> u128 ;
}

#[starknet::contract]
mod ILHedge {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::{Into, TryInto};

    use debug::PrintTrait;

    use starknet::ContractAddress;
    use starknet::ClassHash;
    use starknet::{get_caller_address, get_contract_address};
    use starknet::syscalls::{replace_class_syscall};

    use cubit::f128::types::fixed::{Fixed, FixedTrait};

    use carmine_protocol::ilhedge::amm_curve::compute_portfolio_value;
    use carmine_protocol::ilhedge::constants::{TOKEN_ETH_ADDRESS};
    use carmine_protocol::ilhedge::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use carmine_protocol::ilhedge::hedging::{
        iterate_strike_prices, buy_options_at_strike_to_hedge_at,
        price_options_at_strike_to_hedge_at
    };
    use carmine_protocol::amm_core::oracles::pragma::Pragma::get_pragma_median_price;
    use carmine_protocol::ilhedge::helpers::{convert_from_Fixed_to_int, convert_from_int_to_Fixed};

    #[storage]
    struct Storage {
        amm_address: ContractAddress
    }

    #[constructor]
    fn constructor(ref self: ContractState, amm_address: ContractAddress) {
        self.amm_address.write(amm_address);
    }

    use cubit::f128;
    #[external(v0)]
    impl ILHedge of super::IILHedge<ContractState> {
        fn get_pragma_price(self: @ContractState) -> u128 {
            let base_token_addr: ContractAddress = 0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7.try_into().unwrap();
            let quote_token_addr: ContractAddress = 0x005a643907b9a4bc6a55e9069c4fd5fd1f5c79a22470690f75556c4736e34426.try_into().unwrap();
            get_pragma_median_price(quote_token_addr, base_token_addr).mag
        }

        fn hedge(
            ref self: ContractState,
            notional: u128,
            quote_token_addr: ContractAddress,
            base_token_addr: ContractAddress,
            expiry: u64
        ) {
            let pricing: (u128, u128) = ILHedge::price_hedge(
                @self, notional, quote_token_addr, base_token_addr, expiry
            );
            let (cost_quote, cost_base) = pricing;
            let eth = IERC20Dispatcher { contract_address: TOKEN_ETH_ADDRESS.try_into().unwrap() };
            eth.transferFrom(get_caller_address(), get_contract_address(), cost_base.into());
            eth.approve(self.amm_address.read(), cost_base.into()); // approve AMM to spend
            let curr_price = get_pragma_median_price(quote_token_addr, base_token_addr);
            // iterate available strike prices and get them into pairs of (bought strike, at which strike one should be hedged)
            let mut strikes_calls = iterate_strike_prices(
                curr_price, quote_token_addr, base_token_addr, expiry, true
            );
            //let mut strikes_puts = iterate_strike_prices(
            //    quote_token_addr, base_token_addr, expiry, false
            //);

            let mut already_hedged: Fixed = FixedTrait::ZERO();

            loop {
                match strikes_calls.pop_front() {
                    Option::Some(strike_pair) => {
                        let (tobuy, tohedge) = *strike_pair;
                        // compute how much portf value would be at each hedged strike
                        // converts the excess to the hedge result asset (calls -> convert to eth)
                        // for each strike
                        let portf_val_calls = compute_portfolio_value(
                            curr_price, notional, true, tohedge
                        ); // value of second asset is precisely as much as user put in, expecting conversion
                        assert(portf_val_calls > FixedTrait::ZERO(), 'portf val calls < 0?');
                        let notional_fixed = convert_from_int_to_Fixed(notional, 18);
                        let amount_to_hedge = notional_fixed
                            - portf_val_calls; // difference between converted and leftover amounts is how much one should be hedging against
                        // buy this much of previous strike price (fst in iterate_strike_prices())
                        buy_options_at_strike_to_hedge_at(
                            tobuy,
                            tohedge,
                            amount_to_hedge,
                            expiry,
                            quote_token_addr,
                            base_token_addr,
                            self.amm_address.read(),
                            true
                        );
                    },
                    Option::None(()) => {
                        break;
                    }
                };
            };
        }

        fn upgrade(ref self: ContractState, impl_hash: ClassHash) {
            let caller: ContractAddress = get_caller_address();
            let owner: ContractAddress =
                0x001dd8e12b10592676E109C85d6050bdc1E17adf1be0573a089E081C3c260eD9
                .try_into()
                .unwrap();
            assert(owner == caller, 'invalid caller');
            replace_class_syscall(impl_hash);
        }

        fn price_hedge(
            self: @ContractState,
            notional: u128,
            quote_token_addr: ContractAddress,
            base_token_addr: ContractAddress,
            expiry: u64
        ) -> (u128, u128) {
            let curr_price = get_pragma_median_price(quote_token_addr, base_token_addr);

            // iterate available strike prices and get them into pairs of (bought strike, at which strike one should be hedged)
            let mut strikes_calls = iterate_strike_prices(
                curr_price, quote_token_addr, base_token_addr, expiry, true
            );
            let mut strikes_puts = iterate_strike_prices(
                curr_price, quote_token_addr, base_token_addr, expiry, false
            );

            let mut already_hedged: Fixed = FixedTrait::ZERO();
            let mut cost_quote = 0;
            let mut cost_base = 0;

            loop {
                match strikes_calls.pop_front() {
                    Option::Some(strike_pair) => {
                        let (tobuy, tohedge) = *strike_pair;
                        // compute how much portf value would be at each hedged strike
                        // converts the excess to the hedge result asset (calls -> convert to eth)
                        // for each strike
                        let portf_val_calls = compute_portfolio_value(
                            curr_price, notional, true, tohedge
                        ); // value of second asset is precisely as much as user put in, expecting conversion
                        assert(portf_val_calls > FixedTrait::ZERO(), 'portf val calls < 0?');
                        assert(portf_val_calls.sign == false, 'portf val neg??');
                        let notional_fixed = convert_from_int_to_Fixed(
                            notional, 18
                        ); // difference between converted and premia amounts is how much one should be hedging against
                        //assert((notional_fixed - portf_val_calls) > already_hedged, "amounttohedge neg??"); // can't compile with it for some reason??
                        let amount_to_hedge = (notional_fixed - portf_val_calls) - already_hedged;
                        'hedging, at tobuy:'.print();
                        tobuy.mag.print();
                        'at hedge:'.print();
                        tohedge.mag.print();
                        'amount to hedge:'.print();
                        convert_from_Fixed_to_int(amount_to_hedge, 18).print();
                        already_hedged += amount_to_hedge;
                        cost_base +=
                            price_options_at_strike_to_hedge_at(
                                tobuy, tohedge, amount_to_hedge, expiry, self.amm_address.read(), quote_token_addr, base_token_addr, true
                            );
                    },
                    Option::None(()) => {
                        break;
                    }
                };
            };
            loop {
                match strikes_puts.pop_front() {
                    Option::Some(strike_pair) => {
                        let (tobuy, tohedge) = *strike_pair;
                        tobuy.print();
                        // compute how much portf value would be at each hedged strike
                        // converts the excess to the hedge result asset (calls -> convert to eth)
                        // for each strike
                        let portf_val_puts = compute_portfolio_value(
                            curr_price, notional, false, tohedge
                        ); // value of second asset is precisely as much as user put in, expecting conversion
                        'computed portf val puts'.print();
                        assert(portf_val_puts > FixedTrait::ZERO(), 'portf val puts < 0?');
                        assert(
                            portf_val_puts < (convert_from_int_to_Fixed(notional, 18) * curr_price),
                            'some loss expected'
                        ); // portf_val_puts is in USDC
                        assert(portf_val_puts.sign == false, 'portf val neg??');
                        let notional_fixed_eth = convert_from_int_to_Fixed( // THIS IS BULLSHIT!!!
                            notional, 18
                        ); // difference between converted and premia amounts is how much one should be hedging against
                        let notional_fixed = notional_fixed_eth * curr_price;
                        let amount_to_hedge = notional_fixed
                            - portf_val_puts; // in USDC, with decimals
                        'pricing!'.print();
                        cost_quote +=
                            price_options_at_strike_to_hedge_at(
                                tobuy, tohedge, amount_to_hedge, expiry, self.amm_address.read(), quote_token_addr, base_token_addr, false
                            );
                    },
                    Option::None(()) => {
                        break;
                    }
                };
            };
            (cost_quote, cost_base)
        }
    }
}
