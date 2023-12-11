// Example test

use starknet::ContractAddress;
use traits::{TryInto, Into};
use option::OptionTrait;
use debug::PrintTrait;

use snforge_std::{start_prank, stop_prank, start_warp, stop_warp, start_mock_call, stop_mock_call};
use cubit::f128::types::{Fixed, FixedTrait};

use carmine_protocol::testing::test_utils::{Stats, StatsTrait};
use carmine_protocol::testing::setup::deploy_setup;

use carmine_protocol::amm_interface::IAMMDispatcherTrait;
use carmine_protocol::amm_core::oracles::pragma::Pragma::PRAGMA_ORACLE_ADDRESS;
use carmine_protocol::amm_core::oracles::pragma::PragmaUtils::{
    PragmaPricesResponse, Checkpoint, AggregationMode
};


#[test]
fn test_dummy() {
    // Deploying setup
    // It returns the context with all the needed information (addresses, strike, expiry etc)
    // and Dispatchers (dispatchers for all the contracts deployed in the tests)
    let (ctx, dsps) = deploy_setup();

    // Some token amounts for trading etc
    let five_tokens: u256 = 5000000000000000000; // with 18 decimals
    let five_k_tokens: u256 = 5000000000; // with 6 decimals
    let one_int = 1000000000000000000; // 1*10**18

    // Warping 
    start_warp(ctx.amm_address, 1000000000);

    // Pranking the AMM to call it from user address
    start_prank(ctx.amm_address, ctx.admin_address);

    // Mocking Pragma to return ETH price of 1.4k
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

    // Opening LONG CALL trade using the Dispatchers struct
    // NOTE: You still have to import IAMMDispatcherTrait for it to work
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

    // Opening SHORT CALL trade using the Dispatchers struct
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

    // You can fetch some information about the directly:

    // Fetching AMM long call option position
    let call_pos_long = dsps
        .amm
        .get_option_position(ctx.call_lpt_address, 0, ctx.expiry, ctx.strike_price);

    // Fetching AMM short call option position
    let call_pos_short = dsps
        .amm
        .get_option_position(ctx.call_lpt_address, 1, ctx.expiry, ctx.strike_price);

    // But you can also fetch all the AMM state at once with Stats
    let stats_1 = StatsTrait::new(ctx, dsps);

    // Printing the Stats struct:
    // stats_1.print();

    // It already contains the information about the AMM position in all the options:
    assert(call_pos_long == stats_1.opt_pos_lc, 'This should not fail');
    assert(call_pos_short == stats_1.opt_pos_sc, 'This should not fail');

    // Now let's warp past the expiry and try to settle an option
    start_warp(ctx.amm_address, 1000000000 + 60 * 60 * 24 + 1);

    // AMM calls get_last_checkpoint_before function in Pragma oracle, so we
    // need to mock it ie at price of 1.4k per ETH
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

    // Same goes for get_decimals function
    start_mock_call(PRAGMA_ORACLE_ADDRESS.try_into().unwrap(), 'get_decimals', 8);

    // Expire Call pool
    dsps
        .amm
        .expire_option_token_for_pool(
            ctx.call_lpt_address, 0, // Long
             ctx.strike_price, ctx.expiry
        );
    dsps
        .amm
        .expire_option_token_for_pool(
            ctx.call_lpt_address, 1, // Short
             ctx.strike_price, ctx.expiry
        );

    // Settle trades on user side
    dsps
        .amm
        .trade_settle(
            0, // Call
            ctx.strike_price,
            ctx.expiry,
            0, // Long
            one_int,
            ctx.usdc_address,
            ctx.eth_address,
        );

    dsps
        .amm
        .trade_settle(
            0, // Call
            ctx.strike_price,
            ctx.expiry,
            1, // Short
            one_int,
            ctx.usdc_address,
            ctx.eth_address,
        );

    // Fetch the AMM state again
    let stats_2 = StatsTrait::new(ctx, dsps);

    // Assert some stuff
    assert(stats_2.locked_capital_c == 0, 'Call pool should have no locked');
}
