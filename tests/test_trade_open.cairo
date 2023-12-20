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
use carmine_protocol::amm_core::amm::AMM;
use carmine_protocol::amm_interface::{IAMMDispatcher, IAMMDispatcherTrait};
use carmine_protocol::testing::setup::{Ctx, Dispatchers};

use carmine_protocol::tokens::my_token::{MyToken, IMyTokenDispatcher, IMyTokenDispatcherTrait};

// User just opens long
#[test]
fn test_trade_open_long() {
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

    assert(long_call_premia == FixedTrait::from_felt(62134282537632086), 'Long Call premia wrong');
    assert(long_put_premia == FixedTrait::from_felt(0x697aeba39402e15f14), 'Long put premia wrong');

    let stats_1 = StatsTrait::new(ctx, dsps);

    assert(stats_1.bal_lpt_c == five_tokens, 'Call lpt bal wrong');
    assert(stats_1.bal_lpt_p == five_k_tokens, 'Put lpt bal wrong');

    assert(stats_1.bal_eth == 4996530644608173865, 'Eth1 bal wrong');
    assert(stats_1.bal_usdc == 4891355438, 'Usdc1 bal wrong');

    assert(stats_1.bal_opt_lc == one_int.into(), 'Opt1 lc bal wrong');
    assert(stats_1.bal_opt_sc == 0, 'Opt1 sc bal wrong');
    assert(stats_1.bal_opt_lp == one_int.into(), 'Opt1 lp bal wrong');
    assert(stats_1.bal_opt_sp == 0, 'Opt1 sp bal wrong');

    assert(stats_1.lpool_balance_c == 5003469355391826135, 'Call1 lpool bal wrong');
    assert(stats_1.lpool_balance_p == 5108644562, 'Put1 lpool bal wrong');

    assert(stats_1.bal_eth + stats_1.lpool_balance_c == 2 * five_tokens, 'random eth appeared');
    assert(stats_1.bal_usdc + stats_1.lpool_balance_p == 2 * five_k_tokens, 'random usdc appeared');

    assert(stats_1.unlocked_capital_c == 4003469355391826135, 'Call1 unlocked wrong');
    assert(stats_1.unlocked_capital_p == 3608644562, 'Put1 unlocked wrong');

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

    assert(stats_1.locked_capital_c == 1000000000000000000, 'Call1 locked wrong');
    assert(stats_1.locked_capital_p == 1500000000, 'Put1 locked wrong');

    assert(
        stats_1.pool_pos_val_c == FixedTrait::from_felt(18382745762695790568), 'Call1 pos val wrong'
    );
    assert(
        stats_1.pool_pos_val_p == FixedTrait::from_felt(25665977665455938802040),
        'Put1 pos val wrong'
    );

    assert(
        stats_1.volatility_c == FixedTrait::from_felt(2213609288845146193900), 'Call1 vol wrong'
    );
    assert(stats_1.volatility_p == FixedTrait::from_felt(2398076729582241710000), 'Put1 vol wrong');

    assert(stats_1.opt_pos_lc == 0, 'lc1 pos wrong');
    assert(stats_1.opt_pos_sc == one_int.into(), 'sc1 pos wrong');
    assert(stats_1.opt_pos_lp == 0, 'lp1 pos wrong');
    assert(stats_1.opt_pos_sp == one_int.into(), 'sp1 pos wrong');
}

