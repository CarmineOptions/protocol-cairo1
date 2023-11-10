use starknet::ContractAddress;
use cubit::f128::types::fixed::{Fixed, FixedTrait};
use carmine_protocol::testing::setup::{Ctx, Dispatchers};
use debug::PrintTrait;
use carmine_protocol::tokens::my_token::{MyToken, IMyTokenDispatcher, IMyTokenDispatcherTrait};
use carmine_protocol::tokens::option_token::{
    OptionToken, IOptionTokenDispatcher, IOptionTokenDispatcherTrait
};
use carmine_protocol::tokens::lptoken::{LPToken, ILPTokenDispatcher, ILPTokenDispatcherTrait};

use carmine_protocol::amm_core::amm::{IAMMDispatcher, IAMMDispatcherTrait};


// Helper function for relative comparison of two numbers
// TODO: Is this correct?
fn is_close(a: Fixed, b: Fixed, rel_tol: Fixed) -> bool {
    let tmp = (a - b).abs() / b;

    if tmp <= rel_tol {
        true
    } else {
        false
    }
}

#[derive(Drop, Copy)]
struct Stats {
    bal_lpt_c: u256,
    bal_lpt_p: u256,
    bal_opt_lc: u256,
    bal_opt_sc: u256,
    bal_opt_lp: u256,
    bal_opt_sp: u256,
    bal_eth: u256,
    bal_usdc: u256,
    lpool_balance_c: u256,
    lpool_balance_p: u256,
    unlocked_capital_c: u256,
    unlocked_capital_p: u256,
    locked_capital_c: u256,
    locked_capital_p: u256,
    pool_pos_val_c: Fixed,
    pool_pos_val_p: Fixed,
    volatility_c: Fixed,
    volatility_p: Fixed,
    opt_pos_lc: u128,
    opt_pos_sc: u128,
    opt_pos_lp: u128,
    opt_pos_sp: u128,
}

#[generate_trait]
impl StatsImpl of StatsTrait {
    fn new(ctx: Ctx, dsps: Dispatchers) -> Stats {
        let opt_pos_lc = dsps
            .amm
            .get_option_position(ctx.call_lpt_address, 0, ctx.expiry, ctx.strike_price);

        let opt_pos_sc = dsps
            .amm
            .get_option_position(ctx.call_lpt_address, 1, ctx.expiry, ctx.strike_price);
        let opt_pos_lp = dsps
            .amm
            .get_option_position(ctx.put_lpt_address, 0, ctx.expiry, ctx.strike_price);
        let opt_pos_sp = dsps
            .amm
            .get_option_position(ctx.put_lpt_address, 1, ctx.expiry, ctx.strike_price);

        Stats {
            bal_lpt_c: dsps.lptc.balanceOf(ctx.admin_address),
            bal_lpt_p: dsps.lptp.balanceOf(ctx.admin_address),
            bal_opt_lc: dsps.lc.balanceOf(ctx.admin_address),
            bal_opt_sc: dsps.sc.balanceOf(ctx.admin_address),
            bal_opt_lp: dsps.lp.balanceOf(ctx.admin_address),
            bal_opt_sp: dsps.sp.balanceOf(ctx.admin_address),
            bal_eth: dsps.eth.balance_of(ctx.admin_address),
            bal_usdc: dsps.usdc.balance_of(ctx.admin_address),
            lpool_balance_c: dsps.amm.get_lpool_balance(ctx.call_lpt_address),
            lpool_balance_p: dsps.amm.get_lpool_balance(ctx.put_lpt_address),
            unlocked_capital_c: dsps.amm.get_unlocked_capital(ctx.call_lpt_address),
            unlocked_capital_p: dsps.amm.get_unlocked_capital(ctx.put_lpt_address),
            locked_capital_c: dsps.amm.get_pool_locked_capital(ctx.call_lpt_address),
            locked_capital_p: dsps.amm.get_pool_locked_capital(ctx.put_lpt_address),
            pool_pos_val_c: dsps.amm.get_value_of_pool_position(ctx.call_lpt_address),
            pool_pos_val_p: dsps.amm.get_value_of_pool_position(ctx.put_lpt_address),
            opt_pos_lc: opt_pos_lc,
            opt_pos_sc: opt_pos_sc,
            opt_pos_lp: opt_pos_lp,
            opt_pos_sp: opt_pos_sp,
            volatility_c: dsps
                .amm
                .get_option_volatility(ctx.call_lpt_address, ctx.expiry, ctx.strike_price),
            volatility_p: dsps
                .amm
                .get_option_volatility(ctx.put_lpt_address, ctx.expiry, ctx.strike_price),
        }
    }
}

// impl FixedBalancePrint of PrintTrait<FixedBalance> {
//     fn print(self: FixedBalance) {
//         self.balance.print();
//         self.decimals.print();
//         self.address.print();
//     }
// }

impl StatsPrint of PrintTrait<Stats> {
    fn print(self: Stats) {
        'Balance LPT c/p: '.print();
        self.bal_lpt_c.low.print();
        self.bal_lpt_p.low.print();

        'Balance OPT lc/sc/lp/sp: '.print();
        self.bal_opt_lc.low.print();
        self.bal_opt_sc.low.print();
        self.bal_opt_lp.low.print();
        self.bal_opt_sp.low.print();

        'Bal eth/usdc'.print();
        self.bal_eth.low.print();
        self.bal_usdc.low.print();

        'Lpool bal c/p'.print();
        self.lpool_balance_c.low.print();
        self.lpool_balance_p.low.print();

        'Unlocked cap c/p'.print();
        self.unlocked_capital_c.low.print();
        self.unlocked_capital_p.low.print();

        'Locked cap c/p'.print();
        self.locked_capital_c.low.print();
        self.locked_capital_p.low.print();

        'Pool pos val c/p'.print();
        self.pool_pos_val_c.print();
        self.pool_pos_val_p.print();

        'Vol c/p'.print();
        self.volatility_c.print();
        self.volatility_p.print();

        'OPT ps lc/sc/lp/sp'.print();
        self.opt_pos_lc.print();
        self.opt_pos_sc.print();
        self.opt_pos_lp.print();
        self.opt_pos_sp.print();
    }
}
