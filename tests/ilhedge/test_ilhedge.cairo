use carmine_protocol::testing::setup::deploy_setup;
use snforge_std::{ContractClass, ContractClassTrait, declare};

use carmine_protocol::ilhedge::contract::{IILHedgeDispatcher, IILHedgeDispatcherTrait};

#[test]
fn test_ilhedge() {
    let (ctx, dsps) = deploy_setup();

    let ilhedge_contract = declare('ILHedge');

    let mut ilhedge_constructor_data: Array<felt252> = ArrayTrait::new();
    ilhedge_constructor_data.append(ctx.amm_address.into());

    let ilhedge_address = ilhedge_contract.deploy(@ilhedge_constructor_data).unwrap();

    assert(ilhedge_address.into() != 0, 'ilhedge addr 0');
    let ilhedge = IILHedgeDispatcher { contract_address: ilhedge_address };
    ilhedge.price_hedge(10000000000000, 0x005a643907b9a4bc6a55e9069c4fd5fd1f5c79a22470690f75556c4736e34426, 0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7, 1698451199)
}
