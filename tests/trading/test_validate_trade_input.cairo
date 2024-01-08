
use carmine_protocol::testing::setup::deploy_setup;
use traits::{Into, TryInto};
use debug::PrintTrait;
use option::OptionTrait;
use carmine_protocol::testing::test_utils::{Stats, StatsTrait};
use carmine_protocol::amm_core::oracles::pragma::Pragma::PRAGMA_ORACLE_ADDRESS;
use carmine_protocol::amm_core::oracles::pragma::PragmaUtils::{
    PragmaPricesResponse, Checkpoint, AggregationMode
};
use cubit::f128::types::fixed::{Fixed, FixedTrait};
use snforge_std::{
    declare, ContractClassTrait, start_prank, stop_prank, start_warp, stop_warp, ContractClass,
    start_mock_call, stop_mock_call, start_roll
};
use carmine_protocol::amm_core::helpers::{FixedHelpersTrait, toU256_balance};
use carmine_protocol::amm_core::amm::AMM;
use carmine_protocol::amm_interface::{IAMMDispatcher, IAMMDispatcherTrait};
use carmine_protocol::testing::setup::{Ctx, Dispatchers};

use carmine_protocol::tokens::my_token::{MyToken, IMyTokenDispatcher, IMyTokenDispatcherTrait};

fn prep_for_test() -> (Ctx, Dispatchers) {
    let (ctx, dsps) = deploy_setup();
    let one_int = 1000000000000000000; // 1*10**18

    start_warp(ctx.amm_address, 1000000000);
    start_prank(ctx.amm_address, ctx.admin_address);
    start_mock_call(
        PRAGMA_ORACLE_ADDRESS.try_into().unwrap(),
        'get_data',
        PragmaPricesResponse {
            price: 140000000000,
            decimals: 8,
            last_updated_timestamp: 1000000000 + 60 * 60 * 12,
            num_sources_aggregated: 0,
            expiration_timestamp: Option::None(())
        }
    );
    (ctx, dsps)
}

#[test]
fn test_option_type_call() {
    let one_int = 1000000000000000000; // 1*10**18
    let (ctx, dsps) = prep_for_test();
    // Longs
    let long_call_premia = dsps
        .amm
        .trade_open(
            0, // Call
            ctx.strike_price,
            ctx.expiry,
            0, // Long
            one_int,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_unscaled_felt(100_000), // Disable this check
            99999999999 // Disable this check
        );
}

#[test]
fn test_option_type_put() {
    let (ctx, dsps) = prep_for_test();
    let one_int = 1000000000000000000; // 1*10**18
    // Longs
    let long_call_premia = dsps
        .amm
        .trade_open(
            1, // Put
            ctx.strike_price,
            ctx.expiry,
            0, // Long
            one_int,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_unscaled_felt(100_000), // Disable this check
            99999999999 // Disable this check
        );
}


// NOTE: test below fails in function get_lptoken_address_for_given_option
// because it is called before VTI
#[test]
#[should_panic(expected: ('GLAFGO - pool non existent',))]
fn test_option_type_failing() {
    let one_int = 1000000000000000000; // 1*10**18
    let (ctx, dsps) = prep_for_test();
    // Longs
    let long_call_premia = dsps
        .amm
        .trade_open(
            2, // Put
            ctx.strike_price,
            ctx.expiry,
            0, // Long
            one_int,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_unscaled_felt(100_000), // Disable this check
            99999999999 // Disable this check
        );
}

#[test]
fn test_option_side_long() {
    let one_int = 1000000000000000000; // 1*10**18
    let (ctx, dsps) = prep_for_test();
    // Longs
    let long_call_premia = dsps
        .amm
        .trade_open(
            0, // Call
            ctx.strike_price,
            ctx.expiry,
            0, // Long
            one_int,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_unscaled_felt(100_000), // Disable this check
            99999999999 // Disable this check
        );
}

#[test]
fn test_option_side_short() {
    let one_int = 1000000000000000000; // 1*10**18
    let (ctx, dsps) = prep_for_test();
    // Longs
    let long_call_premia = dsps
        .amm
        .trade_open(
            0, // Call
            ctx.strike_price,
            ctx.expiry,
            1, // Short
            one_int,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_felt(1), // Disable this check
            99999999999 // Disable this check
        );
}

#[test]
#[should_panic(expected: ('VTI - invalid option side',))]
fn test_option_side_failing() {
    let one_int = 1000000000000000000; // 1*10**18
    let (ctx, dsps) = prep_for_test();
    // Longs
    let long_call_premia = dsps
        .amm
        .trade_open(
            0, // Call
            ctx.strike_price,
            ctx.expiry,
            2, // Idk
            one_int,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_felt(1), // Disable this check
            99999999999 // Disable this check
        );
}


#[test]
#[should_panic(expected: ('VTI - opt unavailable',))]
fn test_maturity_option_not_available() {
    let one_int = 1000000000000000000; // 1*10**18
    let (ctx, dsps) = prep_for_test();
    // Longs
    let long_call_premia = dsps
        .amm
        .trade_open(
            0, // Call
            ctx.strike_price,
            1000000999,
            0, // Long
            one_int,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_felt(1), // Disable this check
            99999999999 // Disable this check
        );
}

#[test]
#[should_panic(expected: ('VTI - opt already expired',))]
fn test_maturity_option_expired() {
    let one_int = 1000000000000000000; // 1*10**18
    let (ctx, dsps) = prep_for_test();
    // Longs
    start_warp(ctx.amm_address, ctx.expiry + 1);
    let long_call_premia = dsps
        .amm
        .trade_open(
            0, // Call
            ctx.strike_price,
            ctx.expiry,
            0, // Long
            one_int,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_felt(1), // Disable this check
            99999999999 // Disable this check
        );
}

#[test]
#[should_panic(expected: ('VTI - Trading is stopped',))]
fn test_maturity_trading_stopped() {
    let one_int = 1000000000000000000; // 1*10**18
    let (ctx, dsps) = prep_for_test();
    // Longs
    start_warp(ctx.amm_address, ctx.expiry - 1);
    let long_call_premia = dsps
        .amm
        .trade_open(
            0, // Call
            ctx.strike_price,
            ctx.expiry,
            0, // Long
            one_int,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_felt(1), // Disable this check
            99999999999 // Disable this check
        );
}

