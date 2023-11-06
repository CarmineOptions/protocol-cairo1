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
    start_mock_call, stop_mock_call
};
use carmine_protocol::amm_core::helpers::{FixedHelpersTrait, toU256_balance};
use carmine_protocol::amm_core::amm::{AMM, IAMMDispatcher, IAMMDispatcherTrait};
use carmine_protocol::testing::setup::{Ctx, Dispatchers};

use carmine_protocol::tokens::my_token::{MyToken, IMyTokenDispatcher, IMyTokenDispatcherTrait};

// Todo: tests with price above strike

#[test]
fn test_trade_close_long() {
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

    // Open some trades
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

    let _ = dsps
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

    let long_call_premia = dsps
        .amm
        .trade_close(
            0, // Call
            ctx.strike_price,
            ctx.expiry,
            0, // Long
            one_int,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_felt(1), // Disable this check
            99999999999 // Disable this check
        );

    let long_put_premia = dsps
        .amm
        .trade_close(
            1, // Put
            ctx.strike_price,
            ctx.expiry,
            0, // Long
            one_int,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_felt(1), // Disable this check
            99999999999 // Disable this check
        );

    assert(long_call_premia == FixedTrait::from_felt(62134282537632086), 'Long Call premia wrong');
    assert(
        long_put_premia == FixedTrait::from_felt(1945765480687755943700), 'Long put premia wrong'
    );

    let stats_1 = StatsTrait::new(ctx, dsps);

    assert(stats_1.bal_lpt_c == five_tokens, 'Call lpt bal wrong');
    assert(stats_1.bal_lpt_p == five_k_tokens, 'Put lpt bal wrong');

    assert(stats_1.bal_eth == 4999797901627660614, 'Eth1 bal wrong');
    assert(stats_1.bal_usdc == 4993671191, 'Usdc1 bal wrong');

    assert(stats_1.bal_opt_lc == 0, 'Opt1 lc bal wrong');
    assert(stats_1.bal_opt_sc == 0, 'Opt1 sc bal wrong');
    assert(stats_1.bal_opt_lp == 0, 'Opt1 lp bal wrong');
    assert(stats_1.bal_opt_sp == 0, 'Opt1 sp bal wrong');

    assert(stats_1.lpool_balance_c == 5000202098372339386, 'Call1 lpool bal wrong');
    assert(stats_1.lpool_balance_p == 5006328809, 'Put1 lpool bal wrong');

    assert(stats_1.bal_eth + stats_1.lpool_balance_c == 2 * five_tokens, 'random eth appeared');
    assert(stats_1.bal_usdc + stats_1.lpool_balance_p == 2 * five_k_tokens, 'random usdc appeared');

    assert(stats_1.unlocked_capital_c == 5000202098372339386, 'Call1 unlocked wrong');
    assert(stats_1.unlocked_capital_p == 5006328809, 'Put1 unlocked wrong');

    assert(
        stats_1.bal_eth + stats_1.unlocked_capital_c + stats_1.locked_capital_c == 2 * five_tokens,
        'random eth appeared'
    );
    assert(
        stats_1.bal_usdc
            + stats_1.unlocked_capital_p
            + stats_1.locked_capital_p == 2 * five_k_tokens,
        'random usdc appeared'
    );

    assert(stats_1.locked_capital_c == 0, 'Call1 locked wrong');
    assert(stats_1.locked_capital_p == 0, 'Put1 locked wrong');

    assert(stats_1.pool_pos_val_c == FixedTrait::ZERO(), 'Call1 pos val wrong');
    assert(stats_1.pool_pos_val_p == FixedTrait::ZERO(), 'Put1 pos val wrong');

    assert(
        stats_1.volatility_c == FixedTrait::from_felt(1844674407370955161600), 'Call1 vol wrong'
    );
    assert(stats_1.volatility_p == FixedTrait::from_felt(1844674407370955161600), 'Put1 vol wrong');

    assert(stats_1.opt_pos_lc == 0, 'lc1 pos wrong');
    assert(stats_1.opt_pos_sc == 0, 'sc1 pos wrong');
    assert(stats_1.opt_pos_lp == 0, 'lp1 pos wrong');
    assert(stats_1.opt_pos_sp == 0, 'sp1 pos wrong');
}


