
#[starknet::contract]
mod LPToken {
    use starknet::ContractAddress;
    use starknet::ClassHash;
    use starknet::get_caller_address;
    use openzeppelin::token::erc20::ERC20Component;
    use openzeppelin::access::ownable::OwnableComponent;
    
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

        #[flat]
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


// use starknet::ContractAddress;

// #[starknet::interface]
// trait IMyToken<TState> {
//     fn name(self: @TState) -> felt252;
//     fn symbol(self: @TState) -> felt252;
//     fn decimals(self: @TState) -> u8;
//     fn total_supply(self: @TState) -> u256;
//     fn balance_of(self: @TState, account: ContractAddress) -> u256;
//     fn allowance(self: @TState, owner: ContractAddress, spender: ContractAddress) -> u256;
//     fn transfer(ref self: TState, recipient: ContractAddress, amount: u256) -> bool;
//     fn transfer_from(
//         ref self: TState, sender: ContractAddress, recipient: ContractAddress, amount: u256
//     ) -> bool;
//     fn approve(ref self: TState, spender: ContractAddress, amount: u256) -> bool;
// // fn mint(ref self: TState, recipient: ContractAddress, amount: u256);
// // fn burn(ref self: TState, account: ContractAddress, amount: u256);
// }



// #[starknet::contract]
// mod MyToken {
//     use integer::BoundedInt;
//     use super::IMyToken;
//     use openzeppelin::token::erc20::interface::IERC20;
//     use openzeppelin::token::erc20::interface::IERC20CamelOnly;
//     use starknet::ContractAddress;
//     use starknet::get_caller_address;
//     use zeroable::Zeroable;

//     #[storage]
//     struct Storage {
//         _name: felt252,
//         _symbol: felt252,
//         _decimals: u8,
//         _total_supply: u256,
//         _balances: LegacyMap<ContractAddress, u256>,
//         _allowances: LegacyMap<(ContractAddress, ContractAddress), u256>,
//     }

//     #[event]
//     #[derive(Drop, starknet::Event)]
//     enum Event {
//         Transfer: Transfer,
//         Approval: Approval,
//     }

//     #[derive(Drop, starknet::Event)]
//     struct Transfer {
//         from: ContractAddress,
//         to: ContractAddress,
//         value: u256
//     }

//     #[derive(Drop, starknet::Event)]
//     struct Approval {
//         owner: ContractAddress,
//         spender: ContractAddress,
//         value: u256
//     }

//     #[constructor]
//     fn constructor(
//         ref self: ContractState,
//         name: felt252,
//         symbol: felt252,
//         decimals: u8,
//         initial_supply: u256,
//         recipient: ContractAddress
//     ) {
//         self.initializer(name, symbol, decimals);
//         self._mint(recipient, initial_supply);
//     }

//     //
//     // External
//     //

//     #[external(v0)]
//     impl MyTokenImpl of IMyToken<ContractState> {
//         fn name(self: @ContractState) -> felt252 {
//             self._name.read()
//         }

//         fn symbol(self: @ContractState) -> felt252 {
//             self._symbol.read()
//         }

//         fn decimals(self: @ContractState) -> u8 {
//             self._decimals.read()
//         }

//         fn total_supply(self: @ContractState) -> u256 {
//             self._total_supply.read()
//         }

//         fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
//             self._balances.read(account)
//         }

//         fn allowance(
//             self: @ContractState, owner: ContractAddress, spender: ContractAddress
//         ) -> u256 {
//             self._allowances.read((owner, spender))
//         }

//         fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
//             let sender = get_caller_address();
//             self._transfer(sender, recipient, amount);
//             true
//         }

//         fn transfer_from(
//             ref self: ContractState,
//             sender: ContractAddress,
//             recipient: ContractAddress,
//             amount: u256
//         ) -> bool {
//             let caller = get_caller_address();
//             self._spend_allowance(sender, caller, amount);
//             self._transfer(sender, recipient, amount);
//             true
//         }

//         fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
//             let caller = get_caller_address();
//             self._approve(caller, spender, amount);
//             true
//         }
//     }

//     #[external(v0)]
//     impl ERC20CamelOnlyImpl of IERC20CamelOnly<ContractState> {
//         fn totalSupply(self: @ContractState) -> u256 {
//             MyTokenImpl::total_supply(self)
//         }
//         fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
//             MyTokenImpl::balance_of(self, account)
//         }
//         fn transferFrom(
//             ref self: ContractState,
//             sender: ContractAddress,
//             recipient: ContractAddress,
//             amount: u256
//         ) -> bool {
//             MyTokenImpl::transfer_from(ref self, sender, recipient, amount)
//         }
//     }

//     #[external(v0)]
//     fn increase_allowance(
//         ref self: ContractState, spender: ContractAddress, added_value: u256
//     ) -> bool {
//         self._increase_allowance(spender, added_value)
//     }

//     #[external(v0)]
//     fn increaseAllowance(
//         ref self: ContractState, spender: ContractAddress, addedValue: u256
//     ) -> bool {
//         increase_allowance(ref self, spender, addedValue)
//     }

//     #[external(v0)]
//     fn decrease_allowance(
//         ref self: ContractState, spender: ContractAddress, subtracted_value: u256
//     ) -> bool {
//         self._decrease_allowance(spender, subtracted_value)
//     }

//     #[external(v0)]
//     fn decreaseAllowance(
//         ref self: ContractState, spender: ContractAddress, subtractedValue: u256
//     ) -> bool {
//         decrease_allowance(ref self, spender, subtractedValue)
//     }

//     //
//     // Internal
//     //

//     #[generate_trait]
//     impl InternalImpl of InternalTrait {
//         fn initializer(ref self: ContractState, name_: felt252, symbol_: felt252, decimals_: u8) {
//             self._name.write(name_);
//             self._symbol.write(symbol_);
//             self._decimals.write(decimals_);
//         }

//         fn _increase_allowance(
//             ref self: ContractState, spender: ContractAddress, added_value: u256
//         ) -> bool {
//             let caller = get_caller_address();
//             self._approve(caller, spender, self._allowances.read((caller, spender)) + added_value);
//             true
//         }

//         fn _decrease_allowance(
//             ref self: ContractState, spender: ContractAddress, subtracted_value: u256
//         ) -> bool {
//             let caller = get_caller_address();
//             self
//                 ._approve(
//                     caller, spender, self._allowances.read((caller, spender)) - subtracted_value
//                 );
//             true
//         }

//         fn _mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
//             assert(!recipient.is_zero(), 'ERC20: mint to 0');
//             self._total_supply.write(self._total_supply.read() + amount);
//             self._balances.write(recipient, self._balances.read(recipient) + amount);
//             self.emit(Transfer { from: Zeroable::zero(), to: recipient, value: amount });
//         }

//         fn _burn(ref self: ContractState, account: ContractAddress, amount: u256) {
//             assert(!account.is_zero(), 'ERC20: burn from 0');
//             self._total_supply.write(self._total_supply.read() - amount);
//             self._balances.write(account, self._balances.read(account) - amount);
//             self.emit(Transfer { from: account, to: Zeroable::zero(), value: amount });
//         }

//         fn _approve(
//             ref self: ContractState, owner: ContractAddress, spender: ContractAddress, amount: u256
//         ) {
//             assert(!owner.is_zero(), 'ERC20: approve from 0');
//             assert(!spender.is_zero(), 'ERC20: approve to 0');
//             self._allowances.write((owner, spender), amount);
//             self.emit(Approval { owner, spender, value: amount });
//         }

//         fn _transfer(
//             ref self: ContractState,
//             sender: ContractAddress,
//             recipient: ContractAddress,
//             amount: u256
//         ) {
//             assert(!sender.is_zero(), 'ERC20: transfer from 0');
//             assert(!recipient.is_zero(), 'ERC20: transfer to 0');
//             self._balances.write(sender, self._balances.read(sender) - amount);
//             self._balances.write(recipient, self._balances.read(recipient) + amount);
//             self.emit(Transfer { from: sender, to: recipient, value: amount });
//         }

//         fn _spend_allowance(
//             ref self: ContractState, owner: ContractAddress, spender: ContractAddress, amount: u256
//         ) {
//             let current_allowance = self._allowances.read((owner, spender));
//             if current_allowance != BoundedInt::max() {
//                 self._approve(owner, spender, current_allowance - amount);
//             }
//         }
//     }
// }
