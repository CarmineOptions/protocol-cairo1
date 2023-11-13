// run them in one single test

use starknet::ContractAddress;
use carmine_protocol::amm_core::peripheries::view::View;
use carmine_protocol::testing::setup::{deploy_setup, _add_expired_option};
use array::ArrayTrait;
use debug::PrintTrait;
use carmine_protocol::amm_core::amm::AMM;
use carmine_protocol::amm_interface::{IAMMDispatcher, IAMMDispatcherTrait};
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
#[available_gas(100000000000000)]
fn test_get_all_options() {
    let (ctx, dsps) = deploy_setup();

    let mut call_opts = dsps.amm.get_all_options(ctx.call_lpt_address);
    let mut put_opts = dsps.amm.get_all_options(ctx.put_lpt_address);

    assert(call_opts.len() == 2, 'Should be 2 copts');
    assert(put_opts.len() == 2, 'Should be 2 popts');

    // Calls
    let copt_1 = call_opts.pop_front().unwrap();
    let copt_2 = call_opts.pop_front().unwrap();

    assert(copt_1.option_side == 0, 'COPT1 side wrong');
    assert(copt_1.maturity == ctx.expiry, 'COPT1 expiry wrong');
    assert(copt_1.strike_price == ctx.strike_price, 'COPT1 strike wrong');
    assert(copt_1.quote_token_address == ctx.usdc_address, 'COPT1 qaddr wrong');
    assert(copt_1.base_token_address == ctx.eth_address, 'COPT1 baddr wrong');
    assert(copt_1.option_type == 0, 'COPT1 baddr wrong');

    assert(copt_2.option_side == 1, 'COPT2 side wrong');
    assert(copt_2.maturity == ctx.expiry, 'COPT2 expiry wrong');
    assert(copt_2.strike_price == ctx.strike_price, 'COPT2 strike wrong');
    assert(copt_2.quote_token_address == ctx.usdc_address, 'COPT2 qaddr wrong');
    assert(copt_2.base_token_address == ctx.eth_address, 'COPT2 baddr wrong');
    assert(copt_2.option_type == 0, 'COPT2 baddr wrong');

    // Puts
    let popt_1 = put_opts.pop_front().unwrap();
    let popt_2 = put_opts.pop_front().unwrap();

    assert(popt_1.option_side == 0, 'POPT1 side wrong');
    assert(popt_1.maturity == ctx.expiry, 'POPT1 expiry wrong');
    assert(popt_1.strike_price == ctx.strike_price, 'POPT1 strike wrong');
    assert(popt_1.quote_token_address == ctx.usdc_address, 'POPT1 qaddr wrong');
    assert(popt_1.base_token_address == ctx.eth_address, 'POPT1 baddr wrong');
    assert(popt_1.option_type == 1, 'POPT1 baddr wrong');

    assert(popt_2.option_side == 1, 'POPT2 side wrong');
    assert(popt_2.maturity == ctx.expiry, 'POPT2 expiry wrong');
    assert(popt_2.strike_price == ctx.strike_price, 'POPT2 strike wrong');
    assert(popt_2.quote_token_address == ctx.usdc_address, 'POPT2 qaddr wrong');
    assert(popt_2.base_token_address == ctx.eth_address, 'POPT2 baddr wrong');
    assert(popt_2.option_type == 1, 'POPT2 baddr wrong');
}

#[test]
fn test_get_all_lptoken_addresses() {
    let (ctx, dsps) = deploy_setup();
    let mut lpt_addrs = dsps.amm.get_all_lptoken_addresses();

    assert(lpt_addrs.len() == 2, 'Num of lptaddrrs wrong');
    assert(lpt_addrs.pop_front().unwrap() == ctx.call_lpt_address, 'Wrong call lpt addr');
    assert(lpt_addrs.pop_front().unwrap() == ctx.put_lpt_address, 'Wrong put lpt addr');
}


