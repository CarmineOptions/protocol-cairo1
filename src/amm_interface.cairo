use starknet::ContractAddress;
use carmine_protocol::types::basic::{OptionType, OptionSide};

use carmine_protocol::types::option_::{Option_, OptionWithPremia, OptionWithUsersPosition};
use carmine_protocol::types::pool::{PoolInfo, UserPoolInfo, Pool};
use cubit::f128::types::fixed::{Fixed, FixedTrait};
use carmine_protocol::amm_core::oracles::pragma::PragmaUtils::{PragmaPricesResponse, Checkpoint};
use starknet::ClassHash;

#[starknet::interface]
trait IAMM<TContractState> {
    fn trade_open(
        ref self: TContractState,
        option_type: OptionType,
        strike_price: Fixed,
        maturity: u64,
        option_side: OptionSide,
        option_size: u128,
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        limit_total_premia: Fixed,
        tx_deadline: u64,
    ) -> Fixed;
    fn trade_close(
        ref self: TContractState,
        option_type: OptionType,
        strike_price: Fixed,
        maturity: u64,
        option_side: OptionSide,
        option_size: u128,
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        limit_total_premia: Fixed,
        tx_deadline: u64,
    ) -> Fixed;
    fn trade_settle(
        ref self: TContractState,
        option_type: OptionType,
        strike_price: Fixed,
        maturity: u64,
        option_side: OptionSide,
        option_size: u128,
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
    );
    fn is_option_available(
        self: @TContractState,
        lptoken_address: ContractAddress,
        option_side: OptionSide,
        strike_price: Fixed,
        maturity: u64,
    ) -> bool;
    fn set_trading_halt(ref self: TContractState, new_status: bool);
    fn get_trading_halt(self: @TContractState) -> bool;
    fn set_trading_halt_permission(
        ref self: TContractState, address: ContractAddress, permission: bool
    );
    fn get_trading_halt_permission(self: @TContractState, address: ContractAddress) -> bool;
    fn add_lptoken(
        ref self: TContractState,
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        option_type: OptionType,
        lptoken_address: ContractAddress,
        pooled_token_addr: ContractAddress,
        volatility_adjustment_speed: Fixed,
        max_lpool_bal: u256,
    );
    fn add_option_both_sides(
        ref self: TContractState,
        maturity: u64,
        strike_price: Fixed,
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        option_type: OptionType,
        lptoken_address: ContractAddress,
        option_token_address_long: ContractAddress,
        option_token_address_short: ContractAddress,
        initial_volatility: Fixed
    );

    fn get_option_token_address(
        self: @TContractState,
        lptoken_address: ContractAddress,
        option_side: OptionSide,
        maturity: u64,
        strike_price: Fixed,
    ) -> ContractAddress;
    fn get_lptokens_for_underlying(
        self: @TContractState, pooled_token_addr: ContractAddress, underlying_amt: u256,
    ) -> u256;
    fn get_underlying_for_lptokens(
        self: @TContractState, lptoken_addr: ContractAddress, lpt_amt: u256
    ) -> u256;
    fn get_available_lptoken_addresses(self: @TContractState, order_i: felt252) -> ContractAddress;
    fn get_all_options(self: @TContractState, lptoken_address: ContractAddress) -> Array<Option_>;
    fn get_all_non_expired_options_with_premia(
        self: @TContractState, lptoken_address: ContractAddress
    ) -> Array<OptionWithPremia>;
    fn get_option_with_position_of_user(
        self: @TContractState, user_address: ContractAddress
    ) -> Array<OptionWithUsersPosition>;
    fn get_all_lptoken_addresses(self: @TContractState,) -> Array<ContractAddress>;
    fn get_value_of_pool_position(self: @TContractState, lptoken_address: ContractAddress) -> Fixed;

    fn get_value_of_pool_expired_position(
        self: @TContractState, lptoken_address: ContractAddress
    ) -> Fixed;
    fn get_value_of_pool_non_expired_position(
        self: @TContractState, lptoken_address: ContractAddress
    ) -> Fixed;


    fn get_value_of_position(
        self: @TContractState,
        option: Option_,
        position_size: u128,
        option_type: OptionType,
        current_volatility: Fixed,
    ) -> Fixed;
    fn get_all_poolinfo(self: @TContractState) -> Array<PoolInfo>;
    fn get_user_pool_infos(self: @TContractState, user: ContractAddress) -> Array<UserPoolInfo>;
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
        strike_price: Fixed,
        maturity: u64,
    );
    fn set_max_option_size_percent_of_voladjspd(
        ref self: TContractState, max_opt_size_as_perc_of_vol_adjspd: u128
    );
    fn get_max_option_size_percent_of_voladjspd(self: @TContractState) -> u128;
    fn get_lpool_balance(self: @TContractState, lptoken_address: ContractAddress) -> u256;
    fn get_max_lpool_balance(self: @TContractState, lpt_addr: ContractAddress) -> u256;
    fn set_max_lpool_balance(
        ref self: TContractState, lpt_addr: ContractAddress, max_lpool_bal: u256
    );
    fn get_pool_locked_capital(self: @TContractState, lptoken_address: ContractAddress) -> u256;
    fn get_available_options(
        self: @TContractState, lptoken_address: ContractAddress, order_i: u32
    ) -> Option_;

    fn get_lptoken_address_for_given_option(
        self: @TContractState,
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        option_type: OptionType,
    ) -> ContractAddress;
    fn get_pool_definition_from_lptoken_address(
        self: @TContractState, lptoken_addres: ContractAddress
    ) -> Pool;
    fn get_option_volatility(
        self: @TContractState, lptoken_address: ContractAddress, maturity: u64, strike_price: Fixed,
    ) -> Fixed;
    fn get_underlying_token_address(
        self: @TContractState, lptoken_address: ContractAddress
    ) -> ContractAddress;
    fn get_available_lptoken_addresses_usable_index(
        self: @TContractState, starting_index: felt252
    ) -> felt252;
    fn get_pool_volatility_adjustment_speed(
        self: @TContractState, lptoken_address: ContractAddress
    ) -> Fixed;
    fn set_pool_volatility_adjustment_speed(
        ref self: TContractState, lptoken_address: ContractAddress, new_speed: Fixed
    );
    fn get_option_position(
        self: @TContractState,
        lptoken_address: ContractAddress,
        option_side: OptionSide,
        maturity: u64,
        strike_price: Fixed
    ) -> u128;
    fn get_total_premia(
        self: @TContractState, option: Option_, position_size: u256, is_closing: bool
    ) -> (Fixed, Fixed);

    fn black_scholes(
        self: @TContractState,
        sigma: Fixed,
        time_till_maturity_annualized: Fixed,
        strike_price: Fixed,
        underlying_price: Fixed,
        risk_free_rate_annualized: Fixed,
        is_for_trade: bool, // bool
    ) -> (Fixed, Fixed, bool);
    fn get_current_price(
        self: @TContractState,
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress
    ) -> Fixed;
    fn get_terminal_price(
        self: @TContractState,
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        maturity: u64
    ) -> Fixed;

    fn set_pragma_checkpoint(ref self: TContractState, key: felt252);
    fn set_pragma_required_checkpoints(ref self: TContractState);
    fn upgrade(ref self: TContractState, new_implementation: ClassHash);
}
