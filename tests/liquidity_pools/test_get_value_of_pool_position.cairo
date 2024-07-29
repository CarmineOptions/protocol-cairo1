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

#[test]
fn test_get_value_of_pool_position() {
    let (ctx, dsps) = deploy_setup();

    // Set up initial state
    start_prank(ctx.amm_address, ctx.admin_address);

    // Mock the Pragma oracle call
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
    let initial_deposit: u256 = 5000000000000000000; // 5 ETH
    initial_deposit.print();
    dsps.amm.deposit_liquidity(
        ctx.eth_address,
        ctx.usdc_address,
        ctx.eth_address,
        0, // Call option
        initial_deposit
    );

    // Get the initial pool value (this should use the mocked oracle price)
    let initial_pool_value = dsps.amm.get_value_of_pool_position(ctx.call_lpt_address);
    initial_pool_value.print();
    // Stop the mock call to the oracle
    stop_mock_call(PRAGMA_ORACLE_ADDRESS.try_into().unwrap(), 'get_data');

    // Warp time forward to ensure we're past any potential cache expiration
    // start_warp(ctx.amm_address, 1000000000 + 60 * 60); // 1 hour later

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
    assert(
        initial_pool_value == new_pool_value,
        'Prices differ.'
    );

    // Calculate the expected pool value (5 ETH * $1400)
    // let expected_value = FixedTrait::from_felt(7000000000000000000000); // 7000 USDC

    // Assert that both values match the expected value
    // assert(initial_pool_value == expected_value, 'Initial pool value incorrect');
    // assert(new_pool_value == expected_value, 'Cached pool value incorrect');
}
