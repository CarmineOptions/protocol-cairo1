use array::ArrayTrait;
use core::traits::TryInto;
use debug::PrintTrait;
use snforge_std::{
    BlockId, declare, ContractClassTrait, ContractClass, start_prank, start_warp, stop_prank,
    start_mock_call, start_roll, stop_roll
};
use starknet::{ContractAddress, get_block_timestamp, get_block_info, ClassHash};
use cubit::f128::types::fixed::{Fixed, FixedTrait};

use carmine_protocol::amm_core::oracles::pragma::Pragma::PRAGMA_ORACLE_ADDRESS;
use carmine_protocol::amm_core::oracles::pragma::PragmaUtils::{
    PragmaPricesResponse, Checkpoint, AggregationMode
};
use carmine_protocol::amm_core::oracles::agg::OracleAgg;

use carmine_protocol::amm_interface::IAMM;
use carmine_protocol::amm_interface::IAMMDispatcher;
use carmine_protocol::amm_interface::IAMMDispatcherTrait;
use carmine_protocol::amm_core::state::State::{get_option_token_address, get_available_options};

use carmine_protocol::erc20_interface::IERC20;
use carmine_protocol::erc20_interface::IERC20Dispatcher;
use carmine_protocol::erc20_interface::IERC20DispatcherTrait;
use carmine_protocol::types::basic::{OptionType, OptionSide};

use carmine_protocol::amm_core::constants::TOKEN_EKUBO_ADDRESS;
use carmine_protocol::amm_core::constants::TOKEN_USDC_ADDRESS;

use carmine_protocol::amm_core::constants::OPTION_CALL;
use carmine_protocol::amm_core::constants::OPTION_PUT;

use carmine_protocol::amm_core::constants::TRADE_SIDE_LONG;
use carmine_protocol::amm_core::constants::TRADE_SIDE_SHORT;

use carmine_protocol::oz::access::interface::IOwnable;
use carmine_protocol::oz::access::interface::IOwnableDispatcher;
use carmine_protocol::oz::access::interface::IOwnableDispatcherTrait;

/// TODO:
/// [x] Add lpools
/// [x] Add options
/// [x] Add liquidity to both pools
/// [x] Trade options
/// [x] Close options
/// [x] Settle options

fn EKUBO_WHALE() -> ContractAddress {
    0x02a3ed03046e1042e193651e3da6d3c973e3d45c624442be936a374380a78bb5.try_into().unwrap()
}

fn USDC_WHALE() -> ContractAddress {
    0x00000005dd3d2f4429af886cd1a3b08289dbcea99a294197e9eb43b0e0325b4b.try_into().unwrap()
}


