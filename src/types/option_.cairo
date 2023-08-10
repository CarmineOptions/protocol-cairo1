use starknet::ContractAddress;
use core::traits::{TryInto, Into};
use core::option::OptionTrait;
use starknet::get_block_timestamp;
use carmine_protocol::amm_core::helpers::{
    legacyMath_to_cubit, cubit_to_legacyMath, fromU256_balance, split_option_locked_capital
};
use cubit::f128::types::fixed::{Fixed, FixedTrait};

use carmine_protocol::types::basic::{OptionSide, OptionType, Timestamp, LegacyStrike, Int};
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

use carmine_protocol::amm_core::pricing::option_pricing::{black_scholes};

use carmine_protocol::amm_core::oracles::agg::OracleAgg::{get_current_price, get_terminal_price};

// Option used in c0 AMM
#[derive(Copy, Drop, Serde, Store)]
struct LegacyOption {
    option_side: OptionSide,
    maturity: felt252,
    strike_price: LegacyStrike,
    quote_token_address: ContractAddress,
    base_token_address: ContractAddress,
    option_type: OptionType
}

// New option
#[derive(Copy, Drop, Serde, Store)]
struct Option_ {
    option_side: OptionSide,
    maturity: Timestamp,
    strike_price: Fixed,
    quote_token_address: ContractAddress,
    base_token_address: ContractAddress,
    option_type: OptionType
}

trait Option_Trait {
    fn sum(self: Option_) -> u128;
    fn is_ripe(self: Option_) -> bool;
    fn correct_side(self: Option_, closing: bool) -> Option_;
    fn opt_address(self: Option_) -> ContractAddress;
    fn lpt_addr(self: Option_) -> ContractAddress;
    fn volatility(self: Option_) -> Fixed;
    fn premia_before_fees(self: Option_, position_size: Int) -> Fixed;
    fn premia_with_fees(self: Option_, position_size: Int) -> Fixed;
    fn value_of_position(self: Option_, position_size: Int) -> Fixed;
    fn pools_position(self: Option_) -> Int;
    fn value_of_user_position(self: Option_, position_size: Int) -> Fixed;
}


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

        // 2) Get trade vol
        let (_, trade_volatility) = get_new_volatility(
            self.volatility(),
            option_size_cubit,
            self.option_type,
            self.option_side,
            self.strike_price,
            pool_volatility_adjustment_speed
        );

        // 3) Get TTM
        let time_till_maturity = get_time_till_maturity(self.maturity);

        // 4) Get Risk free rate
        let risk_free_rate_annualized = FixedTrait::from_felt(RISK_FREE_RATE);

        // 5) Get premia
        let hundred = FixedTrait::from_unscaled_felt(100);
        let sigma = trade_volatility / hundred;

        let (call_premia, put_premia, is_usable) = black_scholes(
            sigma,
            time_till_maturity,
            self.strike_price,
            underlying_price,
            risk_free_rate_annualized,
            false
        );
        let zero = FixedTrait::from_felt(0);

        assert(call_premia >= zero, 'GPBF - call_premia < 0');
        assert(put_premia >= zero, 'GPBF - put_premia < 0');

        let premia = select_and_adjust_premia(
            call_premia, put_premia, self.option_type, underlying_price
        );

        let total_premia_before_fees = premia * option_size_cubit;

        assert(premia >= zero, 'GPBF - premia < 0');
        assert(total_premia_before_fees >= zero, 'GPBF - premia_before_fees < 0');

        total_premia_before_fees
    }


    fn premia_with_fees(self: Option_, position_size: Int) -> Fixed {
        let total_premia_before_fees = self.premia_before_fees(position_size, );
        assert(total_premia_before_fees >= FixedTrait::ZERO(), 'GPWF - total premia < 0');

        let total_fees = get_fees(total_premia_before_fees);
        assert(total_fees >= FixedTrait::ZERO(), 'GPWF - total fees < 0');

        let premia_with_fees = add_premia_fees(
            self.option_side, total_premia_before_fees, total_fees
        );
        assert(premia_with_fees >= FixedTrait::ZERO(), 'GPWF - premia w/ fees < 0');

        premia_with_fees
    }


    fn value_of_position(self: Option_, position_size: Int) -> Fixed {
        let zero = FixedTrait::ZERO();

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
        assert(total_fees >= zero, 'GVoP - total fees < 0');

        let opposite_side = get_opposite_side(self.option_side);

        let premia_with_fees = add_premia_fees(opposite_side, total_premia_before_fees, total_fees);

        assert(premia_with_fees >= zero, 'GVoP - premia w fees < 0');

        if self.option_side == TRADE_SIDE_LONG {
            return premia_with_fees;
        }

        if self.option_type == OPTION_CALL {
            let locked_and_premia_with_fees = position_size_cubit - premia_with_fees;
            assert(locked_and_premia_with_fees >= zero, 'GVoP - locked_prem_fee < 0');

            return locked_and_premia_with_fees;
        } else {
            let locked_capital = position_size_cubit * self.strike_price;
            let locked_and_premia_with_fees = locked_capital - premia_with_fees;
            assert(locked_and_premia_with_fees >= zero, 'GVoP - locked_prem_fee < 0');

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
}


// Helper structs for View functions
#[derive(Drop)]
struct OptionWithPremia {
    option: Option_,
    premia: Fixed,
}

#[derive(Drop)]
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
        strike_price: cubit_to_legacyMath(opt.strike_price),
        quote_token_address: opt.quote_token_address,
        base_token_address: opt.base_token_address,
        option_type: opt.option_type
    }
}

fn LegacyOption_to_Option(opt: LegacyOption) -> Option_ {
    Option_ {
        option_side: opt.option_side,
        maturity: opt.maturity.try_into().unwrap(),
        strike_price: legacyMath_to_cubit(opt.strike_price),
        quote_token_address: opt.quote_token_address,
        base_token_address: opt.base_token_address,
        option_type: opt.option_type
    }
}
