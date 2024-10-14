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

// #[test]
// #[fork("MAINNET")]
fn test_amm_deposit_withdraw_liquidity() {
    // Replace with your actual AMM contract address on mainnet
    let amm_contract_addr: ContractAddress =
        0x047472e6755afc57ada9550b6a3ac93129cc4b5f98f51c73e0644d129fd208d9
        .try_into()
        .unwrap();
    let amm = IAMMDispatcher { contract_address: amm_contract_addr };

    let deployer: ContractAddress =
        0x074fd7da23e21f0f0479adb435221b23f57ca4c32a0c68aad9409a41c27f3067
        .try_into()
        .unwrap();

    let new_class_hash: ClassHash =
        0x07a57625ddc2fbcca39c30a13c04fdcbc7d7c25ff7a66703666392dc0de1e88f
        .try_into()
        .unwrap();

    start_prank(amm_contract_addr, deployer);
    amm.upgrade(new_class_hash);
    stop_prank(amm_contract_addr);

    // Test parameters
    let quote_token_address: ContractAddress =
        0x53c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8
        .try_into()
        .unwrap();
    let base_token_address: ContractAddress =
        0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7
        .try_into()
        .unwrap();

    let whale_address: ContractAddress =
        0x053e1987bbc5f997a09760269774bfc6b7089cdac24459dc6976a08f186088c3
        .try_into()
        .unwrap();

    let option_type: OptionType = 1_u8;

    let lptoken_address = amm
        .get_lptoken_address_for_given_option(quote_token_address, base_token_address, option_type);

    // 1. Deposit liquidity
    // get balance before deposit
    let lp_balance = amm.get_lpool_balance(lptoken_address);

    // Amount to deposit (e.g., 10 USDC)
    let deposit_amount: u256 = 10_000_000;
    start_prank(quote_token_address, whale_address);
    let usdc = IERC20Dispatcher { contract_address: quote_token_address };
    usdc.approve(amm_contract_addr, deposit_amount);
    stop_prank(quote_token_address);

    // Deposit liquidity
    start_prank(amm_contract_addr, whale_address);
    amm
        .deposit_liquidity(
            quote_token_address,
            quote_token_address,
            base_token_address,
            option_type,
            deposit_amount
        );
    stop_prank(amm_contract_addr);

    // get balance after deposit
    let post_deposit_lp_balance = amm.get_lpool_balance(lptoken_address);
    assert(post_deposit_lp_balance - lp_balance == deposit_amount, 'unsuccessful deposit');

    // 2. Withdraw liquidity.
    // roll block to avoid sandwich guard
    let curr_block = get_block_info().unbox().block_number;
    start_roll(lptoken_address, curr_block + 1);

    // Withdraw liquidity
    let withdraw_amount: u256 = 5_000_000;
    start_prank(amm_contract_addr, whale_address);
    amm
        .withdraw_liquidity(
            quote_token_address,
            quote_token_address,
            base_token_address,
            option_type,
            withdraw_amount
        );
    stop_prank(amm_contract_addr);
    stop_roll(lptoken_address);
    let post_withdrawal_lp_balance = amm.get_lpool_balance(lptoken_address);
    assert(post_deposit_lp_balance > post_withdrawal_lp_balance, 'unsuccessful withdrawal.');
    assert(
        post_deposit_lp_balance - post_withdrawal_lp_balance > withdraw_amount,
        'withdrawal is too low.'
    );
}


