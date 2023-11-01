use core::traits::Into;
use array::{ArrayTrait, SpanTrait};

use alexandria_sorting::merge_sort::merge;
use cubit::f128::types::fixed::{Fixed, FixedTrait};

use carmine_protocol::ilhedge::carmine::{available_strikes, buy_option, price_option};
use carmine_protocol::ilhedge::helpers::{convert_from_Fixed_to_int, reverse};

use starknet::ContractAddress;


fn iterate_strike_prices(
    curr_price: Fixed,
    quote_token_addr: ContractAddress,
    base_token_addr: ContractAddress,
    expiry: u64,
    calls: bool
) -> Span<(Fixed, Fixed)> {
    let MAX_HEDGE_CALLS: Fixed = FixedTrait::from_unscaled_felt(2400);
    let MAX_HEDGE_PUTS: Fixed = FixedTrait::from_unscaled_felt(800);

    let mut strike_prices_arr = available_strikes(expiry, quote_token_addr, base_token_addr, calls);
    let mut res = ArrayTrait::<(Fixed, Fixed)>::new();
    let mut strike_prices = merge(strike_prices_arr).span();
    if (!calls) {
        strike_prices = reverse(strike_prices);
    }
    let mut i = 0;
    loop {
        if (i + 1 == strike_prices.len()) {
            res
                .append(
                    (*strike_prices.at(i), if (calls) {
                        MAX_HEDGE_CALLS
                    } else {
                        MAX_HEDGE_PUTS
                    })
                );
            break;
        }
        // If both strikes are above (in case of puts) or below (in case of calls) current price, no point – so throw away.
        // This is handled by the other type of the options.
        let tobuy = *strike_prices.at(i);
        let tohedge = *strike_prices.at(i + 1);
        if (calls && (tobuy > curr_price || tohedge > curr_price)) {
            let pair: (Fixed, Fixed) = (tobuy, tohedge);
            res.append(pair);
        } else if (!calls && (tobuy < curr_price || tohedge < curr_price)) {
            let pair: (Fixed, Fixed) = (tobuy, tohedge);
            res.append(pair);
        }

        i += 1;
    };
    res.span()
}


use carmine_protocol::ilhedge::constants::{TOKEN_ETH_ADDRESS, TOKEN_USDC_ADDRESS};
use traits::TryInto;
use option::OptionTrait;
use debug::PrintTrait;
#[test]
#[available_gas(3000000)]
fn test_iterate_strike_prices_calls() {
    let res = iterate_strike_prices(
        FixedTrait::from_unscaled_felt(1650),
        TOKEN_USDC_ADDRESS.try_into().unwrap(),
        TOKEN_ETH_ADDRESS.try_into().unwrap(),
        1693526399,
        true
    );
    assert(res.len() == 4, 'len?');
    let (a, b) = res.at(0);
    assert(*a.mag == 1700 * 18446744073709551616, 1);
    assert(*b.mag == 1800 * 18446744073709551616, 2);
    let (a, b) = res.at(1);
    assert(*a.mag == 1800 * 18446744073709551616, 3);
    assert(*b.mag == 1900 * 18446744073709551616, 4);
    let (a, b) = res.at(2);
    assert(*a.mag == 1900 * 18446744073709551616, 5);
    assert(*b.mag == 2000 * 18446744073709551616, 6);
    let (a, b) = res.at(3);
    assert(*a.mag == 2000 * 18446744073709551616, 7);
    assert(*b.mag == 2400 * 18446744073709551616, 8);
}

