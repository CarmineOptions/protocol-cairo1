use carmine_protocol::testing::setup::deploy_setup;
use snforge_std::{ContractClass, ContractClassTrait, declare, start_mock_call, start_prank, stop_prank};
use carmine_protocol::amm_core::oracles::pragma::Pragma::PRAGMA_ORACLE_ADDRESS;
use carmine_protocol::amm_core::oracles::pragma::PragmaUtils::{PragmaPricesResponse, Checkpoint, AggregationMode};
use cubit::f128::types::{Fixed, FixedTrait};
use carmine_protocol::ilhedge::contract::{IILHedgeDispatcher, IILHedgeDispatcherTrait};
use carmine_protocol::testing::setup::{Ctx, Dispatchers};

#[test]
fn test_ilhedge() {
    let (ctx, dsps) = deploy_setup();

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

    let ilhedge_contract = declare('ILHedge');

    let mut ilhedge_constructor_data: Array<felt252> = ArrayTrait::new();
    ilhedge_constructor_data.append(ctx.amm_address.into());

    let ilhedge_address = ilhedge_contract.deploy(@ilhedge_constructor_data).unwrap();
    assert(ilhedge_address.into() != 0, 'ilhedge addr 0');
    let ilhedge = IILHedgeDispatcher { contract_address: ilhedge_address };
    let expiry = 1000000000 + 60 * 60 * 24; // current time plus 24 hours, taken from setup
    let (pricecalls, priceputs) = ilhedge.price_hedge(10000000000000, ctx.usdc_address, ctx.eth_address, expiry);
    assert(pricecalls == 69, 'pricecalls wut');
    assert(priceputs == 42, 'priceputs wut');
}

fn add_needed_options(ctx: Ctx, dsps: Dispatchers) {
    let FIXED_BASE = 18446744073709551616; // 2**64
    let CALL = 0;
    let PUT = 1;
    add_option_to_amm(ctx, dsps, strike, 1700 * FIXED_BASE, CALL);
    add_option_to_amm(ctx, dsps, strike, 1800 * FIXED_BASE, CALL);
    add_option_to_amm(ctx, dsps, strike, 1900 * FIXED_BASE, CALL);
    add_option_to_amm(ctx, dsps, strike, 2000 * FIXED_BASE, CALL);
    add_option_to_amm(ctx, dsps, strike, 1300 * FIXED_BASE, PUT);
    add_option_to_amm(ctx, dsps, strike, 1400 * FIXED_BASE, PUT);
    add_option_to_amm(ctx, dsps, strike, 1500 * FIXED_BASE, PUT);
    add_option_to_amm(ctx, dsps, strike, 1600 * FIXED_BASE, PUT);
}

fn add_option_to_amm(ctx: Ctx, dsps: Dispatchers, strike: u128, option_type: u8) {
    start_prank(ctx.amm_address, ctx.admin_address);
    let FIXED_BASE = 18446744073709551616; // 2**64
    let expiry: u64 = 1000000000 + 60 * 60 * 24; // current time plus 24 hours
    let LONG = 0;
    let SHORT = 1;
    let hundred = FixedTrait::from_unscaled_felt(100);

    let option_token_contract = declare('OptionToken');

    let mut long_constructor_data: Array<felt252> = ArrayTrait::new();
    long_constructor_data.append('OptLong');
    long_constructor_data.append('OL');
    long_constructor_data.append(ctx.amm_address.into());
    long_constructor_data.append(ctx.usdc_address.into());
    long_constructor_data.append(ctx.eth_address.into());
    long_constructor_data.append(option_type.into());
    long_constructor_data.append(strike.into());
    long_constructor_data.append(expiry.into());
    long_constructor_data.append(LONG);

    let lpt_addr = if (option_type == 0) {ctx.call_lpt_address}else{ctx.call_lpt_address};
    let long_option_address = option_token_contract.deploy(@long_constructor_data).unwrap();
    disp
    .amm
    .add_option(
        LONG.try_into().unwrap(),
        expiry,
        strike,
        ctx.usdc_address,
        ctx.eth_address,
        option_type.try_into().unwrap(),
        lpt_addr,
        long_option_address,
        hundred
    );

    let mut short_constructor_data: Array<felt252> = ArrayTrait::new();
    short_constructor_data.append('OptShort');
    short_constructor_data.append('OS');
    short_constructor_data.append(ctx.amm_address.into());
    short_constructor_data.append(ctx.usdc_address.into());
    short_constructor_data.append(ctx.eth_address.into());
    short_constructor_data.append(option_type.into());
    short_constructor_data.append(strike.into());
    short_constructor_data.append(expiry.into());
    short_constructor_data.append(SHORT);

    let short_option_address = option_token_contract.deploy(@short_constructor_data).unwrap();
    disp
    .amm
    .add_option(
        SHORT.try_into().unwrap(),
        expiry,
        strike,
        ctx.usdc_address,
        ctx.eth_address,
        option_type.try_into().unwrap(),
        lpt_addr,
        short_option_address,
        hundred
    );

    stop_prank(ctx.amm_address);
}