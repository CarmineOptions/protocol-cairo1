use starknet::ContractAddress;
use starknet::ClassHash;
use cubit::f128::types::Fixed;

#[starknet::interface]
trait IOptionToken<TState> {

    fn set_owner_admin(ref self: TState, owner: ContractAddress);
    fn upgrade(ref self: TState, new_class_hash: ClassHash);
    
    fn name(self: @TState) -> felt252;
    fn symbol(self: @TState) -> felt252;
    fn decimals(self: @TState) -> u8;
    fn totalSupply(self: @TState) -> u256;
    fn balanceOf(self: @TState, account: ContractAddress) -> u256;
    fn allowance(self: @TState, owner: ContractAddress, spender: ContractAddress) -> u256;

    fn owner(self: @TState) -> ContractAddress;
    fn quote_token_address(self: @TState) -> ContractAddress;
    fn base_token_address(self: @TState) -> ContractAddress;
    fn option_type(self: @TState) -> u8;
    fn strike_price(self: @TState) -> Fixed;
    fn maturity(self: @TState) -> u64;
    fn side(self: @TState) -> u8;
    
    fn transfer(ref self: TState, recipient: ContractAddress, amount: u256) -> bool;
    fn transferFrom(
        ref self: TState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn approve(ref self: TState, spender: ContractAddress, amount: u256) -> bool;

    fn mint(ref self: TState, recipient: ContractAddress, amount: u256);
    fn burn(ref self: TState, account: ContractAddress, amount: u256);

}


#[starknet::contract]
mod OptionToken {
    use super::IOptionToken;
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use starknet::ClassHash;
    use cubit::f128::types::{Fixed, FixedTrait};

    use openzeppelin::token::erc20::ERC20;
    use openzeppelin::access::ownable::Ownable;
    #[storage]
    struct Storage {
        _option_token_quote_token_address: ContractAddress,
        _option_token_base_token_address: ContractAddress,
        _option_token_option_type: u8,
        _option_token_side: u8,
        _option_token_maturity: u64,
        _option_token_strike_price: Fixed,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Upgraded: Upgraded
    }

    #[derive(Drop, starknet::Event)]
    struct Upgraded {
        class_hash: ClassHash
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: felt252,
        symbol: felt252,
        owner: ContractAddress,
        quote_token_address: ContractAddress,
        base_token_address: ContractAddress,
        option_type: u8,
        strike_price: felt252,
        maturity: u64,
        side: u8,
    ) {

        let mut erc20_unsafe_state = ERC20::unsafe_new_contract_state();
        let mut ownable_unsafe_state = Ownable::unsafe_new_contract_state();
        ERC20::InternalImpl::initializer(ref erc20_unsafe_state, name, symbol);
        Ownable::InternalImpl::initializer(ref ownable_unsafe_state, owner);
        
        self._option_token_quote_token_address.write(quote_token_address);
        self._option_token_base_token_address.write(base_token_address);
        self._option_token_option_type.write(option_type);
        self._option_token_maturity.write(maturity);
        self._option_token_side.write(side);
        self._option_token_strike_price.write(FixedTrait::from_felt(strike_price));
    }

    //
    // External
    //

    use carmine_protocol::utils::assert_admin_only;
    #[external(v0)]
    impl OptionTokenImpl of IOptionToken<ContractState> {

        fn name(self: @ContractState) -> felt252 {
            let erc20_unsafe_state = ERC20::unsafe_new_contract_state();
            ERC20::ERC20Impl::name(@erc20_unsafe_state)
        }

        fn symbol(self: @ContractState) -> felt252 {
            let erc20_unsafe_state = ERC20::unsafe_new_contract_state();
            ERC20::ERC20Impl::symbol(@erc20_unsafe_state)
        }

        fn decimals(self: @ContractState) -> u8 {
            18
        }

        fn allowance(self: @ContractState, owner: ContractAddress, spender: ContractAddress) -> u256 {
            let erc20_unsafe_state = ERC20::unsafe_new_contract_state();
            ERC20::ERC20Impl::allowance(
                @erc20_unsafe_state, owner, spender
            )
        }

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool { 
            let mut erc20_unsafe_state = ERC20::unsafe_new_contract_state();
            ERC20::ERC20Impl::transfer(
                ref erc20_unsafe_state, recipient, amount
            )
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            let mut erc20_unsafe_state = ERC20::unsafe_new_contract_state();
            ERC20::ERC20Impl::transfer(
                ref erc20_unsafe_state, spender, amount
            )
        }
        
        fn mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            let mut erc20_unsafe_state = ERC20::unsafe_new_contract_state();
            let ownable_unsafe_state = Ownable::unsafe_new_contract_state();
            Ownable::InternalImpl::assert_only_owner(@ownable_unsafe_state);
            ERC20::InternalImpl::_mint(
                ref erc20_unsafe_state, recipient, amount
            )
        }

        fn burn(ref self: ContractState, account: ContractAddress, amount: u256) {
            let mut erc20_unsafe_state = ERC20::unsafe_new_contract_state();
            let ownable_unsafe_state = Ownable::unsafe_new_contract_state();
            Ownable::InternalImpl::assert_only_owner(@ownable_unsafe_state);
            ERC20::InternalImpl::_burn(
                ref erc20_unsafe_state, account, amount
            )
        }
        fn totalSupply(self: @ContractState) -> u256 {
            let erc20_unsafe_state = ERC20::unsafe_new_contract_state();
            ERC20::ERC20Impl::total_supply(@erc20_unsafe_state)
        }

        fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
            let erc20_unsafe_state = ERC20::unsafe_new_contract_state();
            ERC20::ERC20Impl::balance_of(@erc20_unsafe_state, account)
        }

        fn transferFrom(
            ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
        ) -> bool {
            let mut erc20_unsafe_state = ERC20::unsafe_new_contract_state();
            ERC20::ERC20Impl::transfer_from(ref erc20_unsafe_state, sender, recipient, amount)
        }

        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            assert_admin_only();
            
            assert(!new_class_hash.is_zero(), 'Class hash cannot be zero');
            starknet::replace_class_syscall(new_class_hash).unwrap();
            self.emit(Upgraded { class_hash: new_class_hash });
        }

        fn set_owner_admin(ref self: ContractState, owner: ContractAddress) {
            assert_admin_only();
            let mut ownable_unsafe_state = Ownable::unsafe_new_contract_state();
            Ownable::InternalImpl::_transfer_ownership(ref ownable_unsafe_state, owner);
        }

        fn owner(self: @ContractState) -> ContractAddress {
            let ownable_unsafe_state = Ownable::unsafe_new_contract_state();
            Ownable::OwnableImpl::owner(@ownable_unsafe_state)
        }

        fn quote_token_address(self: @ContractState) -> ContractAddress {
            self._option_token_quote_token_address.read()
        }

        fn base_token_address(self: @ContractState) -> ContractAddress {
            self._option_token_base_token_address.read()
        }

        fn option_type(self: @ContractState) -> u8 {
            self._option_token_option_type.read()
        }

        fn strike_price(self: @ContractState) -> Fixed {
            self._option_token_strike_price.read()
        }

        fn maturity(self: @ContractState) -> u64 {
            self._option_token_maturity.read()
        }

        fn side(self: @ContractState) -> u8 {
            self._option_token_side.read()
        }
    }
}
