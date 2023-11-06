use starknet::get_caller_address;

fn assert_admin_only() {
    let caller = get_caller_address();

    if caller.into() == 0x00CcAd7A3e7d1B16Db2aE10d069176f0BfB205DE68c4627D91afF59f0D0F9382 {
        return;
    }
    if caller.into() == 0x0178227144f45dd9e704dab545018813d17383e4cd1181a94fb7086df8cc49e7 {
        return;
    }
    if caller.into() == 0x001dd8e12b10592676E109C85d6050bdc1E17adf1be0573a089E081C3c260eD9 {
        return;
    }

    assert(1 == 0, 'Caller not an admin');
}
