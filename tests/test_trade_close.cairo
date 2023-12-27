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

use carmine_protocol::tokens::my_token::{MyToken, IMyTokenDispatcher, IMyTokenDispatcherTrait};


// User just open and closes position
// Pool retains none
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

// User opens and closes position
// but pool goes from short position to long during close
#[test]
fn test_trade_close_long_with_pool_position_change() {
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

    // Open some SHORT position so that pool has long position
    let _ = dsps
        .amm
        .trade_open(
            0, // Call
            ctx.strike_price,
            ctx.expiry,
            1, // SHORT
            500000000000000000,
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
            1, // Short
            500000000000000000,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_felt(1), // Disable this check
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

    let stats_1 = StatsTrait::new(ctx, dsps);

    assert(stats_1.bal_lpt_c == five_tokens, 'Call lpt bal wrong');
    assert(stats_1.bal_lpt_p == five_k_tokens, 'Put lpt bal wrong');

    assert(stats_1.bal_opt_lc == 0, 'Opt1 lc bal wrong');
    assert(stats_1.bal_opt_sc == 500000000000000000, 'Opt1 sc bal wrong');
    assert(stats_1.bal_opt_lp == 0, 'Opt1 lp bal wrong');
    assert(stats_1.bal_opt_sp == 500000000000000000, 'Opt1 sp bal wrong');

    assert(stats_1.bal_eth == 4500739469454718428, 'Eth1 bal wrong');
    assert(stats_1.bal_usdc == 4293344127, 'Usdc1 bal wrong');

    assert(stats_1.lpool_balance_c == 4999260530545281572, 'Call1 lpool bal wrong');
    assert(stats_1.lpool_balance_p == 4956655873, 'Put1 lpool bal wrong');

    assert(
        stats_1.bal_eth + stats_1.lpool_balance_c + 500000000000000000 == 2 * five_tokens,
        'random eth appeared 1'
    );
    assert(
        stats_1.bal_usdc + stats_1.lpool_balance_p + 750000000 == 2 * five_k_tokens,
        'random usdc appeared 1'
    );

    assert(
        stats_1.bal_eth
            + stats_1.locked_capital_c
            + stats_1.unlocked_capital_c
            + 500000000000000000 == 2 * five_tokens,
        'random eth appeared 2'
    );
    assert(
        stats_1.bal_usdc
            + stats_1.locked_capital_p
            + stats_1.unlocked_capital_p
            + 750000000 == 2 * five_k_tokens,
        'random usdc appeared 2'
    );

    assert(stats_1.locked_capital_c == 0, 'Call1 locked wrong');
    assert(stats_1.locked_capital_p == 0, 'Put1 locked wrong');

    assert(stats_1.unlocked_capital_c == 4999260530545281572, 'Call1 unlocked wrong');
    assert(stats_1.unlocked_capital_p == 4956655873, 'Put1 unlocked wrong');

    assert(
        stats_1.volatility_c == FixedTrait::from_felt(1660206966633859645500), 'Call1 vol wrong'
    );
    assert(stats_1.volatility_p == FixedTrait::from_felt(1567973246265311887400), 'Put1 vol wrong');

    assert(stats_1.opt_pos_lc == 500000000000000000, 'lc1 pos wrong');
    assert(stats_1.opt_pos_sc == 0, 'sc1 pos wrong');
    assert(stats_1.opt_pos_lp == 500000000000000000, 'lp1 pos wrong');
    assert(stats_1.opt_pos_sp == 0, 'sp1 pos wrong');
}

// User just open and closes position
// Pool retains none
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
            1, // Short
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
            1, // Short
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
            1, // Short
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
            1, // Short
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

// User opens and closes position
// but pool goes from long position to short during close
#[test]
fn test_trade_close_short_with_pool_position_change() {
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
            1, // Short
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
            1, // Short
            one_int,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_felt(1), // Disable this check
            99999999999 // Disable this check
        );

    // Open some LONG position so that pool has short position
    let _ = dsps
        .amm
        .trade_open(
            0, // Call
            ctx.strike_price,
            ctx.expiry,
            0, // Long
            500000000000000000,
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
            0, // Short
            500000000000000000,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_unscaled_felt(100_000), // Disable this check
            99999999999 // Disable this check
        );

    let short_call_premia = dsps
        .amm
        .trade_close(
            0, // Call
            ctx.strike_price,
            ctx.expiry,
            1, // Short
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
            1, // Short
            one_int,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_unscaled_felt(100_000), // Disable this check
            99999999999 // Disable this check
        );

    let stats_1 = StatsTrait::new(ctx, dsps);

    assert(stats_1.bal_lpt_c == five_tokens, 'Call lpt bal wrong');
    assert(stats_1.bal_lpt_p == five_k_tokens, 'Put lpt bal wrong');

    assert(stats_1.bal_opt_lc == 500000000000000000, 'Opt1 lc bal wrong');
    assert(stats_1.bal_opt_sc == 0, 'Opt1 sc bal wrong');
    assert(stats_1.bal_opt_lp == 500000000000000000, 'Opt1 lp bal wrong');
    assert(stats_1.bal_opt_sp == 0, 'Opt1 sp bal wrong');

    assert(stats_1.bal_eth == 4998433196311350232, 'Eth1 bal wrong');
    assert(stats_1.bal_usdc == 4940147218, 'Usdc1 bal wrong');

    assert(stats_1.lpool_balance_c == 5001566803688649768, 'Call1 lpool bal wrong');
    assert(stats_1.lpool_balance_p == 5059852782, 'Put1 lpool bal wrong');

    assert(stats_1.bal_eth + stats_1.lpool_balance_c == 2 * five_tokens, 'random eth appeared 1');
    assert(
        stats_1.bal_usdc + stats_1.lpool_balance_p == 2 * five_k_tokens, 'random usdc appeared 1'
    );

    assert(stats_1.locked_capital_c == 500000000000000000, 'Call1 locked wrong');
    assert(stats_1.locked_capital_p == 750000000, 'Put1 locked wrong');

    assert(
        stats_1.bal_eth + stats_1.locked_capital_c + stats_1.unlocked_capital_c == 2 * five_tokens,
        'random eth appeared 2'
    );
    assert(
        stats_1.bal_usdc
            + stats_1.locked_capital_p
            + stats_1.unlocked_capital_p == 2 * five_k_tokens,
        'random usdc appeared 2'
    );

    assert(stats_1.unlocked_capital_c == 4501566803688649768, 'Call1 unlocked wrong');
    assert(stats_1.unlocked_capital_p == 4309852782, 'Put1 unlocked wrong');

    assert(
        stats_1.volatility_c == FixedTrait::from_felt(2029141848108050677700), 'Call1 vol wrong'
    );
    assert(stats_1.volatility_p == FixedTrait::from_felt(2121375568476598435800), 'Put1 vol wrong');

    assert(stats_1.opt_pos_lc == 0, 'lc1 pos wrong');
    assert(stats_1.opt_pos_sc == 500000000000000000, 'sc1 pos wrong');
    assert(stats_1.opt_pos_lp == 0, 'lp1 pos wrong');
    assert(stats_1.opt_pos_sp == 500000000000000000, 'sp1 pos wrong');
}


