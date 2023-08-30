use starknet::ContractAddress;
use array::ArrayTrait;

use carmine_protocol::types::basic::{OptionType, Math64x61_, OptionSide};

use carmine_protocol::amm_core::oracles::pragma::Pragma::PragmaCheckpoint;

#[starknet::interface]
trait IERC20<TContractState> {
    fn name(self: @TContractState) -> felt252;
    fn symbol(self: @TContractState) -> felt252;
    fn decimals(self: @TContractState) -> u8;
    fn totalSupply(self: @TContractState) -> u256;
    fn total_supply(self: @TContractState) -> u256;
    fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
    fn burn(ref self: TContractState, account: ContractAddress, amount: u256);
    fn balanceOf(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transferFrom(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
}


#[starknet::interface]
trait IGovernanceToken<TContractState> {
    fn name(self: @TContractState) -> felt252;
    fn symbol(self: @TContractState) -> felt252;
    fn decimals(self: @TContractState) -> felt252;
    fn totalSupply(self: @TContractState) -> u256;
    fn balanceOf(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> felt252;
    fn transferFrom(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> felt252;
    fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> felt252;
    fn upgrade(ref self: TContractState, new_implementation: felt252);
    fn initializer(
        ref self: TContractState,
        name: felt252,
        symbol: felt252,
        decimals: felt252,
        initial_supply: u256,
        recipient: ContractAddress,
        proxy_admin: ContractAddress
    );
}

#[starknet::interface]
trait IOptionToken<TContractState> {
    fn initializer(
        ref self: TContractState,
        name: felt252,
        symbol: felt252,
        proxy_admin: ContractAddress,
        owner: ContractAddress,
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        option_type: OptionType,
        strike_price: Math64x61_,
        maturity: felt252,
        side: OptionSide
    );
    fn _set_owner_admin(ref self: TContractState, owner: ContractAddress);
    fn upgrade(ref self: TContractState, new_implementation: felt252);
    fn name(self: @TContractState) -> felt252;
    fn symbol(self: @TContractState) -> felt252;
    fn decimals(self: @TContractState) -> felt252;
    fn totalSupply(self: @TContractState) -> u256;
    fn balanceOf(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn owner(self: @TContractState) -> ContractAddress;
    fn quote_token_address(self: @TContractState) -> ContractAddress;
    fn base_token_address(self: @TContractState) -> ContractAddress;
    fn option_type(self: @TContractState) -> OptionType;
    fn strike_price(self: @TContractState) -> Math64x61_;
    fn maturity(self: @TContractState) -> felt252;
    fn side(self: @TContractState) -> OptionSide;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> felt252;
    fn transferFrom(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> felt252;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> felt252;
    fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
    fn burn(ref self: TContractState, account: ContractAddress, amount: u256);
    fn transferOwnership(ref self: TContractState, newOwner: ContractAddress);
    fn renounceOwnership(ref self: TContractState);
}

#[starknet::interface]
trait IPragmaOracle<TContractState> {
    fn get_spot_median(
        self: @TContractState, pair_id: felt252
    ) -> (felt252, felt252, felt252, felt252);
    fn get_last_spot_checkpoint_before(
        self: @TContractState, key: felt252, timestamp: felt252
    ) -> (PragmaCheckpoint, felt252);
}