// #[test]
// #[fork("MAINNET")]
fn test_amm_open_close_trade() {
    // Replace with your actual AMM contract address on mainnet
    let amm_contract_addr: ContractAddress =
        0x047472e6755afc57ada9550b6a3ac93129cc4b5f98f51c73e0644d129fd208d9
        .try_into()
        .unwrap();
    let amm = IAMMDispatcher { contract_address: amm_contract_addr };

    let deployer: ContractAddress =
        0x074fd7da23e21f0f0479adb435221b23f57ca4c32a0c68aad9409a41c27f3067
        .try_into()
        .unwrap();

    let new_class_hash: ClassHash =
        0x07a57625ddc2fbcca39c30a13c04fdcbc7d7c25ff7a66703666392dc0de1e88f
        .try_into()
        .unwrap();

    start_prank(amm_contract_addr, deployer);
    amm.upgrade(new_class_hash);
    stop_prank(amm_contract_addr);

    // Test parameters
    let quote_token_address: ContractAddress =
        0x53c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8
        .try_into()
        .unwrap();
    let base_token_address: ContractAddress =
        0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7
        .try_into()
        .unwrap();

    let whale_address: ContractAddress =
        0x053e1987bbc5f997a09760269774bfc6b7089cdac24459dc6976a08f186088c3
        .try_into()
        .unwrap();

    let option_type: OptionType = 1_u8;
    let lptoken_address = amm
        .get_lptoken_address_for_given_option(quote_token_address, base_token_address, option_type);

    // Open trade
    let strike_price = FixedTrait::from_felt(51650883406386744524800); // 2800
    let maturity = 1723161599_u64;
    let option_size = 100_000_000_000_000_000_u128; // 0.1 ETH
    let limit_total_premia = FixedTrait::from_felt(11068046444225730969600); // 600
    let tx_deadline = get_block_timestamp() + 30;

    // approve
    start_prank(quote_token_address, whale_address);
    let value_to_approve = 650_000_000_u256;
    let usdc = IERC20Dispatcher { contract_address: quote_token_address };
    usdc.approve(amm_contract_addr, value_to_approve);
    stop_prank(quote_token_address);

    let approved_amount = usdc.allowance(whale_address, amm_contract_addr);

    // get initial balance of option tokens
    let option_token_address = amm
        .get_option_token_address(lptoken_address, 0_u8, // LONG position
         maturity, strike_price);
    let option_token = IERC20Dispatcher { contract_address: option_token_address };
    let initial_option_balance = option_token.balanceOf(whale_address);

    // 1. Open trade
    start_prank(amm_contract_addr, whale_address);
    start_prank(lptoken_address, whale_address);
    let trade_open_premia = amm
        .trade_open(
            1_u8,
            strike_price,
            maturity,
            0_u8,
            option_size,
            quote_token_address,
            base_token_address,
            limit_total_premia,
            tx_deadline
        );
    stop_prank(amm_contract_addr);

    let final_option_balance = option_token.balanceOf(whale_address);
    assert(
        (final_option_balance - initial_option_balance).try_into().unwrap() == option_size,
        'Option tokens are not received'
    );

    // 2. Close trade
    // approve the AMM to spend the option tokens
    start_prank(option_token_address, whale_address);
    option_token.approve(amm_contract_addr, option_size.into());
    stop_prank(option_token_address);

    // Get initial USDC balance before closing trade
    let initial_usdc_balance = usdc.balanceOf(whale_address);

    // Close the trade
    start_prank(amm_contract_addr, whale_address);
    start_prank(lptoken_address, whale_address);
    let trade_close_premia = amm
        .trade_close(
            1_u8,
            strike_price,
            maturity,
            0_u8,
            option_size,
            quote_token_address,
            base_token_address,
            FixedTrait::from_felt(1),
            get_block_timestamp() + 30
        );
    stop_prank(amm_contract_addr);
    stop_prank(lptoken_address);

    // Check that option tokens were burned
    let final_option_balance_after_close = option_token.balanceOf(whale_address);
    assert(
        final_option_balance_after_close == initial_option_balance, 'Option tokens were not burned'
    );

    // Check that USDC was received
    let final_usdc_balance = usdc.balanceOf(whale_address);
    assert(final_usdc_balance > initial_usdc_balance, 'USDC not received');
}


