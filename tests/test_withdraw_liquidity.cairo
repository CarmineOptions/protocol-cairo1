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

use carmine_protocol::erc20_interface::IERC20Dispatcher;
use carmine_protocol::erc20_interface::IERC20DispatcherTrait;

#[test]
fn test_withdraw_liquidity() {
    let (ctx, dsps) = deploy_setup();
    let five_tokens: u256 = 5000000000000000000; // with 18 decimals
    let five_k_tokens: u256 = 5000000000; // with 6 decimals

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

    let stats_0 = StatsTrait::new(ctx, dsps);

    assert(stats_0.bal_lpt_c == five_tokens, 'Call lpt bal wrong');
    assert(stats_0.bal_lpt_p == five_k_tokens, 'Put lpt bal wrong');

    assert(stats_0.bal_eth == five_tokens, 'Eth bal wrong');
    assert(stats_0.bal_usdc == five_k_tokens, 'Usdc bal wrong');

    assert(stats_0.unlocked_capital_c == five_tokens, 'Call unlocked wrong');
    assert(stats_0.unlocked_capital_p == five_k_tokens, 'Put unlocked wrong');

    assert(stats_0.volatility_c == FixedTrait::from_unscaled_felt(100), 'Call vol wrong');
    assert(stats_0.volatility_p == FixedTrait::from_unscaled_felt(100), 'Put vol wrong');

    assert(stats_0.opt_pos_lc == 0, 'lc pos wrong');
    assert(stats_0.opt_pos_sc == 0, 'sc pos wrong');
    assert(stats_0.opt_pos_lp == 0, 'lp pos wrong');
    assert(stats_0.opt_pos_sp == 0, 'sp pos wrong');

    assert(stats_0.lpool_balance_c == five_tokens, 'Call lpool bal wrong');
    assert(stats_0.lpool_balance_p == five_k_tokens, 'Put lpool bal wrong');

    assert(stats_0.locked_capital_c == 0, 'Call locked wrong');
    assert(stats_0.locked_capital_p == 0, 'Put locked wrong');

    assert(stats_0.pool_pos_val_c == FixedTrait::ZERO(), 'Call pos val wrong');
    assert(stats_0.pool_pos_val_p == FixedTrait::ZERO(), 'Put pos val wrong');

    ///////////////////////////////////////////////////
    // WITHDRAW MORE LIQUIDITY
    ///////////////////////////////////////////////////

    let one_eth: u256 = 1000000000000000000;
    let one_k_usdc: u256 = 1000000000;

    start_roll(ctx.call_lpt_address, 2);
    dsps
        .amm
        .withdraw_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, // Call
         one_eth);

    start_roll(ctx.put_lpt_address, 2);
    dsps
        .amm
        .withdraw_liquidity(
            ctx.usdc_address, ctx.usdc_address, ctx.eth_address, 1, // Put
             one_k_usdc
        );

    let stats_1 = StatsTrait::new(ctx, dsps);

    assert(stats_1.bal_lpt_c == five_tokens - one_eth, 'Call1 lpt bal wrong');
    assert(stats_1.bal_lpt_p == five_k_tokens - one_k_usdc, 'Put1 lpt bal wrong');

    assert(stats_1.bal_eth == five_tokens + one_eth, 'Eth1 bal wrong');
    assert(stats_1.bal_usdc == five_k_tokens + one_k_usdc, 'Usdc1 bal wrong');

    assert(stats_1.unlocked_capital_c == five_tokens - one_eth, 'Call1 unlocked wrong');
    assert(stats_1.unlocked_capital_p == five_k_tokens - one_k_usdc, 'Put1 unlocked wrong');

    assert(stats_1.volatility_c == FixedTrait::from_unscaled_felt(100), 'Call1 vol wrong');
    assert(stats_1.volatility_p == FixedTrait::from_unscaled_felt(100), 'Put1 vol wrong');

    assert(stats_1.opt_pos_lc == 0, 'lc1 pos wrong');
    assert(stats_1.opt_pos_sc == 0, 'sc1 pos wrong');
    assert(stats_1.opt_pos_lp == 0, 'lp1 pos wrong');
    assert(stats_1.opt_pos_sp == 0, 'sp1 pos wrong');

    assert(stats_1.lpool_balance_c == five_tokens - one_eth, 'Call1 lpool bal wrong');
    assert(stats_1.lpool_balance_p == five_k_tokens - one_k_usdc, 'Put1 lpool bal wrong');

    assert(stats_1.locked_capital_c == 0, 'Call1 locked wrong');
    assert(stats_1.locked_capital_p == 0, 'Put1 locked wrong');

    assert(stats_1.pool_pos_val_c == FixedTrait::ZERO(), 'Call1 pos val wrong');
    assert(stats_1.pool_pos_val_p == FixedTrait::ZERO(), 'Put1 pos val wrong');

    start_warp(ctx.amm_address, 1000000000 + 60 * 60 * 12);
    start_prank(ctx.amm_address, ctx.admin_address);
    let one_int = 1000000000000000000; // 1*10**18

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
    let short_put_premia = dsps
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

    assert(long_call_premia == FixedTrait::from_felt(14425957268832963), 'Long Call premia wrong');
    assert(
        short_call_premia == FixedTrait::from_felt(14425957268832963), 'Short Call premia wrong'
    );

    assert(
        long_put_premia == FixedTrait::from_felt(1869892212451346729800), 'Long put premia wrong'
    );
    assert(
        short_put_premia == FixedTrait::from_felt(1869892212451346729800), 'Short put premia wrong'
    );

    let stats_2 = StatsTrait::new(ctx, dsps);

    assert(stats_2.bal_lpt_c == five_tokens - one_eth, 'Call2 lpt bal wrong');
    assert(stats_2.bal_lpt_p == five_k_tokens - one_k_usdc, 'Put2 lpt bal wrong');

    assert(stats_2.bal_eth == 4999953078037366845, 'Eth2 bal wrong');
    assert(stats_2.bal_usdc == 4493917977, 'Usdc2 bal wrong');

    assert(stats_2.unlocked_capital_c == 4000046921962633155, 'Call2 unlocked wrong');
    assert(stats_2.unlocked_capital_p == 4006082023, 'Put2 unlocked wrong');

    assert(stats_2.volatility_c == FixedTrait::from_unscaled_felt(100), 'Call2 vol wrong');
    assert(stats_2.volatility_p == FixedTrait::from_unscaled_felt(100), 'Put2 vol wrong');

    assert(stats_2.opt_pos_lc == 0, 'lc2 pos wrong');
    assert(stats_2.opt_pos_sc == 0, 'sc2 pos wrong');
    assert(stats_2.opt_pos_lp == 0, 'lp2 pos wrong');
    assert(stats_2.opt_pos_sp == 0, 'sp2 pos wrong');

    assert(stats_2.lpool_balance_c == 4000046921962633155, 'Call2 lpool bal wrong');
    assert(stats_2.lpool_balance_p == 4006082023, 'Put2 lpool bal wrong');

    assert(stats_2.locked_capital_c == 0, 'Call2 locked wrong');
    assert(stats_2.locked_capital_p == 0, 'Put2 locked wrong');

    assert(stats_2.pool_pos_val_c == FixedTrait::ZERO(), 'Call2 pos val wrong');
    assert(stats_2.pool_pos_val_p == FixedTrait::ZERO(), 'Put2 pos val wrong');

    // Withdraw one more time
    start_roll(ctx.call_lpt_address, 3);
    dsps
        .amm
        .withdraw_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, // Call
         one_eth);

    start_roll(ctx.put_lpt_address, 3);
    dsps
        .amm
        .withdraw_liquidity(
            ctx.usdc_address, ctx.usdc_address, ctx.eth_address, 1, // Put
             one_k_usdc
        );

    let stats_3 = StatsTrait::new(ctx, dsps);

    assert(stats_3.bal_lpt_c == 3000000000000000000, 'Call3 lpt bal wrong');
    assert(stats_3.bal_lpt_p == 3000000000, 'Put3 lpt bal wrong');

    assert(stats_3.bal_eth == 5999964808528025133, 'Eth3 bal wrong');
    assert(stats_3.bal_usdc == 5495438482, 'Usdc3 bal wrong');

    assert(stats_3.unlocked_capital_c == 3000035191471974867, 'Call3 unlocked wrong');
    assert(stats_3.unlocked_capital_p == 3004561518, 'Put3 unlocked wrong');

    assert(stats_3.volatility_c == FixedTrait::from_unscaled_felt(100), 'Call3 vol wrong');
    assert(stats_3.volatility_p == FixedTrait::from_unscaled_felt(100), 'Put3 vol wrong');

    assert(stats_3.opt_pos_lc == 0, 'lc3 pos wrong');
    assert(stats_3.opt_pos_sc == 0, 'sc3 pos wrong');
    assert(stats_3.opt_pos_lp == 0, 'lp3 pos wrong');
    assert(stats_3.opt_pos_sp == 0, 'sp3 pos wrong');

    assert(stats_3.lpool_balance_c == 3000035191471974867, 'Call3 lpool bal wrong');
    assert(stats_3.lpool_balance_p == 3004561518, 'Put3 lpool bal wrong');

    assert(stats_3.locked_capital_c == 0, 'Call3 locked wrong');
    assert(stats_3.locked_capital_p == 0, 'Put3 locked wrong');

    assert(stats_3.pool_pos_val_c == FixedTrait::ZERO(), 'Call3 pos val wrong');
    assert(stats_3.pool_pos_val_p == FixedTrait::ZERO(), 'Put2 pos val wrong');
}


