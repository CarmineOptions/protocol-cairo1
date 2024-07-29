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
use carmine_protocol::amm_core::state::State::write_latest_oracle_price;

#[test]
#[should_panic(expected: ('Cant set lpool < locked',))]
fn test_set_balance() {
    let (ctx, dsps) = deploy_setup();

    let five_tokens: u256 = 5000000000000000000; // with 18 decimals
    let five_k_tokens: u256 = 5000000000; // with 6 decimals

    let almost_five_k_tokens: u256 = 4950000000; // 4 950 USDC

    start_warp(ctx.amm_address, 1000000000);
    start_prank(ctx.amm_address, ctx.admin_address);
    start_mock_call(
        PRAGMA_ORACLE_ADDRESS.try_into().unwrap(),
        'get_data',
        PragmaPricesResponse {
            price: 190000000000,
            decimals: 8,
            last_updated_timestamp: 1000000000 + 60 * 60 * 12,
            num_sources_aggregated: 0,
            expiration_timestamp: Option::None(())
        }
    );

    ///////////////////////////////////////////////////
    // Open a long trade to lock in capital
    ///////////////////////////////////////////////////

    let new_expiry = _add_options_with_longer_expiry(ctx, dsps);

    // Opening 3.3 options -> all of unlocked (before premia)
    let five_int = 3300000000000000000; // 1*10**18
    let long_put_premia = dsps
        .amm
        .trade_open(
            1,
            ctx.strike_price,
            new_expiry.try_into().unwrap(),
            0,
            five_int,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_unscaled_felt(99999999999), // Disable this check
            99999999999 // Disable this check
        );

    ///////////////////////////////////////////////////
    // Open a short trade 
    ///////////////////////////////////////////////////
    // write_latest_oracle_price(
    //    ctx.eth_address,
    //    ctx.usdc_address,
    //    FixedTrait::ZERO(),
    //    0_u64
    // );

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

    let one_int = 1000000000000000000; // 1*10**18
    let short_put_premia = dsps
        .amm
        .trade_open(
            1, // Put
            ctx.strike_price,
            ctx.expiry,
            1, // short
            one_int,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_felt(1), // Disable this check
            99999999999 // Disable this check
        );
}

// We need another options that will be traded and pool will lock some caital in them
// adds put options only
fn _add_options_with_longer_expiry(ctx: Ctx, dsps: Dispatchers) -> felt252 {
    let another_expiry = 1000000000 + 60 * 60 * 48;

    let mut long_put_data = ArrayTrait::<felt252>::new();
    long_put_data.append('OptLongPut');
    long_put_data.append('OLP');
    long_put_data.append(ctx.amm_address.into());
    long_put_data.append(ctx.usdc_address.into());
    long_put_data.append(ctx.eth_address.into());
    long_put_data.append(1); // PUT
    long_put_data.append(27670116110564327424000);
    long_put_data.append(another_expiry);
    long_put_data.append(0); // LONG

    let mut short_put_data = ArrayTrait::<felt252>::new();
    short_put_data.append('OptShortPut');
    short_put_data.append('OSP');
    short_put_data.append(ctx.amm_address.into());
    short_put_data.append(ctx.usdc_address.into());
    short_put_data.append(ctx.eth_address.into());
    short_put_data.append(1); // Put
    short_put_data.append(27670116110564327424000);
    short_put_data.append(another_expiry);
    short_put_data.append(1); // short

    let new_long_put_address = ctx.opt_contract.deploy(@long_put_data).unwrap();
    let new_short_put_address = ctx.opt_contract.deploy(@short_put_data).unwrap();

    dsps
        .amm
        .add_option_both_sides(
            another_expiry.try_into().unwrap(),
            ctx.strike_price,
            ctx.usdc_address,
            ctx.eth_address,
            1, // type
            ctx.put_lpt_address,
            new_long_put_address,
            new_short_put_address,
            FixedTrait::from_unscaled_felt(100)
        );

    another_expiry
}