#[test]
fn test_trade_close_short() {
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

    // First open some trades
    let _ = dsps
        .amm
        .trade_open(
            0, // Call
            ctx.strike_price,
            ctx.expiry,
            1, // Long
            one_int,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_felt(1), // Disable this check
            99999999999 // Disable this check
        );

    let _ = dsps
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

    let short_call_premia = dsps
        .amm
        .trade_close(
            0, // Call
            ctx.strike_price,
            ctx.expiry,
            1, // Long
            one_int,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_unscaled_felt(100_000), // Disable this check
            99999999999 // Disable this check
        );

    let short_put_premia = dsps
        .amm
        .trade_close(
            1, // Put
            ctx.strike_price,
            ctx.expiry,
            1, // short
            one_int,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_unscaled_felt(100_000), // Disable this check
            99999999999 // Disable this check
        );

    assert(short_call_premia == FixedTrait::from_felt(28650672047953412), 'Long Call premia wrong');
    assert(
        short_put_premia == FixedTrait::from_felt(1875771037947335154100), 'Long put premia wrong'
    );

    let stats_1 = StatsTrait::new(ctx, dsps);

    assert(stats_1.bal_lpt_c == five_tokens, 'Call lpt bal wrong');
    assert(stats_1.bal_lpt_p == five_k_tokens, 'Put lpt bal wrong');

    assert(stats_1.bal_opt_lc == 0, 'Opt1 lc bal wrong');
    assert(stats_1.bal_opt_sc == 0, 'Opt1 sc bal wrong');
    assert(stats_1.bal_opt_lp == 0, 'Opt1 lp bal wrong');
    assert(stats_1.bal_opt_sp == 0, 'Opt1 sp bal wrong');

    assert(stats_1.bal_eth == 4999906810637367318, 'Eth1 bal wrong');
    assert(stats_1.bal_usdc == 4993898855, 'Usdc1 bal wrong');

    assert(stats_1.lpool_balance_c == 5000093189362632682, 'Call1 lpool bal wrong');
    assert(stats_1.lpool_balance_p == 5006101145, 'Put1 lpool bal wrong');

    assert(stats_1.bal_eth + stats_1.lpool_balance_c == 2 * five_tokens, 'random eth appeared');
    assert(stats_1.bal_usdc + stats_1.lpool_balance_p == 2 * five_k_tokens, 'random usdc appeared');

    assert(stats_1.unlocked_capital_c == 5000093189362632682, 'Call1 unlocked wrong');
    assert(stats_1.unlocked_capital_p == 5006101145, 'Put1 unlocked wrong');

    assert(stats_1.locked_capital_c == 0, 'Call1 locked wrong');
    assert(stats_1.locked_capital_p == 0, 'Put1 locked wrong');

    assert(stats_1.pool_pos_val_c == FixedTrait::ZERO(), 'Call1 pos val wrong');
    assert(stats_1.pool_pos_val_p == FixedTrait::ZERO(), 'Put1 pos val wrong');

    assert(
        stats_1.volatility_c == FixedTrait::from_felt(1844674407370955161600), 'Call1 vol wrong'
    );
    assert(stats_1.volatility_p == FixedTrait::from_felt(1844674407370955161600), 'Put1 vol wrong');

    assert(stats_1.opt_pos_lc == 0, 'lc1 pos wrong');
    assert(stats_1.opt_pos_sc == 0, 'sc1 pos wrong');
    assert(stats_1.opt_pos_lp == 0, 'lp1 pos wrong');
    assert(stats_1.opt_pos_sp == 0, 'sp1 pos wrong');
}
