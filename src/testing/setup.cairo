// use starknet::ContractAddress;
// use option::Option;
// use result::Result;
// use result::ResultTrait;
// use array::ArrayTrait;
// use option::OptionTrait;
// use debug::PrintTrait;
// use traits::{Into, TryInto};

// use carmine_protocol::amm_core::amm::{AMM, IAMMDispatcher, IAMMDispatcherTrait };
// use snforge_std::{declare, PreparedContract, deploy};

// use openzeppelin::token::erc20::ERC20;
// use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

// #[derive(Drop)]
// struct Setup { 
//     amm_address : ContractAddress,
//     eth_address : ContractAddress,
//     call_lpt_address: ContractAddress,
//     put_lpt_address: ContractAddress,
// }

// fn deploy_setup() -> Setup {

//     // Deploy AMM
//     let amm_hash = declare('AMM');
//     let amm_prepared = PreparedContract {
//         class_hash: amm_hash, constructor_calldata: @ArrayTrait::new()
//     };
//     let amm_address = deploy(amm_prepared).unwrap();
//     let erc20_hash = declare('ERC20');

//     // Deploy Call ILPT
//     let mut call_lpt_data = ArrayTrait::new();
//     call_lpt_data.append('lorem');
//     call_lpt_data.append('ipsum');
//     call_lpt_data.append(1);
//     call_lpt_data.append(1);
//     call_lpt_data.append(1);
//     let call_lpt_prepared = PreparedContract {
//         class_hash: erc20_hash, constructor_calldata: @call_lpt_data
//     };
//     let call_lpt_address = deploy(call_lpt_prepared).unwrap();

//     // Deploy Put ILPT
//     let mut put_lpt_data = ArrayTrait::new();
//     put_lpt_data.append('lorem');
//     put_lpt_data.append('ipsum');
//     put_lpt_data.append(1);
//     put_lpt_data.append(1);
//     put_lpt_data.append(1);
//     let put_lpt_prepared = PreparedContract {
//         class_hash: erc20_hash, constructor_calldata: @put_lpt_data
//     };
//     let put_lpt_address = deploy(put_lpt_prepared).unwrap();

//     // Deploy ETH
//     let sth: ContractAddress = 0.try_into().unwrap();
//     let mut eth_constr_data = ArrayTrait::new();
//     eth_constr_data.append('lorem');
//     eth_constr_data.append('ipsum');
//     eth_constr_data.append(1);
//     eth_constr_data.append(1);
//     eth_constr_data.append(1);

//     let eth_prepared = PreparedContract {
//         class_hash: erc20_hash, constructor_calldata: @eth_constr_data
//     };
//     let eth_address = deploy(eth_prepared).unwrap();

//     Setup {
//         amm_address: amm_address,
//         eth_address: eth_address,
//         call_lpt_address: call_lpt_address,
//         put_lpt_address: put_lpt_address
//     }
// }

// #[test]
// fn test_deploy_setup() {
//     let setup = deploy_setup();

//     let amm_dispatch = IAMMDispatcher { contract_address: setup.amm_address };
//     let eth_dispatch = IERC20Dispatcher { contract_address: setup.eth_address };
//     let halt = amm_dispatch.get_trading_halt();
//     let decs = eth_dispatch.decimals();

//     halt.print();
//     decs.print();
// }

