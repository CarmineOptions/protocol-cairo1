use starknet::ContractAddress;

#[starknet::interface]
trait IMyToken<TState> {
    fn name(self: @TState) -> felt252;
    fn symbol(self: @TState) -> felt252;
    fn decimals(self: @TState) -> u8;
    fn total_supply(self: @TState) -> u256;
    fn balance_of(self: @TState, account: ContractAddress) -> u256;
    fn allowance(self: @TState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: TState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn approve(ref self: TState, spender: ContractAddress, amount: u256) -> bool;
// fn mint(ref self: TState, recipient: ContractAddress, amount: u256);
// fn burn(ref self: TState, account: ContractAddress, amount: u256);
}


#[starknet::contract]
mod MyToken {
    use starknet::ContractAddress;
    use starknet::ClassHash;
    use starknet::get_caller_address;
    use carmine_protocol::oz::token::erc20::ERC20Component;
    use carmine_protocol::oz::access::ownable::OwnableComponent;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    // ERC20 Component
    #[abi(embed_v0)]
    impl ERC20Impl = ERC20Component::ERC20Impl<ContractState>;

    #[abi(embed_v0)]
    impl SafeAllowanceImpl = ERC20Component::SafeAllowanceImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC20CamelOnlyImpl = ERC20Component::ERC20CamelOnlyImpl<ContractState>;

    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;


    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        decimals: u8,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Upgraded: Upgraded,
        // #[flat]
        ERC20Event: ERC20Component::Event,
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
        decimals: u8,
        initial_supply: u256,
        recipient: ContractAddress
    ) {
        self.erc20.initializer(name, symbol);
        self.erc20._mint(recipient, initial_supply);
        self.decimals.write(decimals)
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
            self.decimals.read()
        }

        // Minting/Burning
        fn mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            self.erc20._mint(recipient, amount);
        }

        fn burn(ref self: ContractState, account: ContractAddress, amount: u256) {
            // Should assert owner be here as well?
            self.erc20._burn(account, amount);
        }

        // Upgrades
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            assert(!new_class_hash.is_zero(), 'Class hash cannot be zero');
            starknet::replace_class_syscall(new_class_hash).unwrap();
            self.emit(Upgraded { class_hash: new_class_hash });
        }
    }
}

