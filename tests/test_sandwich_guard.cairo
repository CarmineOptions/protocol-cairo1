use debug::PrintTrait;

use carmine_protocol::testing::setup::deploy_setup;
use carmine_protocol::tokens::lptoken::{LPToken, ILPTokenDispatcher, ILPTokenDispatcherTrait};
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


const ONE_ETH: u256 = 1000000000000000000;
const HALF_ETH: u256 = 500000000000000000;
const ONE_K_USDC: u256 = 1000000000;


fn sandwich_setup() -> (Ctx, Dispatchers) {
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

    (ctx, dsps)
}

//////////////////////////////////////////////////////////////////////
// TXs with mints first
//////////////////////////////////////////////////////////////////////

#[test]
#[should_panic(expected: ('LPT: too many actions',))]
fn test_sandwich_guard_mint_mint_failing() {
    let (ctx, dsps) = sandwich_setup();

    start_roll(ctx.call_lpt_address, 1000);
    dsps.amm.deposit_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, ONE_ETH);

    // Deposit again in the same block - should fail
    dsps.amm.deposit_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, ONE_ETH);
}

#[test]
#[should_panic(expected: ('LPT: too many actions',))]
fn test_sandwich_guard_mint_burn_failing() {
    let (ctx, dsps) = sandwich_setup();

    start_roll(ctx.call_lpt_address, 1000);
    dsps.amm.deposit_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, ONE_ETH);

    // Withdraw in the same block - should fail
    dsps.amm.withdraw_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, ONE_ETH);
}

#[test]
#[should_panic(expected: ('LPT: too many actions',))]
fn test_sandwich_guard_mint_transfer_failing() {
    let (ctx, dsps) = sandwich_setup();

    start_roll(ctx.call_lpt_address, 1000);
    dsps.amm.deposit_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, ONE_ETH);

    let dummy_addr: felt252 = 0x0178227144f45dd9e704dab545018813d17383e4cd1181a94fb7086df8cc50e1;

    // Transfer in the same block - should fail
    start_prank(ctx.call_lpt_address, ctx.admin_address);
    dsps.lptc.transfer(dummy_addr.try_into().unwrap(), 1);
}

#[test]
#[should_panic(expected: ('LPT: too many actions',))]
fn test_sandwich_guard_mint_transferFrom_failing() {
    let (ctx, dsps) = sandwich_setup();

    start_roll(ctx.call_lpt_address, 1000);
    dsps.amm.deposit_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, ONE_ETH);

    let dummy_addr: felt252 = 0x0178227144f45dd9e704dab545018813d17383e4cd1181a94fb7086df8cc50e1;

    // Aprove dummy address for spending 
    start_prank(ctx.call_lpt_address, ctx.amm_address);
    dsps.lptc.approve(dummy_addr.try_into().unwrap(), 1);

    // Call transfeFrom in the same block - should fail
    start_prank(ctx.call_lpt_address, dummy_addr.try_into().unwrap());
    dsps.lptc.transferFrom(ctx.admin_address, dummy_addr.try_into().unwrap(), 1);
}


#[test]
fn test_sandwich_guard_mint_mint() {
    let (ctx, dsps) = sandwich_setup();

    start_roll(ctx.call_lpt_address, 1000);
    dsps.amm.deposit_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, ONE_ETH);

    // Deposit again in the next block - should not fail
    start_roll(ctx.call_lpt_address, 1001);
    dsps.amm.deposit_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, ONE_ETH);
}

#[test]
fn test_sandwich_guard_mint_burn() {
    let (ctx, dsps) = sandwich_setup();

    start_roll(ctx.call_lpt_address, 1000);
    dsps.amm.deposit_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, ONE_ETH);

    // Withdraw in the next block - should not fail
    start_roll(ctx.call_lpt_address, 1001);
    dsps.amm.withdraw_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, ONE_ETH);
}

#[test]
fn test_sandwich_guard_mint_transfer() {
    let (ctx, dsps) = sandwich_setup();

    start_roll(ctx.call_lpt_address, 1000);
    dsps.amm.deposit_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, ONE_ETH);

    let dummy_addr: felt252 =
        0x0178227144f45dd9e704dab545018813d17383e4cd1181a94fb7086df8cc50e1; // for dummy assert admin

    // Transfer in the next block - should not fail
    start_roll(ctx.call_lpt_address, 1001);
    start_prank(ctx.call_lpt_address, ctx.admin_address);
    dsps.lptc.transfer(dummy_addr.try_into().unwrap(), 1);
}

