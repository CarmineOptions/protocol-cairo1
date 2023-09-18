# protocol-cairo1
Temporary repo for porting carmine protocol to cairo 1

Currently it is pretty garbage so don't even try running build/tests.

Below is a list of things that need to be tested/finished:
## TODO:
- [ ] ReentrancyGuards
- [ ] Proxy/Admin!!
- [ ] Tokens - new vs old
- [ ] Correct interfaces for tokens
- [ ] Test AMM itself
- [ ] Test upgrade from old AMM
- [ ] Trading Halt
- [ ] Upgrade Function!
- [ ] Check interfaces

Plan: 
- Week 1: 
  - Internal tests
  - Check compatibility with outside contracts
    - Tokens, oracle
  - Simple Dashboard 
  - Trade, expire few options
  - Deposit/Withdraw liq
  - Add proxy, reetrancy guard
- Week 2:
  - Public testing
- Week 3:
  - Upgrading the amm
- Week 4: 
  - Profit?
