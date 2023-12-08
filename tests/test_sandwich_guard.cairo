use carmine_protocol::testing::setup::deploy_setup;
use carmine_protocol::amm_core::oracles::pragma::Pragma::PRAGMA_ORACLE_ADDRESS;
use carmine_protocol::amm_core::oracles::pragma::PragmaUtils::{
    PragmaPricesResponse, Checkpoint, AggregationMode
};
use snforge_std::{
    declare, ContractClassTrait, start_prank, stop_prank, start_warp, stop_warp, ContractClass,
    start_mock_call, stop_mock_call, start_roll
};
use carmine_protocol::amm_core::helpers::{FixedHelpersTrait, toU256_balance};
use carmine_protocol::amm_core::amm::AMM;
use carmine_protocol::amm_interface::{IAMMDispatcher, IAMMDispatcherTrait};
use carmine_protocol::testing::setup::{Ctx, Dispatchers};

#[test]
#[should_panic]
fn test_sandwich_guard_failing() {
    let (ctx, dsps) = deploy_setup();
    let five_tokens: u256 = 5000000000000000000; // with 18 decimals
    let five_k_tokens: u256 = 5000000000; // with 6 decimals

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

    let one_eth: u256 = 1000000000000000000;
    let one_k_usdc: u256 = 1000000000;

    start_roll(ctx.amm_address, 1000);
    dsps.amm.deposit_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, one_eth);

    dsps.amm.withdraw_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, one_eth);
}

// Should pass
#[test]
fn test_sandwich_guard() {
    let (ctx, dsps) = deploy_setup();
    let five_tokens: u256 = 5000000000000000000; // with 18 decimals
    let five_k_tokens: u256 = 5000000000; // with 6 decimals

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

    let one_eth: u256 = 1000000000000000000;
    let one_k_usdc: u256 = 1000000000;

    start_roll(ctx.amm_address, 1000);
    dsps
        .amm
        .deposit_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, // Call
         one_eth);

    start_roll(ctx.amm_address, 1001);
    dsps
        .amm
        .withdraw_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, // Call
         one_eth);
}

