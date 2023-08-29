// run them in one single test

use option::OptionTrait;

use carmine_protocol::amm_core::view::View;
use carmine_protocol::testing::setup::deploy_setup;
use array::ArrayTrait;
use debug::PrintTrait;
use carmine_protocol::amm_core::amm::IAMMDispatcherTrait;
use carmine_protocol::types::option_::{Option_Trait, Option_};

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
// TODO: Test for these (bug still present)
// get_all_non_expired_options_with_premia 
// get_option_with_position_of_user 
// get_user_pool_infos
// get_total_premia
// #[test]
// fn test_get_all_poolinfo() {
//     let (ctx, dsps) = deploy_setup();
//     let pool_infos = dsps.amm.get_all_poolinfo();
//     assert(pool_infos.len() == 2, 'Num of poolinfos wrong');
//     let call_lpt = pool_infos.pop_front().unwrap();   
//     let put_lpt = pool_infos.pop_front().unwrap();   
// }