#[test]
fn test_sandwich_guard_mint_transferFrom() {
    let (ctx, dsps) = sandwich_setup();

    start_roll(ctx.call_lpt_address, 1000);
    dsps.amm.deposit_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, ONE_ETH);

    let dummy_addr: felt252 = 0x0178227144f45dd9e704dab545018813d17383e4cd1181a94fb7086df8cc50e1;

    // Aprove dummy address for spending 
    start_prank(ctx.call_lpt_address, ctx.admin_address);
    dsps.lptc.approve(dummy_addr.try_into().unwrap(), 1);

    // Call transfeFrom in the next block - should not fail
    start_roll(ctx.call_lpt_address, 1001);
    start_prank(ctx.call_lpt_address, dummy_addr.try_into().unwrap());
    dsps.lptc.transferFrom(ctx.admin_address, dummy_addr.try_into().unwrap(), 1);
}


//////////////////////////////////////////////////////////////////////
// TXs with burns first
//////////////////////////////////////////////////////////////////////

#[test]
#[should_panic(expected: ('LPT: too many actions',))]
fn test_sandwich_guard_burn_mint_failing() {
    let (ctx, dsps) = sandwich_setup();

    start_roll(ctx.call_lpt_address, 1000);
    dsps.amm.withdraw_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, ONE_ETH);

    // Deposit again in the same block - should fail
    dsps.amm.deposit_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, ONE_ETH);
}

#[test]
#[should_panic(expected: ('LPT: too many actions',))]
fn test_sandwich_guard_burn_burn_failing() {
    let (ctx, dsps) = sandwich_setup();

    start_roll(ctx.call_lpt_address, 1000);
    dsps.amm.withdraw_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, HALF_ETH);

    // Withdraw in the same block - should fail
    dsps.amm.withdraw_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, HALF_ETH);
}

#[test]
#[should_panic(expected: ('LPT: too many actions',))]
fn test_sandwich_guard_burn_transfer_failing() {
    let (ctx, dsps) = sandwich_setup();

    start_roll(ctx.call_lpt_address, 1000);
    dsps.amm.withdraw_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, ONE_ETH);

    let dummy_addr: felt252 =
        0x0178227144f45dd9e704dab545018813d17383e4cd1181a94fb7086df8cc50e1; // for dummy assert admin

    // Transfer in the same block - should fail
    start_prank(ctx.call_lpt_address, ctx.admin_address);
    dsps.lptc.transfer(dummy_addr.try_into().unwrap(), 1);
}

#[test]
#[should_panic(expected: ('LPT: too many actions',))]
fn test_sandwich_guard_burn_transferFrom_failing() {
    let (ctx, dsps) = sandwich_setup();

    start_roll(ctx.call_lpt_address, 1000);
    dsps.amm.withdraw_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, ONE_ETH);

    let dummy_addr: felt252 = 0x0178227144f45dd9e704dab545018813d17383e4cd1181a94fb7086df8cc50e1;

    // Aprove dummy address for spending 
    start_prank(ctx.call_lpt_address, ctx.amm_address);
    dsps.lptc.approve(dummy_addr.try_into().unwrap(), 1);

    // Call transfeFrom in the same block - should fail
    start_prank(ctx.call_lpt_address, dummy_addr.try_into().unwrap());
    dsps.lptc.transferFrom(ctx.admin_address, dummy_addr.try_into().unwrap(), 1);
}


#[test]
fn test_sandwich_guard_burn_mint() {
    let (ctx, dsps) = sandwich_setup();

    start_roll(ctx.call_lpt_address, 1000);
    dsps.amm.withdraw_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, ONE_ETH);

    // Deposit again in the next block - should not fail
    start_roll(ctx.call_lpt_address, 1001);
    dsps.amm.deposit_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, ONE_ETH);
}