// #[test]
// #[fork("MAINNET")]
fn test_amm_open_trade_and_settle() {
    // AMM setup and upgrade
    let amm_contract_addr: ContractAddress =
        0x047472e6755afc57ada9550b6a3ac93129cc4b5f98f51c73e0644d129fd208d9
        .try_into()
        .unwrap();
    let amm = IAMMDispatcher { contract_address: amm_contract_addr };

    let deployer: ContractAddress =
        0x074fd7da23e21f0f0479adb435221b23f57ca4c32a0c68aad9409a41c27f3067
        .try_into()
        .unwrap();

    let new_class_hash: ClassHash =
        0x07a57625ddc2fbcca39c30a13c04fdcbc7d7c25ff7a66703666392dc0de1e88f
        .try_into()
        .unwrap();

    start_prank(amm_contract_addr, deployer);
    amm.upgrade(new_class_hash);
    stop_prank(amm_contract_addr);

    // Test parameters (same as before)
    let quote_token_address: ContractAddress =
        0x53c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8
        .try_into()
        .unwrap();
    let base_token_address: ContractAddress =
        0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7
        .try_into()
        .unwrap();

    let whale_address: ContractAddress =
        0x053e1987bbc5f997a09760269774bfc6b7089cdac24459dc6976a08f186088c3
        .try_into()
        .unwrap();

    let option_type: OptionType = 1_u8;
    let lptoken_address = amm
        .get_lptoken_address_for_given_option(quote_token_address, base_token_address, option_type);

    // Open trade parameters
    let current_timestamp = get_block_timestamp();
    let strike_price = FixedTrait::from_felt(51650883406386744524800); // 2800
    let maturity = 1723161599_u64;
    let option_size = 100_000_000_000_000_000_u128; // 0.1 ETH
    let limit_total_premia = FixedTrait::from_felt(11068046444225730969600); // 600
    let tx_deadline = get_block_timestamp() + 30;

    // Approve USDC spending
    start_prank(quote_token_address, whale_address);
    let value_to_approve = 650_000_000_u256;
    let usdc = IERC20Dispatcher { contract_address: quote_token_address };
    usdc.approve(amm_contract_addr, value_to_approve);
    stop_prank(quote_token_address);

    // Get initial balances
    let initial_usdc_balance = usdc.balanceOf(whale_address);
    let option_token_address = amm
        .get_option_token_address(lptoken_address, 0_u8, maturity, strike_price);
    let option_token = IERC20Dispatcher { contract_address: option_token_address };
    let initial_option_balance = option_token.balanceOf(whale_address);

    // Open trade
    start_prank(amm_contract_addr, whale_address);
    start_prank(lptoken_address, whale_address);
    let trade_open_premia = amm
        .trade_open(
            1_u8,
            strike_price,
            maturity,
            0_u8,
            option_size,
            quote_token_address,
            base_token_address,
            limit_total_premia,
            tx_deadline
        );
    stop_prank(amm_contract_addr);
    stop_prank(lptoken_address);

    // Check that option tokens were received
    let post_trade_option_balance = option_token.balanceOf(whale_address);
    assert(
        (post_trade_option_balance - initial_option_balance).try_into().unwrap() == option_size,
        'Option tokens not received'
    );

    // Check that USDC was spent
    let post_trade_usdc_balance = usdc.balanceOf(whale_address);
    assert(post_trade_usdc_balance < initial_usdc_balance, 'USDC not spent');

    let curr_block = get_block_info().unbox().block_number;
    start_roll(lptoken_address, curr_block + 5);
    start_roll(amm_contract_addr, curr_block + 5);
    start_warp(amm_contract_addr, maturity + 100);
    start_warp(lptoken_address, maturity + 100);
    start_warp(whale_address, maturity + 100);
    start_prank(amm_contract_addr, whale_address);
    // Mock Pragma oracle call
    start_mock_call(
        PRAGMA_ORACLE_ADDRESS.try_into().unwrap(),
        'get_last_checkpoint_before',
        (
            Checkpoint {
                timestamp: maturity - 1,
                value: 3000_000_000,
                aggregation_mode: AggregationMode::Median(()),
                num_sources_aggregated: 0
            },
            1
        )
    );
    // let curr_price = OracleAgg::get_current_price(base_token_address, quote_token_address);
    // curr_price.print();

    // Settle expired option
    amm
        .trade_settle(
            1_u8, strike_price, maturity, 0_u8, option_size, quote_token_address, base_token_address
        );
    stop_prank(amm_contract_addr);

    // Check final balances
    let final_option_balance = option_token.balanceOf(whale_address);
    let final_usdc_balance = usdc.balanceOf(whale_address);

    // Assert option tokens were burned
    assert(final_option_balance == initial_option_balance, 'Option tokens not burned');
}
