// Module responsible for interactions with the AMM

use option::OptionTrait;
use traits::TryInto;
use array::ArrayTrait;
use traits::Into;

use starknet::{ContractAddress, get_block_timestamp};

use carmine_protocol::ilhedge::constants::{TOKEN_ETH_ADDRESS, TOKEN_USDC_ADDRESS};
use carmine_protocol::ilhedge::helpers::FixedHelpersTrait;

use cubit::f128::types::fixed::{Fixed, FixedTrait};


fn buy_option(strike: Fixed, notional: u128, expiry: u64, calls: bool, amm_address: ContractAddress) {
    let optiontype = if (calls) {
        0
    } else {
        1
    };
    IAMMDispatcher { contract_address: amm_address }
        .trade_open(
            optiontype,
            FixedHelpersTrait::to_legacyMath(strike),
            expiry.into(),
            0,
            notional.into(),
            TOKEN_USDC_ADDRESS.try_into().unwrap(), // testnet
            TOKEN_ETH_ADDRESS.try_into().unwrap(),
            (notional / 5).into(),
            (get_block_timestamp() + 42).into()
        );
}

use debug::PrintTrait;

fn price_option(strike: Fixed, notional: u128, expiry: u64, calls: bool, amm_address: ContractAddress) -> u128 {
    let optiontype = if (calls) {
        0
    } else {
        1
    };
    let lpt_addr_felt: felt252 = if (calls) { // testnet
        0x03b176f8e5b4c9227b660e49e97f2d9d1756f96e5878420ad4accd301dd0cc17
    } else {
        0x30fe5d12635ed696483a824eca301392b3f529e06133b42784750503a24972
    };
    'pricing option, maturity:'.print();
    expiry.print();
    'notional:'.print();
    notional.print();
    'strike:'.print();
    FixedHelpersTrait::to_legacyMath(strike).print();
    let option = LegacyOption {
        option_side: 0,
        maturity: expiry.into(),
        strike_price: FixedHelpersTrait::to_legacyMath(strike),
        quote_token_address: TOKEN_USDC_ADDRESS.try_into().unwrap(),
        base_token_address: TOKEN_ETH_ADDRESS.try_into().unwrap(), // testnet
        option_type: optiontype
    };
    let (before_fees, after_fees) = IAMMDispatcher {
        contract_address: amm_address
    }
        .get_total_premia(option, lpt_addr_felt.try_into().unwrap(), notional.into(), 0);
    'call to get_total_premia fin'.print();
    after_fees.try_into().unwrap()
}

fn available_strikes(
    expiry: u64, quote_token_addr: ContractAddress, base_token_addr: ContractAddress, calls: bool
) -> Array<Fixed> {
    // TODO implement
    if (calls) {
        let mut res = ArrayTrait::<Fixed>::new();
        res.append(FixedTrait::from_unscaled_felt(1700));
        res.append(FixedTrait::from_unscaled_felt(1800));
        res.append(FixedTrait::from_unscaled_felt(1900));
        res.append(FixedTrait::from_unscaled_felt(2000));
        res
    } else {
        let mut res = ArrayTrait::<Fixed>::new();
        res.append(FixedTrait::from_unscaled_felt(1300));
        res.append(FixedTrait::from_unscaled_felt(1400));
        res.append(FixedTrait::from_unscaled_felt(1500));
        res.append(FixedTrait::from_unscaled_felt(1600));
        res
    }
}

#[derive(Copy, Drop, Serde, starknet::Store)]
struct LegacyOption {
    option_side: OptionSide,
    maturity: felt252,
    strike_price: LegacyStrike,
    quote_token_address: ContractAddress,
    base_token_address: ContractAddress,
    option_type: OptionType
}

type LegacyStrike = Math64x61_;
type Math64x61_ = felt252; // legacy, for AMM trait definition
type OptionSide = felt252;
type OptionType = felt252;