// User opens and closes but pool retains long position
#[test]
fn test_trade_close_long_with_pool_long_position() {
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

    // Open some SHORT position so that pool has short position > long
    let _ = dsps
        .amm
        .trade_open(
            0, // Call
            ctx.strike_price,
            ctx.expiry,
            1, // SHORT
            one_int * 2,
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
            1, // Short
            one_int * 2,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_felt(1), // Disable this check
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

    let stats_1 = StatsTrait::new(ctx, dsps);

    assert(stats_1.bal_lpt_c == five_tokens, 'Call lpt bal wrong');
    assert(stats_1.bal_lpt_p == five_k_tokens, 'Put lpt bal wrong');

    assert(stats_1.bal_opt_lc == 0, 'Opt1 lc bal wrong');
    assert(stats_1.bal_opt_sc == 2000000000000000000, 'Opt1 sc bal wrong');
    assert(stats_1.bal_opt_lp == 0, 'Opt1 lp bal wrong');
    assert(stats_1.bal_opt_sp == 2000000000000000000, 'Opt1 sp bal wrong');

    assert(stats_1.bal_eth == 3001576330697504434, 'Eth1 bal wrong');
    assert(stats_1.bal_usdc == 2188935187, 'Usdc1 bal wrong');

    assert(stats_1.lpool_balance_c == 4998423669302495566, 'Call1 lpool bal wrong');
    assert(stats_1.lpool_balance_p == 4811064813, 'Put1 lpool bal wrong');

    assert(
        stats_1.bal_eth + stats_1.lpool_balance_c + 2000000000000000000 == 2 * five_tokens,
        'random eth appeared 1'
    );
    assert(
        stats_1.bal_usdc + stats_1.lpool_balance_p + 3000000000 == 2 * five_k_tokens,
        'random usdc appeared 1'
    );

    assert(
        stats_1.bal_eth
            + stats_1.locked_capital_c
            + stats_1.unlocked_capital_c
            + 2000000000000000000 == 2 * five_tokens,
        'random eth appeared 2'
    );
    assert(
        stats_1.bal_usdc
            + stats_1.locked_capital_p
            + stats_1.unlocked_capital_p
            + 3000000000 == 2 * five_k_tokens,
        'random usdc appeared 2'
    );

    assert(stats_1.locked_capital_c == 0, 'Call1 locked wrong');
    assert(stats_1.locked_capital_p == 0, 'Put1 locked wrong');

    assert(stats_1.unlocked_capital_c == 4998423669302495566, 'Call1 unlocked wrong');
    assert(stats_1.unlocked_capital_p == 4811064813, 'Put1 unlocked wrong');

    assert(
        stats_1.volatility_c == FixedTrait::from_felt(1106804644422573097000), 'Call1 vol wrong'
    );
    assert(stats_1.volatility_p == FixedTrait::from_felt(737869762948382064700), 'Put1 vol wrong');

    assert(stats_1.opt_pos_lc == 2000000000000000000, 'lc1 pos wrong');
    assert(stats_1.opt_pos_sc == 0, 'sc1 pos wrong');
    assert(stats_1.opt_pos_lp == 2000000000000000000, 'lp1 pos wrong');
    assert(stats_1.opt_pos_sp == 0, 'sp1 pos wrong');
}

// User opens and closes but pool retains short position
#[test]
fn test_trade_close_long_with_pool_short_position() {
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

    // Open more LONG position so that pool stays in short
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

    let stats_1 = StatsTrait::new(ctx, dsps);

    assert(stats_1.bal_lpt_c == five_tokens, 'Call lpt bal wrong');
    assert(stats_1.bal_lpt_p == five_k_tokens, 'Put lpt bal wrong');

    assert(stats_1.bal_opt_lc == 1000000000000000000, 'Opt1 lc bal wrong');
    assert(stats_1.bal_opt_sc == 0, 'Opt1 sc bal wrong');
    assert(stats_1.bal_opt_lp == 1000000000000000000, 'Opt1 lp bal wrong');
    assert(stats_1.bal_opt_sp == 0, 'Opt1 sp bal wrong');

    assert(stats_1.bal_eth == 4996186544893224317, 'Eth1 bal wrong');
    assert(stats_1.bal_usdc == 4884701533, 'Usdc1 bal wrong');

    assert(stats_1.lpool_balance_c == 5003813455106775683, 'Call1 lpool bal wrong');
    assert(stats_1.lpool_balance_p == 5115298467, 'Put1 lpool bal wrong');

    assert(stats_1.bal_eth + stats_1.lpool_balance_c == 2 * five_tokens, 'random eth appeared 1');
    assert(
        stats_1.bal_usdc + stats_1.lpool_balance_p == 2 * five_k_tokens, 'random usdc appeared 1'
    );

    assert(
        stats_1.bal_eth + stats_1.locked_capital_c + stats_1.unlocked_capital_c == 2 * five_tokens,
        'random eth appeared 2'
    );
    assert(
        stats_1.bal_usdc
            + stats_1.locked_capital_p
            + stats_1.unlocked_capital_p == 2 * five_k_tokens,
        'random usdc appeared 2'
    );

    assert(stats_1.locked_capital_c == 1000000000000000000, 'Call1 locked wrong');
    assert(stats_1.locked_capital_p == 1500000000, 'Put1 locked wrong');

    assert(stats_1.unlocked_capital_c == 4003813455106775683, 'Call1 unlocked wrong');
    assert(stats_1.unlocked_capital_p == 0xd77d13a3, 'Put1 unlocked wrong');

    assert(
        stats_1.volatility_c == FixedTrait::from_felt(2213609288845146193900), 'Call1 vol wrong'
    );
    assert(stats_1.volatility_p == FixedTrait::from_felt(2398076729582241710000), 'Put1 vol wrong');

    assert(stats_1.opt_pos_lc == 0, 'lc1 pos wrong');
    assert(stats_1.opt_pos_sc == 1000000000000000000, 'sc1 pos wrong');
    assert(stats_1.opt_pos_lp == 0, 'lp1 pos wrong');
    assert(stats_1.opt_pos_sp == 1000000000000000000, 'sp1 pos wrong');
}

// User opens and closes but pool retains long position
#[test]
fn test_trade_close_short_with_pool_long_position() {
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
            1, // Short
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
            1, // Short
            one_int,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_felt(1), // Disable this check
            99999999999 // Disable this check
        );

    // Open some LONG position so that pool has short position
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
            1, // Short
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
            1, // Short
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
            1, // Short
            one_int,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_unscaled_felt(100_000), // Disable this check
            99999999999 // Disable this check
        );

    let stats_1 = StatsTrait::new(ctx, dsps);

    assert(stats_1.bal_lpt_c == five_tokens, 'Call lpt bal wrong');
    assert(stats_1.bal_lpt_p == five_k_tokens, 'Put lpt bal wrong');

    assert(stats_1.bal_opt_lc == 0, 'Opt1 lc bal wrong');
    assert(stats_1.bal_opt_sc == 1000000000000000000, 'Opt1 sc bal wrong');
    assert(stats_1.bal_opt_lp == 0, 'Opt1 lp bal wrong');
    assert(stats_1.bal_opt_sp == 1000000000000000000, 'Opt1 sp bal wrong');

    assert(stats_1.bal_eth == 4001480272513744782, 'Eth1 bal wrong');
    assert(stats_1.bal_usdc == 3592628326, 'Usdc1 bal wrong');

    assert(stats_1.lpool_balance_c == 4998519727486255218, 'Call1 lpool bal wrong');
    assert(stats_1.lpool_balance_p == 4907371674, 'Put1 lpool bal wrong');

    assert(
        stats_1.bal_eth + stats_1.lpool_balance_c + 1000000000000000000 == 2 * five_tokens,
        'random eth appeared 1'
    );
    assert(
        stats_1.bal_usdc + stats_1.lpool_balance_p + 1500000000 == 2 * five_k_tokens,
        'random usdc appeared 1'
    );

    assert(stats_1.locked_capital_c == 0, 'Call1 locked wrong');
    assert(stats_1.locked_capital_p == 0, 'Put1 locked wrong');

    assert(
        stats_1.bal_eth
            + stats_1.locked_capital_c
            + stats_1.unlocked_capital_c
            + 1000000000000000000 == 2 * five_tokens,
        'random eth appeared 2'
    );
    assert(
        stats_1.bal_usdc
            + stats_1.locked_capital_p
            + stats_1.unlocked_capital_p
            + 1500000000 == 2 * five_k_tokens,
        'random usdc appeared 2'
    );

    assert(stats_1.unlocked_capital_c == 4998519727486255218, 'Call1 unlocked wrong');
    assert(stats_1.unlocked_capital_p == 4907371674, 'Put1 unlocked wrong');

    assert(
        stats_1.volatility_c == FixedTrait::from_felt(1475739525896764129300), 'Call1 vol wrong'
    );
    assert(stats_1.volatility_p == FixedTrait::from_felt(1291272085159668613200), 'Put1 vol wrong');

    assert(stats_1.opt_pos_lc == 1000000000000000000, 'lc1 pos wrong');
    assert(stats_1.opt_pos_sc == 0, 'sc1 pos wrong');
    assert(stats_1.opt_pos_lp == 1000000000000000000, 'lp1 pos wrong');
    assert(stats_1.opt_pos_sp == 0, 'sp1 pos wrong');
}