#[test]
fn test_get_all_poolinfo() {
    let (ctx, dsps) = deploy_setup();
    let mut pool_infos = dsps.amm.get_all_poolinfo();

    assert(pool_infos.len() == 2, 'Num of poolinfos wrong');

    let call_lpt = pool_infos.pop_front().unwrap();
    let put_lpt = pool_infos.pop_front().unwrap();

    let five_eth = 5000000000000000000;
    let five_k_usdc = 5000000000;

    assert(call_lpt.pool.quote_token_address == ctx.usdc_address, 'Quote token mismatch');
    assert(call_lpt.pool.base_token_address == ctx.eth_address, 'Base token mismatch');
    assert(call_lpt.pool.option_type == 0, 'Option type mismatch');
    assert(call_lpt.lptoken_address == ctx.call_lpt_address, 'LPT addr mismatch');
    assert(call_lpt.staked_capital == five_eth, 'Staked capital mismatch');
    assert(call_lpt.unlocked_capital == five_eth, 'Unlocked capital mismatch');
    assert(call_lpt.value_of_pool_position == FixedTrait::ZERO(), 'Pool pos val mismatch');

    assert(put_lpt.pool.quote_token_address == ctx.usdc_address, 'Quote token mismatch');
    assert(put_lpt.pool.base_token_address == ctx.eth_address, 'Base token mismatch');
    assert(put_lpt.pool.option_type == 1, 'Option type mismatch');
    assert(put_lpt.lptoken_address == ctx.put_lpt_address, 'LPT addr mismatch');
    assert(put_lpt.staked_capital == five_k_usdc, 'Staked capital mismatch');
    assert(put_lpt.unlocked_capital == five_k_usdc, 'Unlocked capital mismatch');
    assert(put_lpt.value_of_pool_position == FixedTrait::ZERO(), 'Pool pos val mismatch');
}

#[test]
fn test_get_total_premia() {
    let (ctx, dsps) = deploy_setup();

    let one = 1000000000000000000;

    let option_long_call = Option_ {
        option_side: 0,
        maturity: ctx.expiry,
        strike_price: ctx.strike_price,
        quote_token_address: ctx.usdc_address,
        base_token_address: ctx.eth_address,
        option_type: 0
    };

    let option_short_call = Option_ {
        option_side: 1,
        maturity: ctx.expiry,
        strike_price: ctx.strike_price,
        quote_token_address: ctx.usdc_address,
        base_token_address: ctx.eth_address,
        option_type: 0
    };

    let option_long_put = Option_ {
        option_side: 0,
        maturity: ctx.expiry,
        strike_price: ctx.strike_price,
        quote_token_address: ctx.usdc_address,
        base_token_address: ctx.eth_address,
        option_type: 1
    };

    let option_short_put = Option_ {
        option_side: 1,
        maturity: ctx.expiry,
        strike_price: ctx.strike_price,
        quote_token_address: ctx.usdc_address,
        base_token_address: ctx.eth_address,
        option_type: 1
    };

    start_prank(ctx.amm_address, ctx.admin_address);
    start_warp(ctx.amm_address, 1000000000 + 60 * 60 * 12);
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

    let (total_premia_before_fees_long_call, total_premia_including_fees_long_call) = dsps
        .amm
        .get_total_premia(option_long_call, one, false);

    let (total_premia_before_fees_short_call, total_premia_including_fees_short_call) = dsps
        .amm
        .get_total_premia(option_short_call, one, false);

    let (total_premia_before_fees_long_put, total_premia_including_fees_long_put) = dsps
        .amm
        .get_total_premia(option_long_put, one, false);

    let (total_premia_before_fees_short_put, total_premia_including_fees_short_put) = dsps
        .amm
        .get_total_premia(option_short_put, one, false);

    assert(
        total_premia_before_fees_long_call == FixedTrait::from_felt(14425957268832963),
        'Long Call bf wrong'
    );
    assert(
        total_premia_including_fees_long_call == FixedTrait::from_felt(14858735986897951),
        'Long call if wrong'
    );

    assert(
        total_premia_before_fees_short_call == FixedTrait::from_felt(4446708911745745),
        'Short Call bf wrong'
    );
    assert(
        total_premia_including_fees_short_call == FixedTrait::from_felt(4313307644393373),
        'Short call if wrong'
    );

    assert(
        total_premia_before_fees_long_put == FixedTrait::from_felt(1869892212451346729800),
        'Long put bf wrong'
    );
    assert(
        total_premia_including_fees_long_put == FixedTrait::from_felt(1925988978824887131645),
        'Long put if wrong'
    );

    assert(
        total_premia_before_fees_short_put == FixedTrait::from_felt(1848856287951398584000),
        'Short put bf wrong'
    );
    assert(
        total_premia_including_fees_short_put == FixedTrait::from_felt(1793390599312856626529),
        'Short put if wrong'
    );
}