#[test]
#[fork("MAINNET")]
fn test_add_ekubo_options() {
    let amm_contract_addr: ContractAddress =
        0x047472e6755afc57ada9550b6a3ac93129cc4b5f98f51c73e0644d129fd208d9
        .try_into()
        .unwrap();
    let amm = IAMMDispatcher { contract_address: amm_contract_addr };
    let owner = IOwnableDispatcher { contract_address: amm_contract_addr }.owner();

    // Add ekubo lpools
    let (ekubo_call_lpt, ekubo_put_lpt) = add_ekubo_lpools(amm_contract_addr, owner);

    // Let's pretend that now is one week ago so that we 
    // dont have to deal with pragma price being too old
    // when setting checkpoints for expirying options
    let expiry = get_block_timestamp();
    let now = expiry - 7 * 86_400; // + week
    
    let strike_price = 46116860184273879040; // 2.5 * 2**64
    start_warp(amm_contract_addr, now);
    deploy_and_add_ekubo_options(
        amm_contract_addr, ekubo_call_lpt, ekubo_put_lpt, expiry, strike_price
    );
    let strike_fixed = FixedTrait::new(strike_price.try_into().unwrap(), false);

    // Try to fetch price for ekubo
    let base_token: ContractAddress = TOKEN_EKUBO_ADDRESS.try_into().unwrap();
    let quote_token: ContractAddress = TOKEN_USDC_ADDRESS.try_into().unwrap();
    let price = amm.get_current_price(quote_token, base_token,);

    let TEN_K_EKUBO: u256 = 100000000000000000000000;
    let TEN_K_USDC: u256 = 10000000000;

    let ekubo_token = IERC20Dispatcher { contract_address: base_token };
    let usdc_token = IERC20Dispatcher { contract_address: quote_token };

    assert(price != FixedTrait::ZERO(), 'Ekubo price is zero');

    // Add liquidity to ekubo call pool
    start_prank(base_token, EKUBO_WHALE());
    ekubo_token.approve(amm_contract_addr, TEN_K_EKUBO);
    stop_prank(base_token);

    start_prank(amm_contract_addr, EKUBO_WHALE());
    amm.deposit_liquidity(base_token, quote_token, base_token, OPTION_CALL, TEN_K_EKUBO);
    stop_prank(amm_contract_addr);

    // Add liquidity to ekubo put pool
    start_prank(quote_token, USDC_WHALE());
    usdc_token.approve(amm_contract_addr, TEN_K_EKUBO);
    stop_prank(quote_token);

    start_prank(amm_contract_addr, USDC_WHALE());
    amm.deposit_liquidity(quote_token, quote_token, base_token, OPTION_PUT, TEN_K_USDC);
    stop_prank(amm_contract_addr);

    assert(amm.get_lpool_balance(ekubo_call_lpt) == TEN_K_EKUBO, 'wrong clpool bal');
    assert(amm.get_lpool_balance(ekubo_put_lpt) == TEN_K_USDC, 'wrong plpool bal');

    assert(amm.get_unlocked_capital(ekubo_call_lpt) == TEN_K_EKUBO, 'wrong clpool bal');
    assert(amm.get_unlocked_capital(ekubo_put_lpt) == TEN_K_USDC, 'wrong plpool bal');

    assert(amm.get_unlocked_capital(ekubo_call_lpt) == TEN_K_EKUBO, 'wrong c unlocked');
    assert(amm.get_unlocked_capital(ekubo_put_lpt) == TEN_K_USDC, 'wrong p unlocked');

    assert(amm.get_pool_locked_capital(ekubo_call_lpt) == 0, 'wrong c locked');
    assert(amm.get_pool_locked_capital(ekubo_put_lpt) == 0, 'wrong p locked');

    // Do some trades
    start_prank(base_token, EKUBO_WHALE());
    ekubo_token.approve(amm_contract_addr, TEN_K_EKUBO);
    stop_prank(base_token);

    start_prank(amm_contract_addr, EKUBO_WHALE());
    let long_call_premia = amm
        .trade_open(
            OPTION_CALL,
            strike_fixed,
            expiry,
            TRADE_SIDE_LONG,
            (TEN_K_EKUBO / 100).try_into().unwrap(),
            quote_token,
            base_token,
            FixedTrait::new_unscaled(1_000_000, false),
            expiry
        );
    stop_prank(amm_contract_addr);

    start_prank(quote_token, USDC_WHALE());
    usdc_token.approve(amm_contract_addr, TEN_K_EKUBO);
    stop_prank(quote_token);

    start_prank(amm_contract_addr, USDC_WHALE());
    let long_put_premia = amm
        .trade_open(
            OPTION_PUT,
            strike_fixed,
            expiry,
            TRADE_SIDE_LONG,
            (TEN_K_EKUBO / 100).try_into().unwrap(),
            quote_token,
            base_token,
            FixedTrait::new_unscaled(1_000_000, false),
            expiry
        );
    stop_prank(amm_contract_addr);

    start_warp(amm_contract_addr, now + 86_400);
    // Close options

    start_prank(amm_contract_addr, EKUBO_WHALE());
    let _ = amm
        .trade_close(
            OPTION_CALL,
            strike_fixed,
            expiry,
            TRADE_SIDE_LONG,
            (TEN_K_EKUBO / 100).try_into().unwrap(),
            quote_token,
            base_token,
            FixedTrait::new(1, false),
            expiry
        );
    stop_prank(amm_contract_addr);

    start_prank(amm_contract_addr, USDC_WHALE());
    let _ = amm
        .trade_close(
            OPTION_PUT,
            strike_fixed,
            expiry,
            TRADE_SIDE_LONG,
            (TEN_K_EKUBO / 100).try_into().unwrap(),
            quote_token,
            base_token,
            FixedTrait::new(1, false),
            expiry
        );
    stop_prank(amm_contract_addr);

    // Open again so we have some
    start_prank(amm_contract_addr, EKUBO_WHALE());
    let _ = amm
        .trade_open(
            OPTION_CALL,
            strike_fixed,
            expiry,
            TRADE_SIDE_LONG,
            (TEN_K_EKUBO / 100).try_into().unwrap(),
            quote_token,
            base_token,
            FixedTrait::new_unscaled(1_000_000, false),
            expiry
        );
    stop_prank(amm_contract_addr);

    start_prank(quote_token, USDC_WHALE());
    usdc_token.approve(amm_contract_addr, TEN_K_EKUBO);
    stop_prank(quote_token);

    start_prank(amm_contract_addr, USDC_WHALE());
    let _ = amm
        .trade_open(
            OPTION_PUT,
            strike_fixed,
            expiry,
            TRADE_SIDE_LONG,
            (TEN_K_EKUBO / 100).try_into().unwrap(),
            quote_token,
            base_token,
            FixedTrait::new_unscaled(1_000_000, false),
            expiry
        );
    stop_prank(amm_contract_addr);

    // jump to expiry and set checkpoints
    start_warp(amm_contract_addr, expiry - 1);
    amm.set_pragma_required_checkpoints();

    // Expire options
    start_warp(amm_contract_addr, expiry + 1);

    // Calls
    amm.expire_option_token_for_pool(
        ekubo_call_lpt,
        TRADE_SIDE_LONG,
        strike_fixed,
        expiry
    );
    amm.expire_option_token_for_pool(
        ekubo_call_lpt,
        TRADE_SIDE_SHORT,
        strike_fixed,
        expiry
    );

    
    // Puts
    amm.expire_option_token_for_pool(
        ekubo_put_lpt,
        TRADE_SIDE_LONG,
        strike_fixed,
        expiry
    );
    amm.expire_option_token_for_pool(
        ekubo_put_lpt,
        TRADE_SIDE_SHORT,
        strike_fixed,
        expiry
    );

    assert(amm.get_option_position( ekubo_put_lpt, TRADE_SIDE_SHORT, expiry, strike_fixed,) == 0, 'Should be no put short');
    assert(amm.get_option_position( ekubo_put_lpt, TRADE_SIDE_LONG, expiry, strike_fixed,) == 0, 'Should be no put long');

    assert(amm.get_option_position( ekubo_call_lpt, TRADE_SIDE_SHORT, expiry, strike_fixed,) == 0, 'Should be no call short');
    assert(amm.get_option_position( ekubo_call_lpt, TRADE_SIDE_LONG, expiry, strike_fixed,) == 0, 'Should be no call long');


    // Settle
    start_prank(amm_contract_addr, EKUBO_WHALE());
    amm.trade_settle(
        OPTION_CALL,
        strike_fixed,
        expiry,
        TRADE_SIDE_LONG,
        (TEN_K_EKUBO / 100).try_into().unwrap(),
        quote_token,
        base_token
    );
    stop_prank(amm_contract_addr);

    start_prank(amm_contract_addr, USDC_WHALE());
    amm.trade_settle(
        OPTION_PUT,
        strike_fixed,
        expiry,
        TRADE_SIDE_LONG,
        (TEN_K_EKUBO / 100).try_into().unwrap(),
        quote_token,
        base_token
    );
    stop_prank(amm_contract_addr);
    
}


