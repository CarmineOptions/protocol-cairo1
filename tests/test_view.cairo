// run them in one single test

use starknet::ContractAddress;
use carmine_protocol::amm_core::view::View;
use carmine_protocol::testing::setup::deploy_setup;
use array::ArrayTrait;
use debug::PrintTrait;
use carmine_protocol::amm_core::amm::IAMMDispatcherTrait;
use carmine_protocol::types::option_::{Option_Trait, Option_};
use cubit::f128::types::{Fixed, FixedTrait};
use snforge_std::{start_prank, stop_prank, start_warp, stop_warp, start_mock_call, stop_mock_call};
use traits::{TryInto, Into};
use option::OptionTrait;

use carmine_protocol::amm_core::oracles::pragma::Pragma::PRAGMA_ORACLE_ADDRESS;


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
// option_side: OptionSide,
// maturity: Timestamp,
// strike_price: Fixed,
// quote_token_address: ContractAddress,
// base_token_address: ContractAddress,
// option_type: OptionType

// fn get_total_premia(
//     self: @TContractState, option: Option_, position_size: u256, is_closing: bool
// ) -> (Fixed, Fixed);

// #[test]
// fn test_get_total_premia () {
//     let (ctx, dsps) = deploy_setup();

//     let one = 1000000000000000000;

//     let option_long_call = Option_ {
//         option_side: 0,
//         maturity: ctx.expiry, 
//         strike_price: ctx.strike_price,
//         quote_token_address: ctx.usdc_address,
//         base_token_address: ctx.eth_address,
//         option_type: 0
//     };

//     let option_short_call = Option_ {
//         option_side: 1,
//         maturity: ctx.expiry, 
//         strike_price: ctx.strike_price,
//         quote_token_address: ctx.usdc_address,
//         base_token_address: ctx.eth_address,
//         option_type: 0
//     };

//     let option_long_put = Option_ {
//         option_side: 0,
//         maturity: ctx.expiry, 
//         strike_price: ctx.strike_price,
//         quote_token_address: ctx.usdc_address,
//         base_token_address: ctx.eth_address,
//         option_type: 1
//     };

//     let option_short_put = Option_ {
//         option_side: 0,
//         maturity: ctx.expiry, 
//         strike_price: ctx.strike_price,
//         quote_token_address: ctx.usdc_address,
//         base_token_address: ctx.eth_address,
//         option_type: 1
//     };

//     start_prank(ctx.amm_address, ctx.admin_address);
//     start_warp(ctx.amm_address, 1000000000 + 60*60*12);
//     start_mock_call(PRAGMA_ORACLE_ADDRESS.try_into().unwrap(), 'get_spot_median', (140000000000, 8, 1000000000 + 60*60*12, 0));

//     let (
//         total_premia_before_fees_long_call,
//         total_premia_including_fees_long_call
//     )  = dsps.amm.get_total_premia(
//         option_long_call, one, false
//     );

// let (
//     total_premia_before_fees_short_call,
//     total_premia_including_fees_short_call
// )  = dsps.amm.get_total_premia(
//     option_short_call, one, false
// );

// let (
//     total_premia_before_fees_long_put,
//     total_premia_including_fees_long_put
// )  = dsps.amm.get_total_premia(
//     option_long_put, one, false
// );

// let (
//     total_premia_before_fees_short_put,
//     total_premia_including_fees_short_put
// )  = dsps.amm.get_total_premia(
//     option_short_put, one, false
// );

// total_premia_before_fees_long_call.print();
// total_premia_including_fees_long_call.print();
// }

// get_total_premia

// TODO: Test for these (bug still present)
// get_all_non_expired_options_with_premia 
// get_option_with_position_of_user 
// get_user_pool_infos


