use starknet::ContractAddress;
use carmine_protocol::amm_core::view::View;
use carmine_protocol::testing::setup::{deploy_setup, _add_expired_option};
use array::ArrayTrait;
use debug::PrintTrait;
use carmine_protocol::amm_core::amm::IAMMDispatcherTrait;
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
fn test_dummy() {
    let (ctx, dsps) = deploy_setup();
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

    let long_put_premia = dsps
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

    start_warp(ctx.amm_address, 1000000000 + 60 * 60 * 24 + 1);
    start_mock_call(
        PRAGMA_ORACLE_ADDRESS.try_into().unwrap(),
        'get_last_checkpoint_before',
        (
            Checkpoint {
                timestamp: 1000000000 + 60 * 60 * 24 - 1,
                value: 140000000000,
                aggregation_mode: AggregationMode::Median(()),
                num_sources_aggregated: 0
            },
            1
        )
    );
    start_mock_call(PRAGMA_ORACLE_ADDRESS.try_into().unwrap(), 'get_decimals', 8);

    // let call_pos = dsps.amm.get_option_position(
    //     ctx.call_lpt_address,
    //     1,
    //     ctx.expiry,
    //     ctx.strike_price
    // );

    // let put_pos = dsps.amm.get_option_position(
    //     ctx.put_lpt_address,
    //     1,
    //     ctx.expiry,
    //     ctx.strike_price
    // );

    // let call_val = dsps.amm.get_value_of_pool_position(
    //     ctx.call_lpt_address
    // );

    // let put_val = dsps.amm.get_value_of_pool_position(
    //     ctx.put_lpt_address
    // );

    let call_val = dsps.amm.get_value_of_pool_expired_position(ctx.call_lpt_address);

    let put_val = dsps.amm.get_value_of_pool_expired_position(ctx.put_lpt_address);
}