fn deploy_and_add_ekubo_options(
    amm_address: ContractAddress,
    call_lpt: ContractAddress,
    put_lpt: ContractAddress,
    expiry: u64,
    strike_price: felt252
) {
    let amm = IAMMDispatcher { contract_address: amm_address };
    let owner = IOwnableDispatcher { contract_address: amm_address }.owner();

    let option_token_contract = declare('OptionToken');

    let mut long_call_data = ArrayTrait::new();
    long_call_data.append('OptLongCall');
    long_call_data.append('OLC');
    long_call_data.append(amm_address.into());
    long_call_data.append(TOKEN_USDC_ADDRESS);
    long_call_data.append(TOKEN_EKUBO_ADDRESS);
    long_call_data.append(OPTION_CALL.into());
    long_call_data.append(strike_price);
    long_call_data.append(expiry.into());
    long_call_data.append(TRADE_SIDE_LONG.into());
    let long_call_address = option_token_contract.deploy(@long_call_data).unwrap();

    // // Short Call
    let mut short_call_data = ArrayTrait::new();
    short_call_data.append('OptShortCall');
    short_call_data.append('OSC');
    short_call_data.append(amm_address.into());
    short_call_data.append(TOKEN_USDC_ADDRESS);
    short_call_data.append(TOKEN_EKUBO_ADDRESS);
    short_call_data.append(OPTION_CALL.into());
    short_call_data.append(strike_price);
    short_call_data.append(expiry.into());
    short_call_data.append(TRADE_SIDE_SHORT.into());
    let short_call_address = option_token_contract.deploy(@short_call_data).unwrap();

    // // Long put
    let mut long_put_data = ArrayTrait::new();
    long_put_data.append('OptLongPut');
    long_put_data.append('OLP');
    long_put_data.append(amm_address.into());
    long_put_data.append(TOKEN_USDC_ADDRESS);
    long_put_data.append(TOKEN_EKUBO_ADDRESS);
    long_put_data.append(OPTION_PUT.into());
    long_put_data.append(strike_price);
    long_put_data.append(expiry.into());
    long_put_data.append(TRADE_SIDE_LONG.into());
    let long_put_address = option_token_contract.deploy(@long_put_data).unwrap();

    // // Short put
    let mut short_put_data = ArrayTrait::new();
    short_put_data.append('OptShortPut');
    short_put_data.append('OSP');
    short_put_data.append(amm_address.into());
    short_put_data.append(TOKEN_USDC_ADDRESS);
    short_put_data.append(TOKEN_EKUBO_ADDRESS);
    short_put_data.append(OPTION_PUT.into());
    short_put_data.append(strike_price);
    short_put_data.append(expiry.into());
    short_put_data.append(TRADE_SIDE_SHORT.into());
    let short_put_address = option_token_contract.deploy(@short_put_data).unwrap();

    let init_vol = FixedTrait::from_unscaled_felt(100);

    start_prank(amm_address, owner);

    let base_token: ContractAddress = TOKEN_EKUBO_ADDRESS.try_into().unwrap();
    let quote_token: ContractAddress = TOKEN_USDC_ADDRESS.try_into().unwrap();

    // Calls
    amm
        .add_option_both_sides(
            expiry,
            FixedTrait::new(strike_price.try_into().unwrap(), false),
            quote_token,
            base_token,
            OPTION_CALL,
            call_lpt,
            long_call_address,
            short_call_address,
            init_vol
        );

    // Puts
    amm
        .add_option_both_sides(
            expiry,
            FixedTrait::new(strike_price.try_into().unwrap(), false),
            quote_token,
            base_token,
            OPTION_PUT,
            put_lpt,
            long_put_address,
            short_put_address,
            init_vol
        );

    stop_prank(amm_address);

    assert(amm.get_all_options(call_lpt).len() == 2, 'Wrong amount of calls');
    assert(amm.get_all_options(put_lpt).len() == 2, 'Wrong amount of puts');
}


