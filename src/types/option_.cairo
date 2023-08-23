use starknet::ContractAddress;
use debug::PrintTrait;
use core::traits::{TryInto, Into};
use core::option::OptionTrait;
use starknet::get_block_timestamp;
use carmine_protocol::amm_core::helpers::{
    fromU256_balance, split_option_locked_capital, FixedHelpersTrait
};
use cubit::f128::types::fixed::{Fixed, FixedTrait};

// use carmine_protocol::basic::{OptionSide, OptionType, Timestamp, LegacyStrike, Int};

type OptionSide = u8; // TODO: Make this an enum
type OptionType = u8; // TODO: Make this an enum
type Timestamp = u64; // In seconds, Block timestamps are also u64

type Int = u128;

type Math64x61_ = felt252; // legacy, for AMM trait definition
type LegacyStrike = Math64x61_;


use carmine_protocol::amm_core::state::State::{
    get_lptoken_address_for_given_option, get_option_volatility,
    get_pool_volatility_adjustment_speed, get_option_position, get_option_token_address
};

use carmine_protocol::amm_core::constants::{
    RISK_FREE_RATE, TRADE_SIDE_LONG, STOP_TRADING_BEFORE_MATURITY_SECONDS, get_opposite_side,
    OPTION_CALL,
};

use carmine_protocol::amm_core::pricing::option_pricing_helpers::{
    get_new_volatility, get_time_till_maturity, select_and_adjust_premia, add_premia_fees
};


use carmine_protocol::amm_core::pricing::fees::{get_fees};
use carmine_protocol::amm_core::pricing::option_pricing::OptionPricing::black_scholes;

use carmine_protocol::amm_core::oracles::agg::OracleAgg::{get_current_price, get_terminal_price};

use carmine_protocol::traits::{
    IOptionTokenDispatcher, IOptionTokenDispatcherTrait, IERC20Dispatcher, IERC20DispatcherTrait
};


// Option used in c0 AMM
#[derive(Copy, Drop, Serde, starknet::Store)]
struct LegacyOption {
    option_side: OptionSide,
    maturity: felt252,
    strike_price: LegacyStrike,
    quote_token_address: ContractAddress,
    base_token_address: ContractAddress,
    option_type: OptionType
}

// impl PackFixed of StorePacking<LegacyOption, felt252> {
//     fn pack(value: Fixed) -> felt252 {
//         let MAX_MAG_PLUS_ONE = 0x100000000000000000000000000000000; // 2**128
//         let packed_sign = MAX_MAG_PLUS_ONE * value.sign.into();
//         value.mag.into() + packed_sign
//     }

//     fn unpack(value: felt252) -> Fixed {
//         let (q, r) = U256DivRem::div_rem(value.into(), u256_as_non_zero(0x100000000000000000000000000000000));
//         let mag: u128 = q.try_into().unwrap();
//         let sign: bool = r.into() == 1;
//         Fixed {mag: mag, sign: sign}
//     }
// }

// New option
#[derive(Copy, Drop, Serde, starknet::Store)]
struct Option_ {
    option_side: OptionSide,
    maturity: Timestamp,
    strike_price: Fixed,
    quote_token_address: ContractAddress,
    base_token_address: ContractAddress,
    option_type: OptionType
}

use carmine_protocol::amm_core::helpers::_pow;

#[generate_trait]
impl Option_Impl of Option_Trait {
    fn sum(self: Option_) -> u128 {
        self.strike_price.mag + self.maturity.into()
    }

    fn correct_side(self: Option_, closing: bool) -> Option_ {
        if closing {
            let correct_side = get_opposite_side(self.option_side);
            Option_ {
                option_side: get_opposite_side(self.option_side),
                maturity: self.maturity,
                strike_price: self.strike_price,
                quote_token_address: self.quote_token_address,
                base_token_address: self.base_token_address,
                option_type: self.option_type,
            }
        } else {
            self
        }
    }

    fn is_ripe(self: Option_) -> bool {
        let current_block_time = get_block_timestamp();

        self.maturity <= current_block_time
    }

    fn opt_address(self: Option_) -> ContractAddress {
        get_option_token_address(
            self.lpt_addr(), self.option_side, self.maturity, self.strike_price
        )
    }

    fn lpt_addr(self: Option_) -> ContractAddress {
        get_lptoken_address_for_given_option(
            self.quote_token_address, self.base_token_address, self.option_type
        )
    }

    fn volatility(self: Option_) -> Fixed {
        get_option_volatility(self.lpt_addr(), self.maturity, self.strike_price)
    }

    fn premia_before_fees(self: Option_, position_size: Int) -> Fixed {
        // For clarity
        let option_size = position_size;
        let option_size_cubit = fromU256_balance(position_size.into(), self.base_token_address);
        let pool_volatility_adjustment_speed = get_pool_volatility_adjustment_speed(
            self.lpt_addr()
        );
        

        // 1) Get current underlying price
        let underlying_price = get_current_price(self.quote_token_address, self.base_token_address);

        //let current_block_time = get_block_timestamp();
        let time_till_maturity = get_time_till_maturity(self.maturity);

        underlying_price
    }


