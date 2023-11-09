// use starknet::ContractAddress;
// use cubit::f128::types::Fixed;
// use starknet::ClassHash;

// #[starknet::interface]
// trait ILPToken<TState> {
//     fn set_owner_admin(ref self: TState, owner: ContractAddress);
//     fn upgrade(ref self: TState, new_class_hash: ClassHash);
//     fn name(self: @TState) -> felt252;
//     fn symbol(self: @TState) -> felt252;
//     fn decimals(self: @TState) -> u8;
//     fn totalSupply(self: @TState) -> u256;
//     fn balanceOf(self: @TState, account: ContractAddress) -> u256;
//     fn allowance(self: @TState, owner: ContractAddress, spender: ContractAddress) -> u256;
//     fn transfer(ref self: TState, recipient: ContractAddress, amount: u256) -> bool;
//     fn transferFrom(
//         ref self: TState, sender: ContractAddress, recipient: ContractAddress, amount: u256
//     ) -> bool;
//     fn approve(ref self: TState, spender: ContractAddress, amount: u256) -> bool;
//     fn mint(ref self: TState, recipient: ContractAddress, amount: u256);
//     fn burn(ref self: TState, account: ContractAddress, amount: u256);
//     fn owner(self: @TState) -> ContractAddress;
// }


#[starknet::contract]
mod LPToken {
    use starknet::ContractAddress;
    use starknet::ClassHash;
    use starknet::get_caller_address;
    use openzeppelin::token::erc20::ERC20Component;
    use openzeppelin::access::ownable::OwnableComponent;
    
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
        owner: ContractAddress
    ) {
        self.erc20.initializer(name, symbol);
        self.ownable.initializer(owner);
    }

    #[external(v0)]
    #[generate_trait]
    impl LPTokenImpl of ILPToken {

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

    }

}
