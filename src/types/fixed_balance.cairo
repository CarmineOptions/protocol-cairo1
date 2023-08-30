use starknet::ContractAddress;
use debug::PrintTrait;
use core::option::OptionTrait;
use traits::{Into, TryInto};

use cubit::f128::types::fixed::{Fixed, FixedTrait};

use carmine_protocol::amm_core::helpers::{fromU256_balance, _toU256_balance};

use carmine_protocol::amm_core::helpers::get_decimal;

#[derive(Drop)]
struct FixedBalance {
    balance: Fixed,
    decimals: u8,
    address: ContractAddress
}

#[generate_trait]
impl FixedBalanceImpl of FixedBalanceTrait {
    fn new(num: Fixed, token_address: ContractAddress) -> FixedBalance {
        let decimals = get_decimal(token_address).expect('FixBal - decimals 0');

        FixedBalance { balance: num, decimals: decimals, address: token_address }
    }

    fn from_u256_balance(num: u256, token_address: ContractAddress) -> FixedBalance {
        let res = fromU256_balance(num, token_address);

        FixedBalanceTrait::new(res, token_address)
    }

    fn from_int_balance(num: u128, token_address: ContractAddress) -> FixedBalance {
        let res = fromU256_balance(num.into(), token_address);

        FixedBalanceTrait::new(res, token_address)
    }
}


impl FixedBalanceIntoU256 of Into<FixedBalance, u256> {
    fn into(self: FixedBalance) -> u256 {
        _toU256_balance(self.balance, self.decimals.into())
    }
}


impl FixedBalanceIntoU128 of Into<FixedBalance, u128> {
    fn into(self: FixedBalance) -> u128 {
        _toU256_balance(self.balance, self.decimals.into())
            .try_into()
            .expect('FixedBalIntoU128 - bal large')
    }
}

impl FixedBalancePrint of PrintTrait<FixedBalance> {
    fn print(self: FixedBalance) {
        self.balance.print();
        self.decimals.print();
        self.address.print();
    }
}

impl FixedBalanceAdd of Add<FixedBalance> {
    fn add(lhs: FixedBalance, rhs: FixedBalance) -> FixedBalance {
        assert(lhs.address == rhs.address, 'FixedBalanceAdd - diff addr');
        assert(lhs.decimals == rhs.decimals, 'FixedBalanceAdd - diff dec');

        FixedBalance {
            balance: lhs.balance + rhs.balance, decimals: lhs.decimals, address: lhs.address
        }
    }
}

impl FixedBalanceAddEq of AddEq<FixedBalance> {
    #[inline(always)]
    fn add_eq(ref self: FixedBalance, other: FixedBalance) {
        assert(self.address == other.address, 'FixedBalanceAddEq - diff addr');
        assert(self.decimals == other.decimals, 'FixedBalanceAddEq - diff dec');

        self =
            FixedBalance {
                balance: self.balance + other.balance,
                decimals: self.decimals,
                address: self.address
            }
    }
}

impl FixedBalanceSub of Sub<FixedBalance> {
    fn sub(lhs: FixedBalance, rhs: FixedBalance) -> FixedBalance {
        assert(lhs.address == rhs.address, 'FixedBalanceSub - diff addr');
        assert(lhs.decimals == rhs.decimals, 'FixedBalanceSub- diff dec');

        FixedBalance {
            balance: lhs.balance - rhs.balance, decimals: lhs.decimals, address: lhs.address
        }
    }
}

impl FixedBalanceSubEq of SubEq<FixedBalance> {
    #[inline(always)]
    fn sub_eq(ref self: FixedBalance, other: FixedBalance) {
        assert(self.address == other.address, 'FixedBalanceSubEq - diff addr');
        assert(self.decimals == other.decimals, 'FixedBalanceSubEq - diff dec');

        self =
            FixedBalance {
                balance: self.balance - other.balance,
                decimals: self.decimals,
                address: self.address
            }
    }
}

impl FixedBalancePartialEq of PartialEq<FixedBalance> {
    #[inline(always)]
    fn eq(lhs: @FixedBalance, rhs: @FixedBalance) -> bool {
        assert(lhs.address == rhs.address, 'FixedBalanceParEq - diff addr');
        assert(lhs.decimals == rhs.decimals, 'FixedBalanceParEq - diff dec');

        lhs.balance == rhs.balance
    }

    #[inline(always)]
    fn ne(lhs: @FixedBalance, rhs: @FixedBalance) -> bool {
        assert(lhs.address == rhs.address, 'FixedBalanceParNe - diff addr');
        assert(lhs.decimals == rhs.decimals, 'FixedBalanceParNe - diff dec');

        lhs.balance != rhs.balance
    }
}

impl FixedBalancePartialOrd of PartialOrd<FixedBalance> {
    #[inline(always)]
    fn ge(lhs: FixedBalance, rhs: FixedBalance) -> bool {
        assert(lhs.address == rhs.address, 'FixedBalanceParGe - diff addr');
        assert(lhs.decimals == rhs.decimals, 'FixedBalanceParGe - diff dec');

        lhs.balance >= rhs.balance
    }

    #[inline(always)]
    fn gt(lhs: FixedBalance, rhs: FixedBalance) -> bool {
        assert(lhs.address == rhs.address, 'FixedBalanceParGt - diff addr');
        assert(lhs.decimals == rhs.decimals, 'FixedBalanceParGt - diff dec');

        lhs.balance > rhs.balance
    }

    #[inline(always)]
    fn le(lhs: FixedBalance, rhs: FixedBalance) -> bool {
        assert(lhs.address == rhs.address, 'FixedBalanceParLe - diff addr');
        assert(lhs.decimals == rhs.decimals, 'FixedBalanceParLe - diff dec');

        lhs.balance <= rhs.balance
    }

    #[inline(always)]
    fn lt(lhs: FixedBalance, rhs: FixedBalance) -> bool {
        assert(lhs.address == rhs.address, 'FixedBalanceParLt - diff addr');
        assert(lhs.decimals == rhs.decimals, 'FixedBalanceParLt - diff dec');

        lhs.balance < rhs.balance
    }
}