#[test]
#[available_gas(3000000)]
fn test_iterate_strike_prices_puts() {
    let res = iterate_strike_prices(
        FixedTrait::from_unscaled_felt(1650),
        TOKEN_USDC_ADDRESS.try_into().unwrap(),
        TOKEN_ETH_ADDRESS.try_into().unwrap(),
        1693526399,
        false
    );
    assert(res.len() == 4, 'len 2?');
    let (a, b) = res.at(0);
    assert(*a.mag == 1600 * 18446744073709551616, 1);
    assert(*b.mag == 1500 * 18446744073709551616, 2);
    let (a, b) = res.at(1);
    assert(*a.mag == 1500 * 18446744073709551616, 3);
    assert(*b.mag == 1400 * 18446744073709551616, 4);
    let (a, b) = res.at(2);
    assert(*a.mag == 1400 * 18446744073709551616, 5);
    assert(*b.mag == 1300 * 18446744073709551616, 6);
    let (a, b) = res.at(3);
    assert(*a.mag == 1300 * 18446744073709551616, 5);
    assert(*b.mag == 800 * 18446744073709551616, 6);
}

// Calculates how much to buy at buystrike to get specified payoff at hedgestrike. Payoff is in quote token for puts, base token for calls.
// Put asset is expected to have 6 decimals.
fn how_many_options_at_strike_to_hedge_at(
    to_buy_strike: Fixed, to_hedge_strike: Fixed, payoff: Fixed, calls: bool
) -> u128 {
    if (calls) {
        assert(to_hedge_strike > to_buy_strike, 'tohedge<=tobuy');
        let res = payoff / (to_hedge_strike - to_buy_strike);
        convert_from_Fixed_to_int(res, 18)
    } else {
        assert(to_hedge_strike < to_buy_strike, 'tohedge>=tobuy');
        let res = payoff / (to_buy_strike - to_hedge_strike);
        convert_from_Fixed_to_int(res, 18)
    }
}


// Calculates how much to buy at buystrike to get specified payoff at hedgestrike.
// And buys via carmine module.
fn buy_options_at_strike_to_hedge_at(
    to_buy_strike: Fixed,
    to_hedge_strike: Fixed,
    payoff: Fixed,
    expiry: u64,
    quote_token_addr: ContractAddress,
    base_token_addr: ContractAddress,
    amm_address: ContractAddress,
    calls: bool,
) {
    let notional = how_many_options_at_strike_to_hedge_at(
        to_buy_strike, to_hedge_strike, payoff, calls
    );
    buy_option(to_buy_strike, notional, expiry, calls, amm_address, quote_token_addr, base_token_addr);
}


fn price_options_at_strike_to_hedge_at(
    to_buy_strike: Fixed, to_hedge_strike: Fixed, payoff: Fixed, expiry: u64, amm_address: ContractAddress, quote_token_addr: ContractAddress, base_token_addr: ContractAddress, calls: bool
) -> u128 {
    let notional = how_many_options_at_strike_to_hedge_at(
        to_buy_strike, to_hedge_strike, payoff, calls
    );
    //notional
    price_option(to_buy_strike, notional, expiry, calls, amm_address, quote_token_addr, base_token_addr)
}


#[test]
#[available_gas(3000000)]
fn test_how_many_options_at_strike_to_hedge_at() {
    let res = how_many_options_at_strike_to_hedge_at(
        FixedTrait::from_unscaled_felt(1000),
        FixedTrait::from_unscaled_felt(1100),
        FixedTrait::ONE(),
        true
    );
    assert(res > 99 * 100000000000000 && res < 101 * 100000000000000, 'rescalls?');

    let res = how_many_options_at_strike_to_hedge_at(
        FixedTrait::from_unscaled_felt(1000),
        FixedTrait::from_unscaled_felt(900),
        FixedTrait::ONE(),
        false
    );
    assert(res > 99 * 100000000000000 && res < 101 * 1000000000000000, 'resputs?');

    // repro attempt
    let res = how_many_options_at_strike_to_hedge_at(
        FixedTrait::from_unscaled_felt(1700),
        FixedTrait::from_unscaled_felt(1800),
        FixedTrait::from_felt(0xb93a99eda0819d),
        true
    );
    //res.print();
    // result is 100000000000000170703 => 100.00000000000017, what the fuck??
    assert(
        res < 1000000000000000000, 'buying way too many options'
    ); //0xb93a99eda0819d => 0.002, should be buying less than that in options...
    assert(res < 2826368885168429, 'buying > payoff amt');
}