#[test]
#[should_panic(expected: ('Not enough capital',))]
fn test_withdraw_liquidity_not_enough_capital() {
    let (ctx, dsps) = deploy_setup();
    let five_tokens: u128 = 5000000000000000000; // with 18 decimals
    let one_eth: u256 = 1000000000000000000;
    let one_int: u128 = 1000000000000000000;

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

    // Withdraw more capital than capital in amm
    start_roll(ctx.call_lpt_address, 2);
    dsps
        .amm
        .withdraw_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, // call
         one_eth*6);
    
}

#[test]
#[should_panic(expected: ('u256_sub Overflow',))]
fn test_withdraw_liquidity_not_enough_lptokens() {
    let (ctx, dsps) = deploy_setup();
    let five_tokens: u128 = 5000000000000000000; // with 18 decimals
    let one_eth: u256 = 1000000000000000000;
    let one_int: u128 = 1000000000000000000;

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

    let dummy_addr: felt252 = 0x0178227144f45dd9e704dab545018813d17383e4cd1181a94fb7086df8cc50e1;

    // Send lpts to dummy addr
    start_roll(ctx.call_lpt_address, 2);
    start_prank(ctx.call_lpt_address, ctx.admin_address);
    let transfer_res = IERC20Dispatcher { contract_address: ctx.call_lpt_address }
        .transfer(dummy_addr.try_into().unwrap(), one_eth * 4);

    stop_prank(ctx.call_lpt_address);

    // Withdraw more capital than lpts
    start_roll(ctx.call_lpt_address, 3);
    dsps
        .amm
        .withdraw_liquidity(ctx.eth_address, ctx.usdc_address, ctx.eth_address, 0, // call
         one_eth*2);
    
}
