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

// TODO: Add more scenarios (long call in profit, short put in profit etc)

#[test]
fn test_expire_long() {
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

    // Conduct some trades
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

    // Warp to one second after expiry
    stop_warp(ctx.amm_address);
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

    // Expire pools
    dsps
        .amm
        .expire_option_token_for_pool(
            ctx.call_lpt_address, 0, // Long
             ctx.strike_price, ctx.expiry
        );
    dsps
        .amm
        .expire_option_token_for_pool(
            ctx.call_lpt_address, 1, // Long
             ctx.strike_price, ctx.expiry
        );
    dsps
        .amm
        .expire_option_token_for_pool(ctx.put_lpt_address, 0, // Long
         ctx.strike_price, ctx.expiry);
    dsps
        .amm
        .expire_option_token_for_pool(ctx.put_lpt_address, 1, // Long
         ctx.strike_price, ctx.expiry);

    let stats_1 = StatsTrait::new(ctx, dsps);

    assert(stats_1.bal_lpt_c == five_tokens, 'Call lpt bal wrong');
    assert(stats_1.bal_lpt_p == five_k_tokens, 'Put lpt bal wrong');

    assert(
        stats_1.bal_eth == 4996530644608173865, 'Eth1 bal wrong'
    ); // User hasn't expired yet, so no change to just opening a trade
    assert(
        stats_1.bal_usdc == 4891355438, 'Usdc1 bal wrong'
    ); // User hasn't expired yet, so no change to just opening a trade

    assert(stats_1.bal_opt_lc == one_int.into(), 'Opt1 lc bal wrong');
    assert(stats_1.bal_opt_sc == 0, 'Opt1 sc bal wrong');
    assert(stats_1.bal_opt_lp == one_int.into(), 'Opt1 lp bal wrong');
    assert(stats_1.bal_opt_sp == 0, 'Opt1 sp bal wrong');

    assert(stats_1.lpool_balance_c == 5003469355391826135, 'Call1 lpool bal wrong');
    assert(stats_1.lpool_balance_p == 5008644562, 'Put1 lpool bal wrong');

    assert(stats_1.bal_eth + stats_1.lpool_balance_c == 2 * five_tokens, 'random eth appeared');
    assert(
        stats_1.bal_usdc + stats_1.lpool_balance_p + 100000000 == 2 * five_k_tokens,
        'random usdc appeared'
    );

    assert(stats_1.unlocked_capital_c == 5003469355391826135, 'Call1 unlocked wrong');
    assert(stats_1.unlocked_capital_p == 5008644562, 'Put1 unlocked wrong');

    assert(
        stats_1.bal_eth + stats_1.unlocked_capital_c + stats_1.locked_capital_c == 2 * five_tokens,
        'random eth appeared'
    );
    assert(
        stats_1.bal_usdc
            + stats_1.unlocked_capital_p
            + stats_1.locked_capital_p
            + 100000000 == 2 * five_k_tokens,
        'random usdc appeared'
    );

    assert(stats_1.locked_capital_c == 0, 'Call1 locked wrong');
    assert(stats_1.locked_capital_p == 0, 'Put1 locked wrong');

    assert(stats_1.pool_pos_val_c == FixedTrait::from_felt(0), 'Call1 pos val wrong');
    assert(stats_1.pool_pos_val_p == FixedTrait::from_felt(0), 'Put1 pos val wrong');

    assert(
        stats_1.volatility_c == FixedTrait::from_felt(2213609288845146193900), 'Call1 vol wrong'
    );
    assert(stats_1.volatility_p == FixedTrait::from_felt(2398076729582241710000), 'Put1 vol wrong');

    assert(stats_1.opt_pos_lc == 0, 'lc1 pos wrong');
    assert(stats_1.opt_pos_sc == 0, 'sc1 pos wrong');
    assert(stats_1.opt_pos_lp == 0, 'lp1 pos wrong');
    assert(stats_1.opt_pos_sp == 0, 'sp1 pos wrong');
}


#[test]
fn test_expire_short() {
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

    // Conduct some shorts
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

    // Warp to one second after expiry
    stop_warp(ctx.amm_address);
    // stop_mock_call(PRAGMA_ORACLE_ADDRESS.try_into().unwrap(), 'get_spot_median');

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

    // Expire pools
    dsps
        .amm
        .expire_option_token_for_pool(
            ctx.call_lpt_address, 0, // Long
             ctx.strike_price, ctx.expiry
        );
    dsps
        .amm
        .expire_option_token_for_pool(
            ctx.call_lpt_address, 1, // Long
             ctx.strike_price, ctx.expiry
        );
    dsps
        .amm
        .expire_option_token_for_pool(ctx.put_lpt_address, 0, // Long
         ctx.strike_price, ctx.expiry);
    dsps
        .amm
        .expire_option_token_for_pool(ctx.put_lpt_address, 1, // Long
         ctx.strike_price, ctx.expiry);

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
    assert(stats_1.lpool_balance_p == 5001364821, 'Put1 lpool bal wrong');

    assert(
        stats_1.bal_eth + stats_1.lpool_balance_c + one_int.into() == 2 * five_tokens,
        'random eth appeared'
    );
    assert(
        stats_1.bal_usdc + stats_1.lpool_balance_p + 1400000000 == 2 * five_k_tokens,
        'random usdc appeared'
    );

    assert(stats_1.unlocked_capital_c == 4998493438637438301, 'Call1 unlocked wrong');
    assert(stats_1.unlocked_capital_p == 5001364821, 'Put1 unlocked wrong');

    assert(stats_1.locked_capital_c == 0, 'Call1 locked wrong');
    assert(stats_1.locked_capital_p == 0, 'Put1 locked wrong');

    assert(stats_1.pool_pos_val_c == FixedTrait::from_felt(0), 'Call1 pos val wrong');
    assert(stats_1.pool_pos_val_p == FixedTrait::from_felt(0), 'Put1 pos val wrong');

    assert(
        stats_1.volatility_c == FixedTrait::from_felt(1475739525896764129300), 'Call1 vol wrong'
    );
    assert(stats_1.volatility_p == FixedTrait::from_felt(1291272085159668613200), 'Put1 vol wrong');

    assert(stats_1.opt_pos_lc == 0, 'lc1 pos wrong');
    assert(stats_1.opt_pos_sc == 0, 'sc1 pos wrong');
    assert(stats_1.opt_pos_lp == 0, 'lp1 pos wrong');
    assert(stats_1.opt_pos_sp == 0, 'sp1 pos wrong');
}
