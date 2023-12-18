use starknet::ContractAddress;
use starknet::ClassHash;

#[starknet::interface]
trait ILPToken<TState> {
    // IERC20
    fn total_supply(self: @TState) -> u256;
    fn balance_of(self: @TState, account: ContractAddress) -> u256;
    fn allowance(self: @TState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: TState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn approve(ref self: TState, spender: ContractAddress, amount: u256) -> bool;

    // IERC20Metadata
    fn name(self: @TState) -> felt252;
    fn symbol(self: @TState) -> felt252;
    fn decimals(self: @TState) -> u8;

    // IERC20SafeAllowance
    fn increase_allowance(ref self: TState, spender: ContractAddress, added_value: u256) -> bool;
    fn decrease_allowance(
        ref self: TState, spender: ContractAddress, subtracted_value: u256
    ) -> bool;

    // IERC20CamelOnly
    fn totalSupply(self: @TState) -> u256;
    fn balanceOf(self: @TState, account: ContractAddress) -> u256;
    fn transferFrom(
        ref self: TState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;

    // IERC20CamelSafeAllowance
    fn increaseAllowance(ref self: TState, spender: ContractAddress, addedValue: u256) -> bool;
    fn decreaseAllowance(ref self: TState, spender: ContractAddress, subtractedValue: u256) -> bool;

    // Custom Functions
    fn mint(ref self: TState, recipient: ContractAddress, amount: u256);
    fn burn(ref self: TState, account: ContractAddress, amount: u256);
    fn upgrade(ref self: TState, new_class_hash: ClassHash);

    // Ownable Functions
    fn transferOwnership(ref self: TState, newOwner: ContractAddress);
    fn renounceOwnership(ref self: TState);
    fn owner(self: @TState) -> ContractAddress;
    fn transfer_ownership(ref self: TState, new_owner: ContractAddress);
    fn renounce_ownership(ref self: TState);
}


#[starknet::contract]
mod LPToken {
    use starknet::ContractAddress;
    use starknet::get_block_info;
    use starknet::ClassHash;
    use starknet::get_caller_address;
    use carmine_protocol::oz::token::erc20::ERC20Component;
    use carmine_protocol::oz::access::ownable::OwnableComponent;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl SafeAllowanceImpl = ERC20Component::SafeAllowanceImpl<ContractState>;
    #[abi(embed_v0)]
    impl SafeAllowanceCamelImpl =
        ERC20Component::SafeAllowanceCamelImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC20MetadataImpl = ERC20Component::ERC20MetadataImpl<ContractState>;

    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    // Ownable Component
    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;

    #[abi(embed_v0)]
    impl OwnableCamelOnlyImpl =
        OwnableComponent::OwnableCamelOnlyImpl<ContractState>;

    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;


    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        // Storage used for preventing too many actions 
        // within the same block
        sandwich_storage: LegacyMap<ContractAddress, u64>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Upgraded: Upgraded,
        // #[flat]
        ERC20Event: ERC20Component::Event,
        // #[flat]
        OwnableEvent: OwnableComponent::Event
    }

    #[derive(Drop, starknet::Event)]
    struct Upgraded {
        class_hash: ClassHash
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, name: felt252, symbol: felt252, owner: ContractAddress
    ) {
        self.erc20.initializer(name, symbol);
        self.ownable.initializer(owner);
    }

    // @notice Checks whether user has not minted or burned and then 
    // @notice      tried to mint/burn/transfer within the same block
    // @param holder: Hodlers address
    fn SandwichGuard(holder: ContractAddress, is_transfer: bool) {
        // Get current block number
        let curr_block = get_block_info().unbox().block_number;

        // Read block number of the last user interaction
        let mut state: ContractState = unsafe_new_contract_state();
        let user_last_interaction = state.sandwich_storage.read(holder);

        // Assert that the values above are not the same
        assert(curr_block != user_last_interaction, 'LPT: too many actions');

        // If the holder is minting or burning we want to save that information
        // so they can't mint/burn/transfer in the same block, 
        // but we don't want to do that if they are transfering, meaning
        // that transfers are unlimited within the same block
        // (unless mint/burn was initialized in it)
        if !is_transfer {
            // Write block number of the last user interaction
            state.sandwich_storage.write(holder, curr_block);
        }
    }


    #[external(v0)]
    #[generate_trait]
    impl LPTokenImpl of ILPToken {
        // Upgrades
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            assert(!new_class_hash.is_zero(), 'Class hash cannot be zero');
            starknet::replace_class_syscall(new_class_hash).unwrap();
            self.emit(Upgraded { class_hash: new_class_hash });
        }

        //////////////////////////////////////////
        // Functions that use sandwich guard 
        //////////////////////////////////////////

        fn mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            SandwichGuard(recipient, false);

            self.ownable.assert_only_owner();
            self.erc20._mint(recipient, amount);
        }

        fn burn(ref self: ContractState, account: ContractAddress, amount: u256) {
            SandwichGuard(account, false);

            self.ownable.assert_only_owner();
            self.erc20._burn(account, amount);
        }


        /// Moves `amount` tokens from the caller's token balance to `to`.
        /// Emits a `Transfer` event.
        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            let sender = get_caller_address();
            SandwichGuard(sender, true);

            self.erc20._transfer(sender, recipient, amount);
            true
        }

        /// Moves `amount` tokens from `from` to `to` using the allowance mechanism.
        /// `amount` is then deducted from the caller's allowance.
        /// Emits a `Transfer` event.
        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool {
            let caller = get_caller_address();
            SandwichGuard(sender, true);

            self.erc20._spend_allowance(sender, caller, amount);
            self
                .erc20
                ._transfer(
                    sender, recipient, amount
                ); // Use this contracts function that uses SandwichGuard
            true
        }


        //////////////////////////////////////////
        // Functions that are copied from ERC20Impl
        //////////////////////////////////////////

        /// Returns the value of tokens in existence.
        fn total_supply(self: @ContractState) -> u256 {
            self.erc20.ERC20_total_supply.read()
        }

        /// Returns the amount of tokens owned by `account`.
        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.erc20.ERC20_balances.read(account)
        }

        /// Returns the remaining number of tokens that `spender` is
        /// allowed to spend on behalf of `owner` through `transfer_from`.
        /// This is zero by default.
        /// This value changes when `approve` or `transfer_from`
        /// are called.
        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress
        ) -> u256 {
            self.erc20.ERC20_allowances.read((owner, spender))
        }

        /// Sets `amount` as the allowance of `spender` over the caller’s tokens.
        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            let caller = get_caller_address();
            self.erc20._approve(caller, spender, amount);
            true
        }

        //////////////////////////////////////////
        // Functions that are from ERC20CamelOnlyImpl
        //////////////////////////////////////////

        fn totalSupply(self: @ContractState) -> u256 {
            self.total_supply() // Calls this contracts function, not components
        }

        fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
            self.balance_of(account) // Calls this contracts function, not components
        }

        fn transferFrom(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool {
            self
                .transfer_from(
                    sender, recipient, amount
                ) // Calls this contracts function, not components
        }
    }
}
