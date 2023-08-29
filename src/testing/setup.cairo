use starknet::ContractAddress;
use option::Option;
use result::Result;
use result::ResultTrait;
use array::ArrayTrait;
use option::OptionTrait;
use debug::PrintTrait;
use traits::{Into, TryInto};

use carmine_protocol::amm_core::amm::{AMM, IAMMDispatcher, IAMMDispatcherTrait };
use snforge_std::{declare, PreparedContract, deploy, start_prank, stop_prank};

use carmine_protocol::tokens::my_token::{MyToken, IMyTokenDispatcher, IMyTokenDispatcherTrait};
use carmine_protocol::tokens::option_token::{OptionToken, IOptionTokenDispatcher, IOptionTokenDispatcherTrait};
use carmine_protocol::tokens::lptoken::{LPToken, ILPTokenDispatcher, ILPTokenDispatcherTrait};

use openzeppelin::token::erc20::ERC20;
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use cubit::f128::types::{Fixed, FixedTrait};

#[derive(Drop, Copy)]
struct Ctx { 
    admin_address: ContractAddress,
    amm_address : ContractAddress,
    eth_address : ContractAddress,
    usdc_address: ContractAddress,
    call_lpt_address: ContractAddress,
    put_lpt_address: ContractAddress,
    
    strike_price: Fixed,
    expiry: u64,

    long_call_address: ContractAddress,
    short_call_address: ContractAddress,

    long_put_address: ContractAddress,
    short_put_address: ContractAddress,
}

#[derive(Drop, Copy)]
struct Dispatchers {
    amm: IAMMDispatcher,
    eth: IMyTokenDispatcher,
    usdc: IMyTokenDispatcher,
    lptc: ILPTokenDispatcher,
    lptp: ILPTokenDispatcher,

    lc: IOptionTokenDispatcher, 
    sc: IOptionTokenDispatcher,
    lp: IOptionTokenDispatcher,
    sp: IOptionTokenDispatcher,
}

