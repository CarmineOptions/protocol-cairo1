use starknet::ContractAddress;

use debug::PrintTrait;
use carmine_protocol::amm_interface::IAMMDispatcher;
use carmine_protocol::amm_interface::IAMMDispatcherTrait;

use carmine_protocol::oz::access::interface::IOwnable;
use carmine_protocol::oz::access::interface::IOwnableDispatcher;
use carmine_protocol::oz::access::interface::IOwnableDispatcherTrait;

use snforge_std::{start_prank, stop_prank,};


use carmine_protocol::amm_core::oracles::pragma::Pragma::PragmaUtils::PRAGMA_EKUBO_USD_KEY;
use carmine_protocol::amm_core::oracles::pragma::Pragma::{
    PRAGMA_ORACLE_ADDRESS, IOracleABIDispatcher, IOracleABIDispatcherTrait, DataType,
    AggregationMode,
};

use carmine_protocol::amm_core::constants::{
    TOKEN_USDC_ADDRESS, TOKEN_EKUBO_ADDRESS, TOKEN_STRK_ADDRESS, TOKEN_ETH_ADDRESS
};


#[test]
#[fork("MAINNET_MISSING_TERMINAL_PRICE")]
fn test_missing_ekubo_terminal_price() {
    // New AMM Hash: 0x07fb1aa680d9c02e1017d5ed048612630c30d11991d43b3e4e7a22531621cd5c

    // Missing maturities: 1744329599, 1744934399, 1745539199, 1743119999
    let mat1: u64 = 1744329599;
    let mat2: u64 = 1744934399;
    let mat3: u64 = 1745539199;
    let mat4: u64 = 1743119999;
    let _mat5: u64 = 1743724799; // This one works fine

    let quote_token: ContractAddress = TOKEN_USDC_ADDRESS.try_into().unwrap();
    let base_token: ContractAddress = TOKEN_EKUBO_ADDRESS.try_into().unwrap();
    let eth_address: ContractAddress = TOKEN_ETH_ADDRESS.try_into().unwrap();
    let strk_address: ContractAddress = TOKEN_STRK_ADDRESS.try_into().unwrap();

    let amm_contract_addr: ContractAddress =
        0x047472e6755afc57ada9550b6a3ac93129cc4b5f98f51c73e0644d129fd208d9
        .try_into()
        .unwrap();
    let amm = IAMMDispatcher { contract_address: amm_contract_addr };
    let owner = IOwnableDispatcher { contract_address: amm_contract_addr }.owner();

    // Get some prices before upgrade
    let _eprice1 = amm.get_terminal_price(quote_token, eth_address, mat1);
    let _eprice2 = amm.get_terminal_price(quote_token, eth_address, mat2);
    let _eprice3 = amm.get_terminal_price(quote_token, eth_address, mat3);
    let _eprice4 = amm.get_terminal_price(quote_token, eth_address, _mat5);

    let _sprice1 = amm.get_terminal_price(quote_token, strk_address, mat1);
    let _sprice2 = amm.get_terminal_price(quote_token, strk_address, mat2);
    let _sprice3 = amm.get_terminal_price(quote_token, strk_address, mat3);
    let _sprice4 = amm.get_terminal_price(quote_token, strk_address, _mat5);

    let ekubo_correct_price = amm.get_terminal_price(quote_token, base_token, _mat5);

    start_prank(amm_contract_addr, owner);
    let new_amm_hash = 0x07fb1aa680d9c02e1017d5ed048612630c30d11991d43b3e4e7a22531621cd5c;
    amm.upgrade(new_amm_hash.try_into().unwrap());

    let pragma = IOracleABIDispatcher {
        contract_address: PRAGMA_ORACLE_ADDRESS.try_into().unwrap()
    };

    let (pragma1, _) = pragma
        .get_last_checkpoint_before(
            DataType::SpotEntry(PRAGMA_EKUBO_USD_KEY), mat1, AggregationMode::Median(()),
        );
    let (pragma2, _) = pragma
        .get_last_checkpoint_before(
            DataType::SpotEntry(PRAGMA_EKUBO_USD_KEY), mat2, AggregationMode::Median(()),
        );
    let (pragma3, _) = pragma
        .get_last_checkpoint_before(
            DataType::SpotEntry(PRAGMA_EKUBO_USD_KEY), mat3, AggregationMode::Median(()),
        );
    let (pragma4, _) = pragma
        .get_last_checkpoint_before(
            DataType::SpotEntry(PRAGMA_EKUBO_USD_KEY), mat4, AggregationMode::Median(()),
        );
    // These three maturities should have unsuitable terminal price
    // meaning the price is more then 2 hours old at time of maturity
    assert(pragma1.timestamp < mat1 - 2 * 3600, 'Price1 isnt old');
    assert(pragma2.timestamp < mat2 - 2 * 3600, 'Price2 isnt old');
    assert(pragma3.timestamp < mat3 - 2 * 3600, 'Price3 isnt old');
    assert(pragma4.timestamp < mat4 - 2 * 3600, 'Price3 isnt old');

    // Now call amm get terminal price - this should return a price 
    // and not fail since values for these maturities are hardcoded

    let price1 = amm.get_terminal_price(quote_token, base_token, mat1);
    let price2 = amm.get_terminal_price(quote_token, base_token, mat2);
    let price3 = amm.get_terminal_price(quote_token, base_token, mat3);
    let price4 = amm.get_terminal_price(quote_token, base_token, mat4);

    assert(price1.mag == 70672569880895012595, 'wrong price1');
    assert(price2.mag == 67146148428302767882, 'wrong price2');
    assert(price3.mag == 84393854137221198643, 'wrong price3');
    assert(price4.mag == 121850010775334694205, 'wrong price4');

    // Fetch prices for other assets again after upgrade and assert they haven't changed
    assert(_eprice1 == amm.get_terminal_price(quote_token, eth_address, mat1), 'price changed1');
    assert(_eprice2 == amm.get_terminal_price(quote_token, eth_address, mat2), 'price changed2');
    assert(_eprice3 == amm.get_terminal_price(quote_token, eth_address, mat3), 'price changed3');
    assert(_eprice4 == amm.get_terminal_price(quote_token, eth_address, _mat5), 'price changed4');

    assert(_sprice1 == amm.get_terminal_price(quote_token, strk_address, mat1), 'price changed5');
    assert(_sprice2 == amm.get_terminal_price(quote_token, strk_address, mat2), 'price changed6');
    assert(_sprice3 == amm.get_terminal_price(quote_token, strk_address, mat3), 'price changed7');
    assert(_sprice4 == amm.get_terminal_price(quote_token, strk_address, _mat5), 'price changed8');

    assert(
        ekubo_correct_price == amm.get_terminal_price(quote_token, base_token, _mat5),
        'price changed9'
    );
}

