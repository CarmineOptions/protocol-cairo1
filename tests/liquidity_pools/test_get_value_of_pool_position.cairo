use carmine_protocol::testing::setup::deploy_setup;
use traits::{Into, TryInto};
use debug::PrintTrait;
use option::OptionTrait;
use carmine_protocol::amm_core::oracles::pragma::Pragma::PRAGMA_ORACLE_ADDRESS;
use carmine_protocol::amm_core::oracles::pragma::PragmaUtils::PragmaPricesResponse;
use cubit::f128::types::fixed::{Fixed, FixedTrait};
use snforge_std::{start_prank, stop_prank, start_warp, stop_warp, start_mock_call, stop_mock_call};
use carmine_protocol::amm_interface::{IAMMDispatcher, IAMMDispatcherTrait};
use carmine_protocol::testing::setup::{Ctx, Dispatchers};

#[test]
fn test_get_value_of_pool_position() {
    let (ctx, dsps) = deploy_setup();

    // Set up initial state
    start_warp(ctx.amm_address, 1000000000);
    start_prank(ctx.amm_address, ctx.admin_address);
    start_mock_call(
        PRAGMA_ORACLE_ADDRESS.try_into().unwrap(),
        'get_data',
        PragmaPricesResponse {
            price: 140000000000, // $1400 with 8 decimals
            decimals: 8,
            last_updated_timestamp: 1000000000,
            num_sources_aggregated: 0,
            expiration_timestamp: Option::None(())
        }
    );

    // Add some liquidity to the pool
    let one_int = 1000000000000000000; // 1*10**18
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
            FixedTrait::from_unscaled_felt(100_000),
            99999999999
        );

    // Get the initial pool value (this should use the mocked oracle price)
    let initial_pool_value = dsps.amm.get_value_of_pool_position(ctx.call_lpt_address);

    // Stop the mock call to the oracle with price $1400
    stop_mock_call(PRAGMA_ORACLE_ADDRESS.try_into().unwrap(), 'get_data');

    // Start pragma mock with new price
    // Expected behavior: price is gonna be obtained from state as block stays the same and new price in pragma would not
    // affect pool value
    start_mock_call(
        PRAGMA_ORACLE_ADDRESS.try_into().unwrap(),
        'get_data',
        PragmaPricesResponse {
            price: 280000000000, // $2800 with 8 decimals
            decimals: 8,
            last_updated_timestamp: 1000000000,
            num_sources_aggregated: 0,
            expiration_timestamp: Option::None(())
        }
    );

    // Get the pool value again (this should use the cached price)
    let new_pool_value = dsps.amm.get_value_of_pool_position(ctx.call_lpt_address);

    // Assert that the values are the same, indicating the use of cached oracle data
    assert(initial_pool_value == new_pool_value, 'Prices differ.');
}
