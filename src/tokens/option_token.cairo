// use starknet::ContractAddress;
// use starknet::ClassHash;
// use cubit::f128::types::Fixed;

// #[starknet::interface]
// trait IOptionToken<TState> {
//     // fn set_owner_admin(ref self: TState, owner: ContractAddress);
//     fn upgrade(ref self: TState, new_class_hash: ClassHash);

//     fn name(self: @TState) -> felt252;
//     fn symbol(self: @TState) -> felt252;
//     fn decimals(self: @TState) -> u8;
//     fn totalSupply(self: @TState) -> u256;
//     fn balanceOf(self: @TState, account: ContractAddress) -> u256;
//     fn balance_of(self: @TState, account: ContractAddress) -> u256;
//     fn allowance(self: @TState, owner: ContractAddress, spender: ContractAddress) -> u256;

//     fn owner(self: @TState) -> ContractAddress;
//     fn quote_token_address(self: @TState) -> ContractAddress;
//     fn base_token_address(self: @TState) -> ContractAddress;
//     fn option_type(self: @TState) -> u8;
//     fn strike_price(self: @TState) -> Fixed;
//     fn maturity(self: @TState) -> u64;
//     fn side(self: @TState) -> u8;

//     fn transfer(ref self: TState, recipient: ContractAddress, amount: u256) -> bool;
//     fn transferFrom(
//         ref self: TState, sender: ContractAddress, recipient: ContractAddress, amount: u256
//     ) -> bool;
//     fn approve(ref self: TState, spender: ContractAddress, amount: u256) -> bool;

//     fn mint(ref self: TState, recipient: ContractAddress, amount: u256);
//     fn burn(ref self: TState, account: ContractAddress, amount: u256);
// }


#[starknet::contract]
mod OptionToken {

    use starknet::ContractAddress;
    use starknet::ClassHash;
    use starknet::get_caller_address;

    use openzeppelin::token::erc20::ERC20Component;
    use openzeppelin::access::ownable::OwnableComponent;
    use cubit::f128::types::FixedTrait;
    use cubit::f128::types::Fixed;
    
    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    
    // ERC20 Component
    #[abi(embed_v0)]
    impl ERC20Impl = ERC20Component::ERC20Impl<ContractState>;

    #[abi(embed_v0)]
    impl SafeAllowanceImpl = ERC20Component::SafeAllowanceImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC20CamelOnlyImpl = ERC20Component::ERC20CamelOnlyImpl<ContractState>;

    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    // Ownable Component
    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;

    #[abi(embed_v0)]
    impl OwnableCamelOnlyImpl = OwnableComponent::OwnableCamelOnlyImpl<ContractState>;

    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    
    
    #[storage]
    struct Storage {

        #[substorage(v0)]
        erc20: ERC20Component::Storage,

        #[substorage(v0)]
        ownable:  OwnableComponent::Storage,
        
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
        Upgraded: Upgraded,

        #[flat]
        ERC20Event: ERC20Component::Event,

        #[flat]
        OwnableEvent: OwnableComponent::Event
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

        let strike = FixedTrait::from_felt(strike_price);

        self.erc20.initializer(name, symbol);
        self.ownable.initializer(owner);

        self._option_token_quote_token_address.write(quote_token_address);
        self._option_token_base_token_address.write(base_token_address);
        self._option_token_option_type.write(option_type);
        self._option_token_maturity.write(maturity);
        self._option_token_side.write(side);
        self._option_token_strike_price.write(strike);
    }

    //
    // External
    //

    // use carmine_protocol::utils::assert_admin_only;
    #[external(v0)]
    #[generate_trait]
    impl OptionTokenImpl of IOptionToken {

        // Did not import Erc20MetaData, so we can change decimals
        // so we need to define name, symbol and decimals ourselves
        fn name(self: @ContractState) -> felt252 {
            self.erc20.ERC20_name.read()
        }

        fn symbol(self: @ContractState) -> felt252 {
            self.erc20.ERC20_symbol.read()
        }

        fn decimals(self: @ContractState) -> u8 {
            18
        }

        // Minting/Burning
        fn mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            self.ownable.assert_only_owner();
            self.erc20._mint(recipient, amount);
        }

        fn burn(ref self: ContractState, account: ContractAddress, amount: u256) {
            // Should assert owner be here as well?
            self.erc20._burn(account, amount);
        }

        // Upgrades
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            assert(!new_class_hash.is_zero(), 'Class hash cannot be zero');
            starknet::replace_class_syscall(new_class_hash).unwrap();
            self.emit(Upgraded { class_hash: new_class_hash });
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
