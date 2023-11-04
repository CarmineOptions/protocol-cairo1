use carmine_protocol::testing::setup::deploy_setup;
use snforge_std::{ContractClass, ContractClassTrait, declare, start_mock_call, start_prank, stop_prank};
use carmine_protocol::amm_core::oracles::pragma::Pragma::PRAGMA_ORACLE_ADDRESS;
use carmine_protocol::amm_core::oracles::pragma::PragmaUtils::{PragmaPricesResponse, Checkpoint, AggregationMode};
use cubit::f128::types::{Fixed, FixedTrait};
use carmine_protocol::ilhedge::contract::{IILHedgeDispatcher, IILHedgeDispatcherTrait};
use carmine_protocol::testing::setup::{Ctx, Dispatchers};
use carmine_protocol::amm_core::amm::{AMM, IAMMDispatcher, IAMMDispatcherTrait};

use debug::PrintTrait;
#[test]
fn test_ilhedge() {
    let (ctx, dsps) = deploy_setup();
    'hi'.print();
    // set spot price
    start_mock_call(
        PRAGMA_ORACLE_ADDRESS.try_into().unwrap(),
        'get_data',
        PragmaPricesResponse {
            price: 165000000000,  // 1650
            decimals: 8, 
            last_updated_timestamp: 1000000000 + 60 * 60 * 12,
            num_sources_aggregated: 0,
            expiration_timestamp: Option::None(())
        }
    );
    add_needed_options(ctx, dsps);
    'hello'.print();

    let ilhedge_contract = declare('ILHedge');

    let mut ilhedge_constructor_data: Array<felt252> = ArrayTrait::new();
    ilhedge_constructor_data.append(ctx.amm_address.into());

    let ilhedge_address = ilhedge_contract.deploy(@ilhedge_constructor_data).unwrap();
    assert(ilhedge_address.into() != 0, 'ilhedge addr 0');
    let ilhedge = IILHedgeDispatcher { contract_address: ilhedge_address };
    let expiry = 1000000000 + 60 * 60 * 24; // current time plus 24 hours, taken from setup
    let (pricecalls, priceputs) = ilhedge.price_hedge(1000000000000000000, ctx.usdc_address, ctx.eth_address, expiry);
    'pricecalls:'.print();
    pricecalls.print();
    assert(pricecalls == 69, 'pricecalls wut');
    'priceputs:'.print();
    priceputs.print();
    assert(priceputs == 42, 'priceputs wut');
}

fn add_needed_options(ctx: Ctx, dsps: Dispatchers) {
    let CALL = 0;
    let PUT = 1;
    add_option_to_amm(ctx, dsps, 1600, PUT);
    add_option_to_amm(ctx, dsps, 1700, CALL);
    add_option_to_amm(ctx, dsps, 1800, CALL);
    add_option_to_amm(ctx, dsps, 1900, CALL);
    add_option_to_amm(ctx, dsps, 2000, CALL);
    add_option_to_amm(ctx, dsps, 1300, PUT);
    add_option_to_amm(ctx, dsps, 1400, PUT);
    // add_option_to_amm(ctx, dsps, 1500, PUT); // already added
}

fn add_option_to_amm(ctx: Ctx, dsps: Dispatchers, strike: u128, option_type: u8) {
    start_prank(ctx.amm_address, ctx.admin_address);
    let expiry: u64 = 1000000000 + 60 * 60 * 24; // current time plus 24 hours
    let LONG = 0;
    let SHORT = 1;
    let hundred = FixedTrait::from_unscaled_felt(100);
    let strike_fixed = FixedTrait::from_unscaled_felt(strike.into());

    let mut long_constructor_data: Array<felt252> = ArrayTrait::new();
    long_constructor_data.append('OptLong');
    long_constructor_data.append('OL');
    long_constructor_data.append(ctx.amm_address.into());
    long_constructor_data.append(ctx.usdc_address.into());
    long_constructor_data.append(ctx.eth_address.into());
    long_constructor_data.append(option_type.into());
    long_constructor_data.append(strike_fixed.mag.into());
    long_constructor_data.append(expiry.into());
    long_constructor_data.append(LONG);
    let long_option_address = ctx.opt_contract.deploy(@long_constructor_data).unwrap();


    let mut short_constructor_data: Array<felt252> = ArrayTrait::new();
    short_constructor_data.append('OptShort');
    short_constructor_data.append('OS');
    short_constructor_data.append(ctx.amm_address.into());
    short_constructor_data.append(ctx.usdc_address.into());
    short_constructor_data.append(ctx.eth_address.into());
    short_constructor_data.append(option_type.into());
    short_constructor_data.append(strike_fixed.mag.into());
    short_constructor_data.append(expiry.into());
    short_constructor_data.append(SHORT);
    let short_option_address = ctx.opt_contract.deploy(@short_constructor_data).unwrap();


    let lpt_addr = if (option_type == 0) {ctx.call_lpt_address}else{ctx.put_lpt_address};
    dsps
    .amm
    .add_option_both_sides(
        expiry,
        strike_fixed,
        ctx.usdc_address,
        ctx.eth_address,
        option_type,
        lpt_addr,
        long_option_address,
        short_option_address,
        hundred
    );
    stop_prank(ctx.amm_address);
}