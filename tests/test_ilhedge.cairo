use carmine_protocol::testing::setup::deploy_setup;
use snforge_std::{ContractClass, ContractClassTrait, declare};

#[test]
fn test_ilhedge() {
    let (ctx, dsps) = deploy_setup();

    let ilhedge_contract = declare('ILHedge');

    let mut ilhedge_constructor_data: Array<felt252> = ArrayTrait::new();
    ilhedge_constructor_data.append(ctx.amm_address.into());

    let ilhedge_address = ilhedge_contract.deploy(@ilhedge_constructor_data).unwrap();

    assert(ilhedge_address.into() != 0, 'ilhedge addr 0');

}