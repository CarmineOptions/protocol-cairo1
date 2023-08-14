use starknet::ContractAddress;
use debug::PrintTrait;
use cubit::f128::types::fixed::{Fixed, FixedTrait};

use carmine_protocol::amm_core::helpers::{
    fromU256_balance, toU256_balance
};

#[derive(Drop)]
struct FixedBalance {
    num: Fixed,
    decimals: u8
}

trait FixedBalanceTrait {
    fn new(num: Fixed, decs: u8) -> FixedBalance;
    fn from_u256_balance(num: u256, token_address: ContractAddress) -> FixedBalance;
    fn from_int_balance(num: u128, token_address: ContractAddress) -> FixedBalance;
}


// impl FixedBalanceImpl of FixedBalanceTrait {
//     fn new(num: Fixed, decs: u8) -> FixedBalance {
//         FixedBalance {
//             num: num,
//             decimals: decs
//         }
//     }

//     fn from_u256_balance(num: u256, token_address: ContractAddress) -> FixedBalance { }

//     fn from_int_balance(num: u128, token_address: ContractAddress) -> FixedBalance { }
    
// }


impl FixedBalanceIntoU256 of Into<FixedBalance, u256> {
    fn into(self: FixedBalance) -> u256 {
        1 // TODO
    }
}


impl FixedBalanceIntoU128 of Into<FixedBalance, u128> {
    fn into(self: FixedBalance) -> u128 {
        1 // TODO
    }
}

impl FixedBalancePrint of PrintTrait<FixedBalance> {
    fn print(self: FixedBalance) {
        self.num.print();
        self.decimals.print();
    }
}