// User opens and closes but pool retains short position
#[test]
fn test_trade_close_short_with_pool_short_position() {
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
            1, // Short
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
            1, // Short
            one_int,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_felt(1), // Disable this check
            99999999999 // Disable this check
        );

    // Open some LONG position so that pool has short position
    let _ = dsps
        .amm
        .trade_open(
            0, // Call
            ctx.strike_price,
            ctx.expiry,
            0, // Long
            one_int * 2,
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
            0, // Short
            one_int * 2,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_unscaled_felt(100_000), // Disable this check
            99999999999 // Disable this check
        );

    let short_call_premia = dsps
        .amm
        .trade_close(
            0, // Call
            ctx.strike_price,
            ctx.expiry,
            1, // Short
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
            1, // Short
            one_int,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_unscaled_felt(100_000), // Disable this check
            99999999999 // Disable this check
        );

    let stats_1 = StatsTrait::new(ctx, dsps);

    assert(stats_1.bal_lpt_c == five_tokens, 'Call lpt bal wrong');
    assert(stats_1.bal_lpt_p == five_k_tokens, 'Put lpt bal wrong');

    assert(stats_1.bal_opt_lc == 2000000000000000000, 'Opt1 lc bal wrong');
    assert(stats_1.bal_opt_sc == 0, 'Opt1 sc bal wrong');
    assert(stats_1.bal_opt_lp == 2000000000000000000, 'Opt1 lp bal wrong');
    assert(stats_1.bal_opt_sp == 0, 'Opt1 sp bal wrong');

    assert(stats_1.bal_eth == 4990693017777102250, 'Eth1 bal wrong');
    assert(stats_1.bal_usdc == 4771540710, 'Usdc1 bal wrong');

    assert(stats_1.lpool_balance_c == 5009306982222897750, 'Call1 lpool bal wrong');
    assert(stats_1.lpool_balance_p == 5228459290, 'Put1 lpool bal wrong');

    assert(stats_1.bal_eth + stats_1.lpool_balance_c == 2 * five_tokens, 'random eth appeared 1');
    assert(
        stats_1.bal_usdc + stats_1.lpool_balance_p == 2 * five_k_tokens, 'random usdc appeared 1'
    );

    assert(stats_1.locked_capital_c == 2000000000000000000, 'Call1 locked wrong');
    assert(stats_1.locked_capital_p == 3000000000, 'Put1 locked wrong');

    assert(
        stats_1.bal_eth + stats_1.locked_capital_c + stats_1.unlocked_capital_c == 2 * five_tokens,
        'random eth appeared 2'
    );
    assert(
        stats_1.bal_usdc
            + stats_1.locked_capital_p
            + stats_1.unlocked_capital_p == 2 * five_k_tokens,
        'random usdc appeared 2'
    );

    assert(stats_1.unlocked_capital_c == 3009306982222897750, 'Call1 unlocked wrong');
    assert(stats_1.unlocked_capital_p == 2228459290, 'Put1 unlocked wrong');

    assert(
        stats_1.volatility_c == FixedTrait::from_felt(2582544170319337226200), 'Call1 vol wrong'
    );
    assert(stats_1.volatility_p == FixedTrait::from_felt(2951479051793528258500), 'Put1 vol wrong');

    assert(stats_1.opt_pos_lc == 0, 'lc1 pos wrong');
    assert(stats_1.opt_pos_sc == 2000000000000000000, 'sc1 pos wrong');
    assert(stats_1.opt_pos_lp == 0, 'lp1 pos wrong');
    assert(stats_1.opt_pos_sp == 2000000000000000000, 'sp1 pos wrong');
}

#[test]
#[should_panic(expected: ('u256_sub Overflow',))]
fn test_trade_close_not_enough_opt() {
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
        .trade_close(
            0, // Call
            ctx.strike_price,
            ctx.expiry,
            0, // Long
            one_int * 2,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_felt(1), // Disable this check
            99999999999 // Disable this check
        );
}

#[test]
#[should_panic(expected: ('VTI - Trading is stopped',))]
fn test_trade_close_2hr_before_expiry() {
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

    start_warp(ctx.amm_address, ctx.expiry - 3600);

    // Close the trade
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
            FixedTrait::from_felt(1), // Disable this check
            99999999999 // Disable this check
        );
}

#[test]
#[should_panic(expected: ('VTI - opt already expired',))]
fn test_trade_close_after_expiry() {
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

    start_warp(ctx.amm_address, ctx.expiry + 1);

    // Close the trade
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
            FixedTrait::from_felt(1), // Disable this check
            99999999999 // Disable this check
        );

}