fn add_ekubo_lpools(
    amm_contract_addr: ContractAddress, owner: ContractAddress
) -> (ContractAddress, ContractAddress) {
    let amm = IAMMDispatcher { contract_address: amm_contract_addr };
    // Upgrade amm
    start_prank(amm_contract_addr, owner);
    let new_amm_hash = declare('AMM');
    amm.upgrade(new_amm_hash.class_hash);
    stop_prank(amm_contract_addr);

    let (ekubo_call_lpt, ekubo_put_lpt) = deploy_ekubo_lptokens(amm_contract_addr);

    /////////////////////////////////////////////
    /// Adding New lptokens to amm
    /////////////////////////////////////////////

    let base_token: ContractAddress = TOKEN_EKUBO_ADDRESS.try_into().unwrap();
    let quote_token: ContractAddress = TOKEN_USDC_ADDRESS.try_into().unwrap();
    let max_bal =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;

    let lptokens_before = amm.get_all_lptoken_addresses();

    start_prank(amm_contract_addr, owner);
    // Adding Call
    amm
        .add_lptoken(
            quote_token,
            base_token,
            OPTION_CALL,
            ekubo_call_lpt,
            FixedTrait::new(184467440737095516160000, false), // 10k
            max_bal
        );

    // Adding Put
    amm
        .add_lptoken(
            quote_token,
            base_token,
            OPTION_PUT,
            ekubo_put_lpt,
            FixedTrait::new(922337203685477580800000, false), // 50k
            max_bal
        );

    stop_prank(amm_contract_addr);

    let lptokens_after = amm.get_all_lptoken_addresses();

    assert(lptokens_before.len() + 2 == lptokens_after.len(), 'Lptokens lost');
    assert(*lptokens_after.at(lptokens_before.len()) == ekubo_call_lpt, 'Call missing');
    assert(*lptokens_after.at(lptokens_before.len() + 1) == ekubo_put_lpt, 'Put missing');

    (ekubo_call_lpt, ekubo_put_lpt)
}


fn deploy_ekubo_lptokens(amm: ContractAddress) -> (ContractAddress, ContractAddress) {
    let lptoken_hash = declare('LPToken');

    let sth: felt252 = lptoken_hash.class_hash.into();

    let mut call_lpt_data = ArrayTrait::new();
    call_lpt_data.append('Ekubo-Call-LPT'); // Name 
    call_lpt_data.append('EU-C-LPT'); //  Symbol
    call_lpt_data.append(amm.into()); // Owner
    let call_lpt_address = lptoken_hash.deploy(@call_lpt_data).unwrap();

    let mut put_lpt_data = ArrayTrait::new();
    put_lpt_data.append('Ekubo-Put-LPT'); // Name 
    put_lpt_data.append('EU-P-LPT'); //  Symbol
    put_lpt_data.append(amm.into()); // Owner
    let put_lpt_address = lptoken_hash.deploy(@put_lpt_data).unwrap();

    (call_lpt_address, put_lpt_address)
}
