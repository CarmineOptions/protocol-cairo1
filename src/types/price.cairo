use starknet::ContractAddress;

#[derive(Drop, Serde)]
struct Price {
    token_address: ContractAddress,
    price: u128,
}
