use starknet::ContractAddress;
use cubit::f128::types::Fixed;
use starknet::ClassHash;

#[starknet::interface]
trait ILPToken<TState> {
    fn set_owner_admin(ref self: TState, owner: ContractAddress);
    fn upgrade(ref self: TState, new_class_hash: ClassHash);

    fn name(self: @TState) -> felt252;
    fn symbol(self: @TState) -> felt252;
    fn decimals(self: @TState) -> u8;
    fn totalSupply(self: @TState) -> u256;
    fn balanceOf(self: @TState, account: ContractAddress) -> u256;
    fn allowance(self: @TState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: TState, recipient: ContractAddress, amount: u256) -> bool;
    fn transferFrom(
        ref self: TState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn approve(ref self: TState, spender: ContractAddress, amount: u256) -> bool;
    fn mint(ref self: TState, recipient: ContractAddress, amount: u256);
    fn burn(ref self: TState, account: ContractAddress, amount: u256);

    fn owner(self: @TState) -> ContractAddress;
}


#[starknet::contract]
mod LPToken {
    use starknet::ContractAddress;
    use starknet::ClassHash;
    use starknet::get_caller_address;
    use openzeppelin::token::erc20::ERC20;
    use openzeppelin::access::ownable::Ownable;
    use cubit::f128::types::Fixed;
    use carmine_protocol::utils::assert_admin_only;

    #[storage]
    struct Storage {}

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
        ref self: ContractState, name: felt252, symbol: felt252, // proxy_admin: ContractAddress,
        owner: ContractAddress
    ) {
        let mut erc20_unsafe_state = ERC20::unsafe_new_contract_state();
        let mut ownable_unsafe_state = Ownable::unsafe_new_contract_state();
        ERC20::InternalImpl::initializer(ref erc20_unsafe_state, name, symbol);
        Ownable::InternalImpl::initializer(ref ownable_unsafe_state, owner);
    // Todo: add proxy, ownable, add upgrades
    }

    #[external(v0)]
    impl LPTokenImpl of super::ILPToken<ContractState> {
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


        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress
        ) -> u256 {
            let erc20_unsafe_state = ERC20::unsafe_new_contract_state();
            ERC20::ERC20Impl::allowance(@erc20_unsafe_state, owner, spender)
        }

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            let mut erc20_unsafe_state = ERC20::unsafe_new_contract_state();
            ERC20::ERC20Impl::transfer(ref erc20_unsafe_state, recipient, amount)
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            let mut erc20_unsafe_state = ERC20::unsafe_new_contract_state();
            ERC20::ERC20Impl::transfer(ref erc20_unsafe_state, spender, amount)
        }

        fn mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            let mut erc20_unsafe_state = ERC20::unsafe_new_contract_state();
            let ownable_unsafe_state = Ownable::unsafe_new_contract_state();
            Ownable::InternalImpl::assert_only_owner(@ownable_unsafe_state);
            ERC20::InternalImpl::_mint(ref erc20_unsafe_state, recipient, amount)
        }

        fn burn(ref self: ContractState, account: ContractAddress, amount: u256) {
            let mut erc20_unsafe_state = ERC20::unsafe_new_contract_state();
            let ownable_unsafe_state = Ownable::unsafe_new_contract_state();
            Ownable::InternalImpl::assert_only_owner(@ownable_unsafe_state);
            ERC20::InternalImpl::_burn(ref erc20_unsafe_state, account, amount)
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
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
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
    }
}