// User just opens short
#[test]
fn test_trade_open_short() {
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

    // short
    let short_call_premia = dsps
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

    let short_put_premia = dsps
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

    assert(short_call_premia == FixedTrait::from_felt(28650672047953412), 'Long Call premia wrong');
    assert(
        short_put_premia == FixedTrait::from_felt(1875771037947335154100), 'Long put premia wrong'
    );

    let stats_1 = StatsTrait::new(ctx, dsps);

    assert(stats_1.bal_lpt_c == five_tokens, 'Call lpt bal wrong');
    assert(stats_1.bal_lpt_p == five_k_tokens, 'Put lpt bal wrong');

    assert(stats_1.bal_opt_lc == 0, 'Opt1 lc bal wrong');
    assert(stats_1.bal_opt_sc == one_int.into(), 'Opt1 sc bal wrong');
    assert(stats_1.bal_opt_lp == 0, 'Opt1 lp bal wrong');
    assert(stats_1.bal_opt_sp == one_int.into(), 'Opt1 sp bal wrong');

    assert(stats_1.bal_eth == 4001506561362561699, 'Eth1 bal wrong');
    assert(stats_1.bal_usdc == 3598635179, 'Usdc1 bal wrong');

    assert(stats_1.lpool_balance_c == 4998493438637438301, 'Call1 lpool bal wrong');
    assert(stats_1.lpool_balance_p == 4901364821, 'Put1 lpool bal wrong');

    // assert(stats_1.bal_eth + stats_1.lpool_balance_c == 2*five_tokens, 'random eth appeared');
    // assert(stats_1.bal_usdc+ stats_1.lpool_balance_p == 2* five_k_tokens, 'random usdc appeared');

    assert(stats_1.unlocked_capital_c == 4998493438637438301, 'Call1 unlocked wrong');
    assert(stats_1.unlocked_capital_p == 4901364821, 'Put1 unlocked wrong');

    assert(stats_1.locked_capital_c == 0, 'Call1 locked wrong');
    assert(stats_1.locked_capital_p == 0, 'Put1 locked wrong');

    assert(
        stats_1.pool_pos_val_c == FixedTrait::from_felt(27791151886514810), 'Call1 pos val wrong'
    );
    assert(
        stats_1.pool_pos_val_p == FixedTrait::from_felt(1819497906808915099526),
        'Put1 pos val wrong'
    );

    assert(
        stats_1.volatility_c == FixedTrait::from_felt(1475739525896764129300), 'Call1 vol wrong'
    );
    assert(stats_1.volatility_p == FixedTrait::from_felt(1291272085159668613200), 'Put1 vol wrong');

    assert(stats_1.opt_pos_lc == one_int.into(), 'lc1 pos wrong');
    assert(stats_1.opt_pos_sc == 0, 'sc1 pos wrong');
    assert(stats_1.opt_pos_lp == one_int.into(), 'lp1 pos wrong');
    assert(stats_1.opt_pos_sp == 0, 'sp1 pos wrong');
}