#[test]
fn test_sandwich_guard_burn_burn() {
    let (ctx, dsps) = sandwich_setup();

    start_roll(ctx.call_lpt_address, 1000);
    dsps.amm.withdraw_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, HALF_ETH);

    // Withdraw in the next block - should not fail
    start_roll(ctx.call_lpt_address, 1001);
    dsps.amm.withdraw_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, HALF_ETH);
}

#[test]
fn test_sandwich_guard_burn_transfer() {
    let (ctx, dsps) = sandwich_setup();

    start_roll(ctx.call_lpt_address, 1000);
    dsps.amm.withdraw_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, ONE_ETH);

    let dummy_addr: felt252 =
        0x0178227144f45dd9e704dab545018813d17383e4cd1181a94fb7086df8cc50e1; // for dummy assert admin

    // Transfer in the next block - should not fail
    start_roll(ctx.call_lpt_address, 1001);
    start_prank(ctx.call_lpt_address, ctx.admin_address);
    dsps.lptc.transfer(dummy_addr.try_into().unwrap(), 1);
}

#[test]
fn test_sandwich_guard_burn_transferFrom() {
    let (ctx, dsps) = sandwich_setup();

    start_roll(ctx.call_lpt_address, 1000);
    dsps.amm.withdraw_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, ONE_ETH);

    let dummy_addr: felt252 = 0x0178227144f45dd9e704dab545018813d17383e4cd1181a94fb7086df8cc50e1;

    // Approve dummy addr for spending
    start_prank(ctx.call_lpt_address, ctx.admin_address);
    dsps.lptc.approve(dummy_addr.try_into().unwrap(), 1);

    // Call transfeFrom in the next block - should not fail
    start_roll(ctx.call_lpt_address, 1001);
    start_prank(ctx.call_lpt_address, dummy_addr.try_into().unwrap());
    dsps.lptc.transferFrom(ctx.admin_address, dummy_addr.try_into().unwrap(), 1);
}

//////////////////////////////////////////////////////////////////////
// TXs with transfers first
//////////////////////////////////////////////////////////////////////

#[test]
fn test_sandwich_guard_transfer_mint_same_block() {
    let (ctx, dsps) = sandwich_setup();
    let dummy_addr: felt252 =
        0x0178227144f45dd9e704dab545018813d17383e4cd1181a94fb7086df8cc50e1; // for dummy assert admin

    start_roll(ctx.call_lpt_address, 1000);
    start_prank(ctx.call_lpt_address, ctx.admin_address);
    dsps.lptc.transfer(dummy_addr.try_into().unwrap(), 1);
    stop_prank(ctx.call_lpt_address);

    // Burn in the same block - should not fail
    start_prank(ctx.amm_address, ctx.admin_address);
    dsps.amm.deposit_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, ONE_ETH);
}

#[test]
fn test_sandwich_guard_transfer_burn_same_block() {
    let (ctx, dsps) = sandwich_setup();
    let dummy_addr: felt252 =
        0x0178227144f45dd9e704dab545018813d17383e4cd1181a94fb7086df8cc50e1; // for dummy assert admin

    start_roll(ctx.call_lpt_address, 1000);
    start_prank(ctx.call_lpt_address, ctx.admin_address);
    dsps.lptc.transfer(dummy_addr.try_into().unwrap(), 1);
    stop_prank(ctx.call_lpt_address);

    // Withdraw in the same block - should not fail
    dsps.amm.withdraw_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, HALF_ETH);
}

#[test]
fn test_sandwich_guard_transfer_transfer_same_block() {
    let (ctx, dsps) = sandwich_setup();
    let dummy_addr: felt252 =
        0x0178227144f45dd9e704dab545018813d17383e4cd1181a94fb7086df8cc50e1; // for dummy assert admin

    start_roll(ctx.call_lpt_address, 1000);
    start_prank(ctx.call_lpt_address, ctx.admin_address);
    dsps.lptc.transfer(dummy_addr.try_into().unwrap(), 1);
    stop_prank(ctx.call_lpt_address);

    // Transfer in the same block - should not fail
    start_prank(ctx.call_lpt_address, ctx.admin_address);
    dsps.lptc.transfer(dummy_addr.try_into().unwrap(), 1);
}

