use starknet::ContractAddress;
use carmine_protocol::amm_core::peripheries::view::View;
use carmine_protocol::testing::setup::{deploy_setup, _add_expired_option};
use array::ArrayTrait;
use debug::PrintTrait;
use carmine_protocol::amm_core::amm::AMM;
use carmine_protocol::amm_interface::{IAMMDispatcher, IAMMDispatcherTrait};
use carmine_protocol::types::option_::{Option_Trait, Option_};
use cubit::f128::types::{Fixed, FixedTrait};
use snforge_std::{start_prank, stop_prank, start_warp, stop_warp, start_mock_call, stop_mock_call};
use traits::{TryInto, Into};
use option::OptionTrait;

use carmine_protocol::amm_core::oracles::pragma::Pragma::PRAGMA_ORACLE_ADDRESS;
use carmine_protocol::amm_core::oracles::pragma::PragmaUtils::{
    PragmaPricesResponse, Checkpoint, AggregationMode
};


#[test]
fn test_set_trading_halt_permission() {
    let (ctx, dsps) = deploy_setup();

    let dummy_addr: felt252 = 0x0178227144f45dd9e704dab545018813d17383e4cd1181a94fb7086df8cc50e1;

    // Permission not set yet
    assert(
        !dsps.amm.get_trading_halt_permission(dummy_addr.try_into().unwrap()), 'Should be false1'
    );

    // Set permission to true
    start_prank(ctx.amm_address, ctx.admin_address);
    dsps.amm.set_trading_halt_permission(dummy_addr.try_into().unwrap(), true);
    assert(dsps.amm.get_trading_halt_permission(dummy_addr.try_into().unwrap()), 'Should be true');

    // Set permission to false
    dsps.amm.set_trading_halt_permission(dummy_addr.try_into().unwrap(), false);
    assert(
        !dsps.amm.get_trading_halt_permission(dummy_addr.try_into().unwrap()), 'Should be false2'
    );
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_set_trading_halt_permission_failing() {
    let (ctx, dsps) = deploy_setup();
    let dummy_addr: felt252 = 0x0178227144f45dd9e704dab545018813d17383e4cd1181a94fb7086df8cc50e1;

    // Try to set permission
    start_prank(ctx.amm_address, dummy_addr.try_into().unwrap());
    dsps.amm.set_trading_halt_permission(dummy_addr.try_into().unwrap(), true);
}


#[test]
fn test_set_trading_halt() {
    let (ctx, dsps) = deploy_setup();
    let dummy_addr: felt252 = 0x0178227144f45dd9e704dab545018813d17383e4cd1181a94fb7086df8cc50e1;

    // Set permission to true
    start_prank(ctx.amm_address, ctx.admin_address);
    dsps.amm.set_trading_halt_permission(dummy_addr.try_into().unwrap(), true);

    // set halt to true
    start_prank(ctx.amm_address, dummy_addr.try_into().unwrap());
    dsps.amm.set_trading_halt(true);

    // assert 
    assert(dsps.amm.get_trading_halt(), 'should be true');
}

#[test]
#[should_panic(expected: ('Cant set trading halt status',))]
fn test_set_trading_halt_failing() {
    let (ctx, dsps) = deploy_setup();
    let dummy_addr: felt252 = 0x0178227144f45dd9e704dab545018813d17383e4cd1181a94fb7086df8cc50e1;

    // Set permission to true
    start_prank(ctx.amm_address, ctx.admin_address);
    dsps.amm.set_trading_halt_permission(dummy_addr.try_into().unwrap(), true);

    // set status to false - should fail
    start_prank(ctx.amm_address, dummy_addr.try_into().unwrap());
    dsps.amm.set_trading_halt(false);
}

#[test]
#[should_panic(expected: ('Trading halted',))]
fn test_set_trading_halt_trade_failing() {
    let (ctx, dsps) = deploy_setup();
    let dummy_addr: felt252 = 0x0178227144f45dd9e704dab545018813d17383e4cd1181a94fb7086df8cc50e1;

    // Set permission to true
    start_prank(ctx.amm_address, ctx.admin_address);
    dsps.amm.set_trading_halt_permission(dummy_addr.try_into().unwrap(), true);

    // set status to true
    start_prank(ctx.amm_address, dummy_addr.try_into().unwrap());
    dsps.amm.set_trading_halt(true);

    // Do some trade - should fail   
    start_prank(ctx.amm_address, ctx.admin_address);

    let five_tokens: u256 = 5000000000000000000; // with 18 decimals
    let five_k_tokens: u256 = 5000000000; // with 6 decimals
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

    let _ = dsps
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