// fn deploy_setup() {
fn deploy_setup() -> Ctx {
    let admin_address = 123456;

    let mytoken_hash = declare('MyToken');
    let lptoken_hash = declare('LPToken');
    let amm_hash = declare('AMM');
    let option_token_hash = declare('OptionToken');

    let amm_prepared = PreparedContract {
        class_hash: amm_hash, constructor_calldata: @ArrayTrait::new()
    };
    let amm_address = deploy(amm_prepared).unwrap();

    // Deploy Call ILPT
    let mut call_lpt_data = ArrayTrait::new();
    call_lpt_data.append('CLPT'); // Name
    call_lpt_data.append('CallPool'); //Symbol
    let call_lpt_prepared = PreparedContract {
        class_hash: lptoken_hash, constructor_calldata: @call_lpt_data
    };
    let call_lpt_address = deploy(call_lpt_prepared).unwrap();

    // // Deploy Put ILPT
    let mut put_lpt_data = ArrayTrait::new();
    put_lpt_data.append('PLPT'); // Name
    put_lpt_data.append('PutPool'); // Symbol
    let put_lpt_prepared = PreparedContract {
        class_hash: lptoken_hash, constructor_calldata: @put_lpt_data
    };
    let put_lpt_address = deploy(put_lpt_prepared).unwrap();

    // // Deploy ETH
    let mut eth_constr_data = ArrayTrait::new();
    eth_constr_data.append('eth'); // Name
    eth_constr_data.append('eth'); // Symbol
    eth_constr_data.append(18); // Decimals
    eth_constr_data.append(10000000000000000000); // Initial supply, low, 10 * 10**18
    eth_constr_data.append(0); // Initial supply, high
    eth_constr_data.append(admin_address); // Recipient

    let eth_prepared = PreparedContract {
        class_hash: mytoken_hash, constructor_calldata: @eth_constr_data
    };
    let eth_address = deploy(eth_prepared).unwrap();

    // // Deploy USDC
    let mut usdc_constr_data = ArrayTrait::new();
    usdc_constr_data.append('usdc'); // Name
    usdc_constr_data.append('usdc'); // Symbol
    usdc_constr_data.append(6); // Decimals
    usdc_constr_data.append(10000000000); // Initial supply, low 10_000 * 10**6
    usdc_constr_data.append(0); // Initial supply, high
    usdc_constr_data.append(admin_address); // Recipient

    let usdc_prepared = PreparedContract {
        class_hash: mytoken_hash, constructor_calldata: @usdc_constr_data
    };
    let usdc_address = deploy(usdc_prepared).unwrap();

    // // Deploy Option Tokens

    let strike_price = 27670116110564327424000; // 1500 * 2**64
    let expiry = 1000000000 + 60*60*24; // current time plus 24 hours
    let LONG = 0;
    let SHORT = 1;

    let CALL = 0;
    let PUT = 1;
    
    // Long Call
    let mut long_call_data = ArrayTrait::new();
    long_call_data.append('OptLongCall');
    long_call_data.append('OLC');
    long_call_data.append(usdc_address.into());
    long_call_data.append(eth_address.into());
    long_call_data.append(CALL);
    long_call_data.append(strike_price);
    long_call_data.append(expiry.into());
    long_call_data.append(LONG);

    let long_call_prep = PreparedContract {
        class_hash: option_token_hash, constructor_calldata: @long_call_data
    };
    let long_call_address = deploy(long_call_prep).unwrap();

    // Short Call
    let mut short_call_data = ArrayTrait::new();
    short_call_data.append('OptShortCall');
    short_call_data.append('OSC');
    short_call_data.append(usdc_address.into());
    short_call_data.append(eth_address.into());
    short_call_data.append(CALL);
    short_call_data.append(strike_price);
    short_call_data.append(expiry.into());
    short_call_data.append(SHORT);

    let short_call_prep = PreparedContract {
        class_hash: option_token_hash, constructor_calldata: @short_call_data
    };
    let short_call_address = deploy(short_call_prep).unwrap();

    // Long put
    let mut long_put_data = ArrayTrait::new();
    long_put_data.append('OptLongPut');
    long_put_data.append('OLP');
    long_put_data.append(usdc_address.into());
    long_put_data.append(eth_address.into());
    long_put_data.append(PUT);
    long_put_data.append(strike_price);
    long_put_data.append(expiry.into());
    long_put_data.append(LONG);

    let long_put_prep = PreparedContract {
        class_hash: option_token_hash, constructor_calldata: @long_put_data
    };
    let long_put_address = deploy(long_put_prep).unwrap();

    // Short put
    let mut short_put_data = ArrayTrait::new();
    short_put_data.append('OptShortPut');
    short_put_data.append('OSP');
    short_put_data.append(usdc_address.into());
    short_put_data.append(eth_address.into());
    short_put_data.append(PUT);
    short_put_data.append(strike_price);
    short_put_data.append(expiry.into());
    short_put_data.append(SHORT);

    let short_put_prep = PreparedContract {
        class_hash: option_token_hash, constructor_calldata: @short_put_data
    };
    let short_put_address = deploy(short_put_prep).unwrap();

    let ctx = Ctx {
        admin_address: admin_address.try_into().unwrap(),
        amm_address: amm_address,
        eth_address: eth_address,
        usdc_address: usdc_address,
        call_lpt_address: call_lpt_address,
        put_lpt_address: put_lpt_address,
        strike_price: FixedTrait::from_felt(strike_price),
        expiry: expiry,
        long_call_address: long_call_address,
        short_call_address: short_call_address,
        long_put_address: long_put_address,
        short_put_address: short_put_address,
    };

    let disp = get_dispatchers(ctx);

    let call_vol_adjspd = FixedTrait::from_unscaled_felt(5);
    let put_vol_adjspd = FixedTrait::from_unscaled_felt(5_000);

    // ADD lptokens
    // Call
    disp.amm.add_lptoken(
        ctx.usdc_address,
        ctx.eth_address,
        CALL.try_into().unwrap(),
        ctx.call_lpt_address,
        ctx.eth_address,
        call_vol_adjspd,
        10000000000000000000 // 10eth
    );

    // PUT
    disp.amm.add_lptoken(
        ctx.usdc_address,
        ctx.eth_address,
        PUT.try_into().unwrap(),
        ctx.put_lpt_address,
        ctx.usdc_address,
        put_vol_adjspd,
        10000000000 // 10k usdc
    );

    // Approve bajilion for use by amm
    let bajillion = 0x80000000000000000000000000000000;

    start_prank(ctx.eth_address, ctx.admin_address);
    disp.eth.approve(ctx.amm_address, bajillion);
    stop_prank(ctx.eth_address);

    start_prank(ctx.usdc_address, ctx.admin_address);
    disp.usdc.approve(ctx.amm_address, bajillion);
    stop_prank(ctx.usdc_address);
    
    // Deposit 5eth and 5k usdc liquidity
    start_prank(ctx.amm_address, ctx.admin_address);
    disp.amm.set_max_option_size_percent_of_voladjspd(1_000); // Basically turn this off

    let five_eth = 5000000000000000000;
    let five_k_usdc = 5000000000;

    // ETH
    disp.amm.deposit_liquidity(
        ctx.eth_address,
        ctx.usdc_address,
        ctx.eth_address,
        CALL.try_into().unwrap(),
        five_eth
    );

    // Put
    disp.amm.deposit_liquidity(
        ctx.usdc_address,
        ctx.usdc_address,
        ctx.eth_address,
        PUT.try_into().unwrap(),
        five_k_usdc,
    );

    assert(disp.lptc.balance_of(ctx.admin_address) == five_eth, 'Wher call lpt');
    assert(disp.lptp.balance_of(ctx.admin_address) == five_k_usdc, 'Wher put lpt');

    // Add Options
    let hundred = FixedTrait::from_unscaled_felt(100);

    // Long call
    disp.amm.add_option(
        LONG.try_into().unwrap(),
        ctx.expiry,
        ctx.strike_price,
        ctx.usdc_address,
        ctx.eth_address,
        CALL.try_into().unwrap(),
        ctx.call_lpt_address,
        ctx.long_call_address,
        hundred
    );
    // Short call
    disp.amm.add_option(
        SHORT.try_into().unwrap(),
        ctx.expiry,
        ctx.strike_price,
        ctx.usdc_address,
        ctx.eth_address,
        CALL.try_into().unwrap(),
        ctx.call_lpt_address,
        ctx.short_call_address,
        hundred
    );
    // Long put
    disp.amm.add_option(
        LONG.try_into().unwrap(),
        ctx.expiry,
        ctx.strike_price,
        ctx.usdc_address,
        ctx.eth_address,
        PUT.try_into().unwrap(),
        ctx.put_lpt_address,
        ctx.long_put_address,
        hundred
    );
    // Short call
    disp.amm.add_option(
        SHORT.try_into().unwrap(),
        ctx.expiry,
        ctx.strike_price,
        ctx.usdc_address,
        ctx.eth_address,
        PUT.try_into().unwrap(),
        ctx.put_lpt_address,
        ctx.short_put_address,
        hundred
    );
    
    ctx
}

fn get_dispatchers(ctx: Ctx) -> Dispatchers {
    Dispatchers {
        amm: IAMMDispatcher{contract_address: ctx.amm_address},
        eth: IMyTokenDispatcher{contract_address: ctx.eth_address},
        usdc: IMyTokenDispatcher{contract_address: ctx.usdc_address},
        lptc: ILPTokenDispatcher{contract_address: ctx.call_lpt_address},
        lptp: ILPTokenDispatcher{contract_address: ctx.put_lpt_address},

        lc: IOptionTokenDispatcher{contract_address: ctx.long_call_address},
        sc: IOptionTokenDispatcher{contract_address: ctx.short_call_address},

        lp: IOptionTokenDispatcher{contract_address: ctx.long_put_address},
        sp: IOptionTokenDispatcher{contract_address: ctx.short_put_address},
    }
}

// #[test]
// fn test_deploy_setup() {
//     let ctx = deploy_setup();
//     let disp = get_dispatchers(ctx);
// }