#[starknet::interface]
trait IAMM<TContractState> {
    fn trade_open(
        ref self: TContractState,
        option_type: OptionType,
        strike_price: Math64x61_,
        maturity: felt252,
        option_side: OptionSide,
        option_size: felt252,
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        limit_total_premia: Math64x61_,
        tx_deadline: felt252,
    ) -> Math64x61_;
    fn trade_close(
        ref self: TContractState,
        option_type: OptionType,
        strike_price: Math64x61_,
        maturity: felt252,
        option_side: OptionSide,
        option_size: felt252,
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        limit_total_premia: Math64x61_,
        tx_deadline: felt252,
    ) -> Math64x61_;
    fn trade_settle(
        ref self: TContractState,
        option_type: OptionType,
        strike_price: Math64x61_,
        maturity: felt252,
        option_side: OptionSide,
        option_size: felt252,
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
    );
    fn is_option_available(
        self: @TContractState,
        lptoken_address: ContractAddress,
        option_side: OptionSide,
        strike_price: Math64x61_,
        maturity: felt252,
    ) -> felt252;
    fn set_trading_halt(ref self: TContractState, new_status: felt252);
    fn get_trading_halt(self: @TContractState) -> felt252;
    fn add_lptoken(
        ref self: TContractState,
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        option_type: OptionType,
        lptoken_address: ContractAddress,
        pooled_token_addr: ContractAddress,
        volatility_adjustment_speed: Math64x61_,
        max_lpool_bal: u256,
    );
    fn add_option(
        ref self: TContractState,
        option_side: OptionSide,
        maturity: felt252,
        strike_price: Math64x61_,
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        option_type: OptionType,
        lptoken_address: ContractAddress,
        option_token_address_: ContractAddress,
        initial_volatility: Math64x61_,
    );
    fn get_option_token_address(
        self: @TContractState,
        lptoken_address: ContractAddress,
        option_side: OptionSide,
        maturity: felt252,
        strike_price: Math64x61_,
    ) -> ContractAddress;
    fn get_lptokens_for_underlying(
        ref self: TContractState, pooled_token_addr: ContractAddress, underlying_amt: u256,
    ) -> u256;
    fn get_underlying_for_lptokens(
        self: @TContractState, pooled_token_addr: ContractAddress, lpt_amt: u256
    ) -> u256;
    fn get_available_lptoken_addresses(self: @TContractState, order_i: felt252) -> ContractAddress;
    fn get_all_options(self: @TContractState, lptoken_address: ContractAddress) -> Array<felt252>;
    fn get_all_non_expired_options_with_premia(
        self: @TContractState, lptoken_address: ContractAddress
    ) -> Array<felt252>;
    fn get_option_with_position_of_user(
        self: @TContractState, user_address: ContractAddress
    ) -> Array<felt252>;
    fn get_all_lptoken_addresses(self: @TContractState,) -> Array<ContractAddress>;
    fn get_value_of_pool_position(
        self: @TContractState, lptoken_address: ContractAddress
    ) -> Math64x61_;
    // fn get_value_of_position(
    //     option: Option,
    //     position_size: Math64x61_,
    //     option_type: OptionType,
    //     current_volatility: Math64x61_,
    // ) -> Math64x61_;
    // fn get_all_poolinfo() -> Array<PoolInfo>;
    // fn get_option_info_from_addresses(
    //     lptoken_address: ContractAddress, option_token_address: ContractAddress, 
    // ) -> Option;
    // fn get_user_pool_infos(user: ContractAddress) -> Array<UserPoolInfo>;
    fn deposit_liquidity(
        ref self: TContractState,
        pooled_token_addr: ContractAddress,
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        option_type: OptionType,
        amount: u256,
    );
    fn withdraw_liquidity(
        ref self: TContractState,
        pooled_token_addr: ContractAddress,
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        option_type: OptionType,
        lp_token_amount: u256,
    );
    fn get_unlocked_capital(self: @TContractState, lptoken_address: ContractAddress) -> u256;
    fn expire_option_token_for_pool(
        ref self: TContractState,
        lptoken_address: ContractAddress,
        option_side: OptionSide,
        strike_price: Math64x61_,
        maturity: felt252,
    );
    fn getAdmin(self: @TContractState);
    fn set_max_option_size_percent_of_voladjspd(
        ref self: TContractState, max_opt_size_as_perc_of_vol_adjspd: felt252
    );
    fn get_max_option_size_percent_of_voladjspd(self: @TContractState) -> felt252;
    fn get_lpool_balance(self: @TContractState, lptoken_address: ContractAddress) -> u256;
    fn get_max_lpool_balance(self: @TContractState, pooled_token_addr: ContractAddress) -> u256;
    fn set_max_lpool_balance(
        ref self: TContractState, pooled_token_addr: ContractAddress, max_lpool_bal: u256
    );
    fn get_pool_locked_capital(self: @TContractState, lptoken_address: ContractAddress) -> u256;
    // fn get_available_options(lptoken_address: ContractAddress, order_i: felt252) -> Option;
    fn get_available_options_usable_index(
        self: @TContractState, lptoken_address: ContractAddress, starting_index: felt252
    ) -> felt252;
    fn get_lptoken_address_for_given_option(
        self: @TContractState,
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        option_type: OptionType,
    ) -> ContractAddress;
    //fn get_pool_definition_from_lptoken_address(lptoken_addres: ContractAddress) -> Pool;
    fn get_option_type(self: @TContractState, lptoken_address: ContractAddress) -> OptionType;
    fn get_pool_volatility_separate(
        self: @TContractState,
        lptoken_address: ContractAddress,
        maturity: felt252,
        strike_price: Math64x61_,
    ) -> Math64x61_;
    fn get_underlying_token_address(
        self: @TContractState, lptoken_address: ContractAddress
    ) -> ContractAddress;
    fn get_available_lptoken_addresses_usable_index(
        self: @TContractState, starting_index: felt252
    ) -> felt252;
    fn get_pool_volatility_adjustment_speed(
        self: @TContractState, lptoken_address: ContractAddress
    ) -> Math64x61_;
    fn set_pool_volatility_adjustment_speed_external(
        ref self: TContractState, lptoken_address: ContractAddress, new_speed: Math64x61_,
    );
    fn get_pool_volatility(
        self: @TContractState, lptoken_address: ContractAddress, maturity: felt252
    ) -> Math64x61_;
    fn get_pool_volatility_auto(
        self: @TContractState,
        lptoken_address: ContractAddress,
        maturity: felt252,
        strike_price: Math64x61_,
    ) -> Math64x61_;
    fn get_option_position(
        self: @TContractState,
        lptoken_address: ContractAddress,
        option_side: OptionSide,
        maturity: felt252,
        strike_price: Math64x61_
    ) -> felt252;
    fn get_total_premia(
        self: @TContractState,
        option: LegacyOption,
        lptoken_address: ContractAddress,
        position_size: u256,
        is_closing: felt252,
    ) -> (Math64x61_, Math64x61_); // before_fees, including_fees
    fn black_scholes(
        self: @TContractState,
        sigma: felt252,
        time_till_maturity_annualized: felt252,
        strike_price: felt252,
        underlying_price: felt252,
        risk_free_rate_annualized: felt252,
        is_for_trade: felt252, // bool
    ) -> (felt252, felt252);
    fn empiric_median_price(self: @TContractState, key: felt252) -> Math64x61_;
    fn initializer(ref self: TContractState, proxy_admin: ContractAddress);
    fn upgrade(ref self: TContractState, new_implementation: felt252);
    fn setAdmin(ref self: TContractState, address: felt252);
    fn getImplementationHash(self: @TContractState,) -> felt252;
}