// fn get_all_non_expired_options_with_premia(lpt_addr: LPTAddress) -> Array<OptionWithPremia> {
#[test]
fn test_get_all_non_expired_options_with_premia() {
    let (ctx, dsps) = deploy_setup();
    _add_expired_option(ctx, dsps);

    // There are 3 call options
    //      two with maturity 1000000000 + 60*60*24
    //      one with maturity 1000000000 - 60*60*24
    // There are 2 put options both with maturity 1000000000 + 60*60*24
    // Only the options with maturity 1000000000 + 60*60*24 should show -> 2 calls, 2 puts

    start_warp(ctx.amm_address, 1000000000 + 60 * 60 * 12);
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

    let mut call_opts = dsps.amm.get_all_non_expired_options_with_premia(ctx.call_lpt_address);
    let mut put_opts = dsps.amm.get_all_non_expired_options_with_premia(ctx.put_lpt_address);

    assert(call_opts.len() == 2, 'Too many call opts');
    assert(put_opts.len() == 2, 'Too many put opts');

    let call_0 = call_opts.pop_front().unwrap();
    let call_1 = call_opts.pop_front().unwrap();

    let call_option_addr_0 = dsps
        .amm
        .get_option_token_address(
            ctx.call_lpt_address,
            call_0.option.option_side,
            call_0.option.maturity,
            call_0.option.strike_price
        );
    let call_option_addr_1 = dsps
        .amm
        .get_option_token_address(
            ctx.call_lpt_address,
            call_1.option.option_side,
            call_1.option.maturity,
            call_1.option.strike_price
        );

    assert(call_option_addr_0 == ctx.long_call_address, 'LC addr not matching');
    assert(call_option_addr_1 == ctx.short_call_address, 'SC addr not matching');

    let put_0 = put_opts.pop_front().unwrap();
    let put_1 = put_opts.pop_front().unwrap();

    let put_option_addr_0 = dsps
        .amm
        .get_option_token_address(
            ctx.put_lpt_address,
            put_0.option.option_side,
            put_0.option.maturity,
            put_0.option.strike_price
        );
    let put_option_addr_1 = dsps
        .amm
        .get_option_token_address(
            ctx.put_lpt_address,
            put_1.option.option_side,
            put_1.option.maturity,
            put_1.option.strike_price
        );
    assert(put_option_addr_0 == ctx.long_put_address, 'LP addr not matching');
    assert(put_option_addr_1 == ctx.short_put_address, 'SP addr not matching');

    assert(call_0.premia == FixedTrait::from_felt(14858735986897951), 'LC premia wrong');
    assert(call_1.premia == FixedTrait::from_felt(4313307644393373), 'SC premia wrong');

    assert(put_0.premia == FixedTrait::from_felt(1925988978824887131645), 'LP premia wrong');
    assert(put_1.premia == FixedTrait::from_felt(1793390599312856626529), 'SP premia wrong');
}

#[test]
fn test_get_user_pool_infos() {
    let (ctx, dsps) = deploy_setup();

    let mut pool_infos = dsps.amm.get_user_pool_infos(ctx.admin_address);

    assert(pool_infos.len() == 2, 'too much pool info');

    let cp = pool_infos.pop_front().unwrap(); // Call pool
    let pp = pool_infos.pop_front().unwrap(); // Put pool

    let five_tokens: u256 = 5000000000000000000; // with 18 decimals
    let five_k_tokens: u256 = 5000000000; // with 6 decimals

    // Call pool
    assert(cp.pool_info.pool.option_type == 0, 'Call pool wrong type');
    assert(cp.pool_info.pool.quote_token_address == ctx.usdc_address, 'Call pool wrong quote');
    assert(cp.pool_info.pool.base_token_address == ctx.eth_address, 'Call pool wrong base');
    assert(cp.pool_info.lptoken_address == ctx.call_lpt_address, 'Call pool wrong lpt addr');
    assert(cp.pool_info.staked_capital == five_tokens, 'Call pool wrong staked');
    assert(cp.pool_info.unlocked_capital == five_tokens, 'Call pool wrong unlo');
    assert(
        cp.pool_info.value_of_pool_position == FixedTrait::ZERO(), 'Call pool wrong pool pos val'
    );
    assert(cp.value_of_user_stake == five_tokens, 'Call pool wrong user stake');
    assert(cp.size_of_users_tokens == five_tokens, 'Call pool wrong user tokens');

    // Put pool
    assert(pp.pool_info.pool.option_type == 1, 'Put pool wrong type');
    assert(pp.pool_info.pool.quote_token_address == ctx.usdc_address, 'Put pool wrong quote');
    assert(pp.pool_info.pool.base_token_address == ctx.eth_address, 'Put pool wrong base');
    assert(pp.pool_info.lptoken_address == ctx.put_lpt_address, 'Put pool wrong lpt addr');
    assert(pp.pool_info.staked_capital == five_k_tokens, 'Put pool wrong staked');
    assert(pp.pool_info.unlocked_capital == five_k_tokens, 'Put pool wrong unlo');
    assert(
        pp.pool_info.value_of_pool_position == FixedTrait::ZERO(), 'Put pool wrong pool pos val'
    );
    assert(pp.value_of_user_stake == five_k_tokens, 'Put pool wrong user stake');
    assert(pp.size_of_users_tokens == five_k_tokens, 'Put pool wrong user tokens');
}
// TODO: Test for these adter trade functions have been tested
// get_option_with_position_of_user 