#[test]
fn test_sandwich_guard_transfer_transferFrom_same_block() {
    let (ctx, dsps) = sandwich_setup();
    let dummy_addr: felt252 =
        0x0178227144f45dd9e704dab545018813d17383e4cd1181a94fb7086df8cc50e1; // for dummy assert admin

    start_roll(ctx.call_lpt_address, 1000);
    start_prank(ctx.call_lpt_address, ctx.admin_address);
    dsps.lptc.transfer(dummy_addr.try_into().unwrap(), 1);
    stop_prank(ctx.call_lpt_address);

    // Aprove dummy address for spending 
    start_prank(ctx.call_lpt_address, ctx.admin_address);
    dsps.lptc.approve(dummy_addr.try_into().unwrap(), 1);

    // Transfer in the same block - should not fail
    start_prank(ctx.call_lpt_address, dummy_addr.try_into().unwrap());
    dsps.lptc.transferFrom(ctx.admin_address, dummy_addr.try_into().unwrap(), 1);
}

#[test]
fn test_sandwich_guard_transfer_mint_next_block() {
    let (ctx, dsps) = sandwich_setup();
    let dummy_addr: felt252 =
        0x0178227144f45dd9e704dab545018813d17383e4cd1181a94fb7086df8cc50e1; // for dummy assert admin

    start_roll(ctx.call_lpt_address, 1000);
    start_prank(ctx.call_lpt_address, ctx.admin_address);
    dsps.lptc.transfer(dummy_addr.try_into().unwrap(), 1);
    stop_prank(ctx.call_lpt_address);

    // Burn in the next block - should not fail
    start_roll(ctx.call_lpt_address, 1001);
    start_prank(ctx.amm_address, ctx.admin_address);
    dsps.amm.deposit_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, ONE_ETH);
}

#[test]
fn test_sandwich_guard_transfer_burn_next_block() {
    let (ctx, dsps) = sandwich_setup();
    let dummy_addr: felt252 =
        0x0178227144f45dd9e704dab545018813d17383e4cd1181a94fb7086df8cc50e1; // for dummy assert admin

    start_roll(ctx.call_lpt_address, 1000);
    start_prank(ctx.call_lpt_address, ctx.admin_address);
    dsps.lptc.transfer(dummy_addr.try_into().unwrap(), 1);
    stop_prank(ctx.call_lpt_address);

    // Withdraw in the next block - should not fail
    start_roll(ctx.call_lpt_address, 1001);
    dsps.amm.withdraw_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, HALF_ETH);
}

#[test]
fn test_sandwich_guard_transfer_transfer_next_block() {
    let (ctx, dsps) = sandwich_setup();
    let dummy_addr: felt252 =
        0x0178227144f45dd9e704dab545018813d17383e4cd1181a94fb7086df8cc50e1; // for dummy assert admin

    start_roll(ctx.call_lpt_address, 1000);
    start_prank(ctx.call_lpt_address, ctx.admin_address);
    dsps.lptc.transfer(dummy_addr.try_into().unwrap(), 1);
    stop_prank(ctx.call_lpt_address);

    // Transfer in the next block - should not fail
    start_roll(ctx.call_lpt_address, 1001);
    start_prank(ctx.call_lpt_address, ctx.admin_address);
    dsps.lptc.transfer(dummy_addr.try_into().unwrap(), 1);
}

#[test]
fn test_sandwich_guard_transfer_transferFrom_next_block() {
    let (ctx, dsps) = sandwich_setup();
    let dummy_addr: felt252 =
        0x0178227144f45dd9e704dab545018813d17383e4cd1181a94fb7086df8cc50e1; // for dummy assert admin

    start_roll(ctx.call_lpt_address, 1000);
    start_prank(ctx.call_lpt_address, ctx.admin_address);
    dsps.lptc.transfer(dummy_addr.try_into().unwrap(), 1);
    stop_prank(ctx.call_lpt_address);

    // Aprove dummy address for spending 
    start_prank(ctx.call_lpt_address, ctx.admin_address);
    dsps.lptc.approve(dummy_addr.try_into().unwrap(), 1);

    // Transfer in the same block - should not fail
    start_roll(ctx.call_lpt_address, 1001);
    start_prank(ctx.call_lpt_address, dummy_addr.try_into().unwrap());
    dsps.lptc.transferFrom(ctx.admin_address, dummy_addr.try_into().unwrap(), 1);
}