// User opens long but pool has long position
#[test]
fn test_trade_open_long_pool_long_position() {
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

    // Open some shorts so pool has LONG position
    let _ = dsps
        .amm
        .trade_open(
            0, // Call
            ctx.strike_price,
            ctx.expiry,
            1, // Short
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
    

    // Open longs
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

    assert(long_call_premia == FixedTrait::from_felt(8082394435302130), 'Long Call premia wrong');
    assert(long_put_premia == FixedTrait::from_felt(1846781395990920563700), 'Long put premia wrong');

    let stats_1 = StatsTrait::new(ctx, dsps);

    assert(stats_1.bal_lpt_c == five_tokens, 'Call lpt bal wrong');
    assert(stats_1.bal_lpt_p == five_k_tokens, 'Put lpt bal wrong');

    assert(stats_1.bal_eth == 3001297127353709564, 'Eth1 bal wrong');
    assert(stats_1.bal_usdc == 2092072362, 'Usdc1 bal wrong');

    assert(stats_1.bal_opt_lc == one_int.into(), 'Opt1 lc bal wrong');
    assert(stats_1.bal_opt_sc == (one_int * 2).into(), 'Opt1 sc bal wrong');
    assert(stats_1.bal_opt_lp == one_int.into(), 'Opt1 lp bal wrong');
    assert(stats_1.bal_opt_sp == (one_int * 2).into(), 'Opt1 sp bal wrong');

    assert(stats_1.lpool_balance_c == 4998702872646290436, 'Call1 lpool bal wrong');
    assert(stats_1.lpool_balance_p == 4907927638, 'Put1 lpool bal wrong');

    assert(stats_1.bal_eth + stats_1.lpool_balance_c + 2000000000000000000 == 2 * five_tokens, 'random eth appeared');
    assert(stats_1.bal_usdc + stats_1.lpool_balance_p + 3000000000 == 2 * five_k_tokens, 'random usdc appeared');

    assert(stats_1.unlocked_capital_c == 4998702872646290436, 'Call1 unlocked wrong');
    assert(stats_1.unlocked_capital_p == 4907927638, 'Put1 unlocked wrong');

    assert(
        stats_1.bal_eth + stats_1.unlocked_capital_c + stats_1.locked_capital_c + 2000000000000000000 == 2 * five_tokens,
        'random eth appeared'
    );
    assert(
        stats_1.bal_usdc
            + stats_1.unlocked_capital_p
            + stats_1.locked_capital_p + 3000000000
            == 2 * five_k_tokens,
        'random usdc appeared'
    );

    assert(stats_1.locked_capital_c == 0, 'Call1 locked wrong');
    assert(stats_1.locked_capital_p == 0, 'Put1 locked wrong');

    assert(
        stats_1.pool_pos_val_c == FixedTrait::from_felt(27791151886514810), 'Call1 pos val wrong'
    );
    assert(
        stats_1.pool_pos_val_p == FixedTrait::from_felt(1819497906808915099526),
        'Put1 pos val wrong'
    );

    assert(
        stats_1.volatility_c == FixedTrait::from_felt(1475739525896764129300), 'Call1 vol wrong'
    );
    assert(stats_1.volatility_p == FixedTrait::from_felt(1291272085159668613100), 'Put1 vol wrong');

    assert(stats_1.opt_pos_lc == one_int.into(), 'lc1 pos wrong');
    assert(stats_1.opt_pos_sc == 0, 'sc1 pos wrong');
    assert(stats_1.opt_pos_lp == one_int.into(), 'lp1 pos wrong');
    assert(stats_1.opt_pos_sp == 0, 'sp1 pos wrong');
}

// User opens short but pool has short position
#[test]
fn test_trade_open_short_pool_short_position() {
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

    let _ = dsps
        .amm
        .trade_open(
            0, // Call
            ctx.strike_price,
            ctx.expiry,
            0, // Long
            one_int*2,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_unscaled_felt(100_000), // Disable this check
            99999999999 // Disable this check
        );

    let short_put_premia = dsps
        .amm
        .trade_open(
            1, // Put
            ctx.strike_price,
            ctx.expiry,
            0, // Long
            one_int*2,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_unscaled_felt(100_000), // Disable this check
            99999999999 // Disable this check
        );
    

    // short
    let short_call_premia = dsps
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

    let short_put_premia = dsps
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

    assert(short_call_premia == FixedTrait::from_felt(105791989625178717), 'Long Call premia wrong');
    assert(
        short_put_premia == FixedTrait::from_felt(2045714777084622220900), 'Long put premia wrong'
    );

    let stats_1 = StatsTrait::new(ctx, dsps);

    assert(stats_1.bal_lpt_c == five_tokens, 'Call lpt bal wrong');
    assert(stats_1.bal_lpt_p == five_k_tokens, 'Put lpt bal wrong');

    assert(stats_1.bal_opt_lc == (one_int * 2).into(), 'Opt1 lc bal wrong');
    assert(stats_1.bal_opt_sc == one_int.into(), 'Opt1 sc bal wrong');
    assert(stats_1.bal_opt_lp == (one_int * 2).into(), 'Opt1 lp bal wrong');
    assert(stats_1.bal_opt_sp == one_int.into(), 'Opt1 sp bal wrong');

    assert(stats_1.bal_eth == 3996308577534598938, 'Eth1 bal wrong');
    assert(stats_1.bal_usdc == 3385031741, 'Usdc1 bal wrong');

    assert(stats_1.lpool_balance_c == 5003691422465401062, 'Call1 lpool bal wrong');
    assert(stats_1.lpool_balance_p == 5114968259, 'Put1 lpool bal wrong');

    assert(stats_1.bal_eth + stats_1.lpool_balance_c + 1000000000000000000 == 2*five_tokens, 'random eth appeared');
    assert(stats_1.bal_usdc+ stats_1.lpool_balance_p + 1500000000 == 2* five_k_tokens, 'random usdc appeared');

    assert(stats_1.unlocked_capital_c == 4003691422465401062, 'Call1 unlocked wrong');
    assert(stats_1.unlocked_capital_p == 3614968259, 'Put1 unlocked wrong');

    assert(stats_1.locked_capital_c == 1000000000000000000, 'Call1 locked wrong');
    assert(stats_1.locked_capital_p == 1500000000, 'Put1 locked wrong');

    assert(
        stats_1.pool_pos_val_c == FixedTrait::from_felt(18382745762695790568), 'Call1 pos val wrong'
    );
    assert(
        stats_1.pool_pos_val_p == FixedTrait::from_felt(25665977665455938802040),
        'Put1 pos val wrong'
    );

    assert(
        stats_1.volatility_c == FixedTrait::from_felt(2213609288845146193900), 'Call1 vol wrong'
    );
    assert(stats_1.volatility_p == FixedTrait::from_felt(2398076729582241710100), 'Put1 vol wrong');

    assert(stats_1.opt_pos_lc == 0, 'lc1 pos wrong');
    assert(stats_1.opt_pos_sc == one_int.into(), 'sc1 pos wrong');
    assert(stats_1.opt_pos_lp == 0, 'lp1 pos wrong');
    assert(stats_1.opt_pos_sp == one_int.into(), 'sp1 pos wrong');
}


// User opens long but pool goes from long position to short one
#[test]
fn test_trade_open_long_with_pool_position_change() {
    let (ctx, dsps) = deploy_setup();
    let five_tokens: u256 = 5000000000000000000; // with 18 decimals
    let five_k_tokens: u256 = 5000000000; // with 6 decimals
    let one_int = 1000000000000000000; // 1*10**18
    let half_int = 500000000000000000;

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

    // Open 0.5 of short options
    let _ = dsps
        .amm
        .trade_open(
            0, // Call
            ctx.strike_price,
            ctx.expiry,
            1, // Long
            half_int,
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
            1, // Long
            half_int,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_felt(1), // Disable this check
            99999999999 // Disable this check
        );


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

    assert(long_call_premia == FixedTrait::from_felt(43936369775213579), 'Long Call premia wrong');
    assert(long_put_premia == FixedTrait::from_felt(1906185325056254172800), 'Long put premia wrong');
    
    let stats_1 = StatsTrait::new(ctx, dsps);

    assert(stats_1.bal_lpt_c == five_tokens, 'Call lpt bal wrong');
    assert(stats_1.bal_lpt_p == five_k_tokens, 'Put lpt bal wrong');

    assert(stats_1.bal_eth == 4498490795527326816, 'Eth1 bal wrong');
    assert(stats_1.bal_usdc == 4193249914, 'Usdc1 bal wrong');

    assert(stats_1.bal_opt_lc == one_int.into(), 'Opt1 lc bal wrong');
    assert(stats_1.bal_opt_sc == half_int.into(), 'Opt1 sc bal wrong');
    assert(stats_1.bal_opt_lp == one_int.into(), 'Opt1 lp bal wrong');
    assert(stats_1.bal_opt_sp == half_int.into(), 'Opt1 sp bal wrong');

    assert(stats_1.lpool_balance_c == 5001509204472673184, 'Call1 lpool bal wrong');
    assert(stats_1.lpool_balance_p == 5056750086, 'Put1 lpool bal wrong');

    assert(stats_1.bal_eth + stats_1.lpool_balance_c + half_int.into() == 2 * five_tokens, 'random eth appeared');
    assert(stats_1.bal_usdc + stats_1.lpool_balance_p + 750000000 == 2 * five_k_tokens, 'random usdc appeared');

    assert(stats_1.unlocked_capital_c == 4501509204472673184, 'Call1 unlocked wrong');
    assert(stats_1.unlocked_capital_p == 4306750086, 'Put1 unlocked wrong');

    assert(
        stats_1.bal_eth + stats_1.unlocked_capital_c + stats_1.locked_capital_c + half_int.into() == 2 * five_tokens,
        'random eth appeared'
    );
    assert(
        stats_1.bal_usdc
            + stats_1.unlocked_capital_p
            + stats_1.locked_capital_p+ 750000000 == 2 * five_k_tokens,
        'random usdc appeared'
    );

    assert(stats_1.locked_capital_c == half_int.into(), 'Call1 locked wrong');
    assert(stats_1.locked_capital_p == (750000000).into(), 'Put1 locked wrong');

    assert(
        stats_1.pool_pos_val_c == FixedTrait::from_felt(9196234209699652984), 'Call1 pos val wrong'
    );
    assert(
        stats_1.pool_pos_val_p == FixedTrait::from_felt(12843714094506033625616),
        'Put1 pos val wrong'
    );

    assert(
        stats_1.volatility_c == FixedTrait::from_felt(2029141848108050677800), 'Call1 vol wrong'
    );
    assert(stats_1.volatility_p == FixedTrait::from_felt(2121375568476598435800), 'Put1 vol wrong');

    assert(stats_1.opt_pos_lc == 0, 'lc1 pos wrong');
    assert(stats_1.opt_pos_sc == half_int.into(), 'sc1 pos wrong');
    assert(stats_1.opt_pos_lp == 0, 'lp1 pos wrong');
    assert(stats_1.opt_pos_sp == half_int.into(), 'sp1 pos wrong');
}


// User opens short but pool goes from short position to long one
#[test]
fn test_trade_open_short_with_pool_position_change() {
    let (ctx, dsps) = deploy_setup();
    let five_tokens: u256 = 5000000000000000000; // with 18 decimals
    let five_k_tokens: u256 = 5000000000; // with 6 decimals
    let one_int = 1000000000000000000; // 1*10**18
    let half_int = 500000000000000000;

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

    // Open 0.5 of long options
    let _ = dsps
        .amm
        .trade_open(
            0, // Call
            ctx.strike_price,
            ctx.expiry,
            0, // Long
            half_int,
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
            half_int,
            ctx.usdc_address,
            ctx.eth_address,
            FixedTrait::from_unscaled_felt(100_000), // Disable this check
            99999999999 // Disable this check
        );

    // Short
    let short_call_premia = dsps
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

    let short_put_premia = dsps
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

    assert(short_call_premia == FixedTrait::from_felt(43936369775213579), 'Long Call premia wrong');
    assert(short_put_premia == FixedTrait::from_felt(1906185325056254172800), 'Long put premia wrong');

    let stats_1 = StatsTrait::new(ctx, dsps);

    assert(stats_1.bal_lpt_c == five_tokens, 'Call lpt bal wrong');
    assert(stats_1.bal_lpt_p == five_k_tokens, 'Put lpt bal wrong');

    assert(stats_1.bal_opt_lc == half_int.into(), 'Opt1 lc bal wrong');
    assert(stats_1.bal_opt_sc == one_int.into(), 'Opt1 sc bal wrong');
    assert(stats_1.bal_opt_lp == half_int.into(), 'Opt1 lp bal wrong');
    assert(stats_1.bal_opt_sp == one_int.into(), 'Opt1 sp bal wrong');

    assert(stats_1.bal_eth == 4000839196958822517, 'Eth1 bal wrong');
    assert(stats_1.bal_usdc == 3546493615, 'Usdc1 bal wrong');

    assert(stats_1.lpool_balance_c == 4999160803041177483, 'Call1 lpool bal wrong');
    assert(stats_1.lpool_balance_p == 4953506385, 'Put1 lpool bal wrong');

    assert(stats_1.bal_eth + stats_1.lpool_balance_c + one_int.into() == 2 * five_tokens, 'random eth appeared');
    assert(stats_1.bal_usdc+ stats_1.lpool_balance_p + 1500000000 == 2 * five_k_tokens, 'random usdc appeared');

    assert(stats_1.unlocked_capital_c == 4999160803041177483, 'Call1 unlocked wrong');
    assert(stats_1.unlocked_capital_p == 4953506385, 'Put1 unlocked wrong');

    assert(stats_1.locked_capital_c == 0, 'Call1 locked wrong');
    assert(stats_1.locked_capital_p == 0, 'Put1 locked wrong');

    assert(
        stats_1.pool_pos_val_c == FixedTrait::from_felt(17414552206169978), 'Call1 pos val wrong'
    );
    assert(
        stats_1.pool_pos_val_p == FixedTrait::from_felt(916516563938195284225),
        'Put1 pos val wrong'
    );

    assert(
        stats_1.volatility_c == FixedTrait::from_felt(1660206966633859645400), 'Call1 vol wrong'
    );
    assert(stats_1.volatility_p == FixedTrait::from_felt(1567973246265311887400), 'Put1 vol wrong');

    assert(stats_1.opt_pos_lc == half_int, 'lc1 pos wrong');
    assert(stats_1.opt_pos_sc == 0, 'sc1 pos wrong');
    assert(stats_1.opt_pos_lp == half_int, 'lp1 pos wrong');
    assert(stats_1.opt_pos_sp == 0, 'sp1 pos wrong');
}