    fn premia_with_fees(self: Option_, position_size: Int) -> Fixed {
        let total_premia_before_fees = self.premia_before_fees(position_size, );
        total_premia_before_fees.assert_nn('GPWF - total premia < 0');

        let total_fees = get_fees(total_premia_before_fees);
        total_fees.assert_nn('GPWF - total fees < 0');

        let premia_with_fees = add_premia_fees(
            self.option_side, total_premia_before_fees, total_fees
        );
        premia_with_fees.assert_nn('GPWF - premia w/ fees < 0');

        premia_with_fees
    }


    fn value_of_position(self: Option_, position_size: Int) -> Fixed {
        let current_block_time = get_block_timestamp();
        let is_ripe = self.maturity <= current_block_time;

        let position_size_cubit = fromU256_balance(position_size.into(), self.base_token_address);

        if is_ripe {
            let terminal_price = get_terminal_price(
                self.quote_token_address, self.base_token_address, self.maturity
            );

            let (long_value, short_value) = split_option_locked_capital(
                self.option_type,
                self.option_side,
                position_size_cubit,
                self.strike_price,
                terminal_price
            );

            if self.option_side == TRADE_SIDE_LONG {
                return long_value;
            } else {
                return short_value;
            }
        }

        // Fail if the value of option that matures in 2 hours or less (can't price the option)
        let stop_trading_by = self.maturity - STOP_TRADING_BEFORE_MATURITY_SECONDS;
        assert(current_block_time <= stop_trading_by, 'GVoP - Wait till maturity');

        let total_premia_before_fees = self.premia_before_fees(position_size, );

        // Get fees and total premia
        let total_fees = get_fees(total_premia_before_fees);
        total_fees.assert_nn('GVoP - total fees < 0');

        let opposite_side = get_opposite_side(self.option_side);

        let premia_with_fees = add_premia_fees(opposite_side, total_premia_before_fees, total_fees);
        premia_with_fees.assert_nn('GVoP - premia w fees < 0');

        if self.option_side == TRADE_SIDE_LONG {
            return premia_with_fees;
        }

        if self.option_type == OPTION_CALL {
            let locked_and_premia_with_fees = position_size_cubit - premia_with_fees;
            locked_and_premia_with_fees.assert_nn('GVoP - locked_prem_fee < 0');

            return locked_and_premia_with_fees;
        } else {
            let locked_capital = position_size_cubit * self.strike_price;
            let locked_and_premia_with_fees = locked_capital - premia_with_fees;
            locked_and_premia_with_fees.assert_nn('GVoP - locked_prem_fee < 0');

            return locked_and_premia_with_fees;
        }
    }

    fn pools_position(self: Option_) -> Int {
        get_option_position(self.lpt_addr(), self.option_side, self.maturity, self.strike_price)
    }


    fn value_of_user_position(self: Option_, position_size: Int) -> Fixed {
        if self.is_ripe() {
            let terminal_price = get_terminal_price(
                self.quote_token_address, self.base_token_address, self.maturity
            );

            let (long_value, short_value) = split_option_locked_capital(
                self.option_type,
                self.option_side,
                fromU256_balance(position_size.into(), self.base_token_address),
                self.strike_price,
                terminal_price
            );

            if self.option_side == TRADE_SIDE_LONG {
                return long_value;
            } else {
                return short_value;
            }
        }

        // TODO: is this correct?
        // Value of an option should be value that user would be able to get 
        // if they were to close the position, so we need to pretend we're closing the position
        self.correct_side(true).premia_with_fees(position_size)
    }

    fn get_dispatcher(self: Option_) -> IOptionTokenDispatcher {
        IOptionTokenDispatcher { contract_address: self.opt_address() }
    }
}


// Helper structs for View functions
#[derive(Drop, Copy, Serde)]
struct OptionWithPremia {
    option: Option_,
    premia: Fixed,
}

#[derive(Drop, Serde)]
struct OptionWithUsersPosition {
    option: Option_,
    position_size: u256,
    value_of_position: Fixed
}

// Helper functions
fn Option_to_LegacyOption(opt: Option_) -> LegacyOption {
    LegacyOption {
        option_side: opt.option_side,
        maturity: opt.maturity.into(),
        strike_price: opt.strike_price.to_legacyMath(),
        quote_token_address: opt.quote_token_address,
        base_token_address: opt.base_token_address,
        option_type: opt.option_type
    }
}

fn LegacyOption_to_Option(opt: LegacyOption) -> Option_ {
    Option_ {
        option_side: opt.option_side,
        maturity: opt.maturity.try_into().unwrap(),
        strike_price: FixedHelpersTrait::from_legacyMath(opt.strike_price),
        quote_token_address: opt.quote_token_address,
        base_token_address: opt.base_token_address,
        option_type: opt.option_type
    }
}

impl Option_Print of PrintTrait<Option_> {
    fn print(self: Option_) {
        self.option_side.print();
        self.maturity.print();
        self.strike_price.print();
        self.quote_token_address.print();
        self.base_token_address.print();
        self.option_type.print();
    }
}

impl LegacyOptionPrint of PrintTrait<LegacyOption> {
    fn print(self: LegacyOption) {
        self.option_side.print();
        self.maturity.print();
        self.strike_price.print();
        self.quote_token_address.print();
        self.base_token_address.print();
        self.option_type.print();
    }
}
