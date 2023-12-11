# protocol-cairo1
This repo contains Carmine Options AMM written in C1, version `2.3.0`.

## Building/Testing the project
The contracts are build using Scarb `2.3.0.` Install with:
`curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | sh -s -- -v 2.3.0`

Then build by running `scarb build` command.

Tests can be run with Starknet foundry `0.10.1.` Install by first installing `snfoundryup`:
`curl -L https://raw.githubusercontent.com/foundry-rs/starknet-foundry/master/scripts/install.sh | sh`

And then install the correct version: `snfoundryup -v 0.10.1`

Now you can run tests with `snforge test`.

Alternatively you can open this folder in VSCode Devcontainer, which comes with all the tooling installed.

## Note on presence of OZ contracts in the repo
The AMM is currently built on Cairo version 2.3.0. However while OpenZeppelin was porting their contracts to 2.3.0 the 2.3.1 came out in the meantime, so part of contracts (which we do not need) are built on top 2.3.1. and snforge 0.10.1 unfortunately does not support that so tests can't be run if we include OZ contracts in the Scarb.toml file. For that reason we just imported needed contracts directly.

## List of files to be audited
**Everything except for OZ smart contracts, `src/amm_core/peripheries` folder and tests is intended for audit:**
- src/amm_core/oracles/agg.cairo
- src/amm_core/oracles/oracle_helpers.cairo
- src/amm_core/oracles/pragma.cairo
- src/amm_core/pricing/fees.cairo
- src/amm_core/pricing/option_pricing.cairo
- src/amm_core/pricing/option_pricing_helpers.cairo
- src/amm_core/amm.cairo
- src/amm_core/constants.cairo
- src/amm_core/helpers.cairo
- src/amm_core/liquidity_pool.cairo
- src/amm_core/options.cairo
- src/amm_core/state.cairo
- src/amm_core/trading.cairo
- src/types/option_.cairo
- src/types/pool.cairo
- src/tokens/lptoken.cairo
- src/tokens/option_token.cairo

## Tests
Unit tests are located in files containing relevant code, while integration tests are located in `tests` folder. Currently there are integration tests for: 
- Depositing liquidity
- Withdrawing liquidity
- Opening trade
- Closing trade
- Settling trade
- View functions
- Sandwich guard

Most of the tests also contain a couple of different scenarios.

Folder `src/testing` contains various utilities for writing tests:
 - `setup.cairo` - Contains function that will fully deploy the AMM (along with tokens representing ETH, USDC), set it up, add liquidity etc. The function is called `deploy_setup` and it returns a tuple of two structs, where the first one is `Ctx` (context) which contains information needed for tests - addresses (AMM, tokens, LP tokens, OP tokens, admin...) strike, expiry etc. The second struct, `Dispatchers`, provides dispatcher for every contract that is deployed in the tests (it's more convenient than having to create them in the test manually). 
 - `test_utils.cairo` provides utilities for fetching all the information about current AMM state (plus some user balances etc.). To fetch the `Stats` struct, call the `new` method on it with `Ctx` and `Dispatchers` as args. `Stats` also implement `PrintTrait` for more convenient debugging. 

You can look into `tests/test_dummy.cairo` to see an example of how to write a new test - how to deploy the setup, prank the AMM, mock the Pragma price, fetch the AMM state etc.

## Deployment - Zero to Hero 
Deployment described using `starkli`, version `0.1.20 (e4d2307)`.

There will be a lot of invoking and deploying, so it might be useful to make some aliases:
- `alias sinv='starkli invoke  --account /path/to/account --keystore /path/to/key.json --rpc http://rpc.address.here`
- `alias depl='starkli deploy  --account /path/to/account --keystore /path/to/key.json --rpc http://rpc.address.here`
- `alias decl='starkli declare --account /path/to/account --keystore /path/to/key.json --rpc http://rpc.address.here`

1. Build the contracts with 
   - `scarb build`
   
2. Declare the AMM and tokens and export the hashes
    - AMM
      - `decl ./target/dev/carmine_protocol_AMM.contract_class.json`
      - `export AMM_HASH=...`

    - LP Token
        - `decl ./target/dev/carmine_protocol_LPToken.contract_class.json`
        - `export LPT_HASH=...`

    - OP Token
      - `decl ./target/dev/carmine_protocol_OptionToken.contract_class.json`
      - `export OPT_HASH=...`

3. Export some additional vars
    - `export ETH_ADDR=0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7`
    - `export USDC_ADDR=0x005a643907b9a4bc6a55e9069c4fd5fd1f5c79a22470690f75556c4736e34426`
    - `export BTC_ADDR=0x012d537dc323c439dc65c976fad242d5610d27cfb5f31689a0a319b8be7f3d56`
    - `export INITIAL_VOL=1844674407370955161600` 
    - `export CALL_TYPE=0`
    - `export PUT_TYPE=1`
    - `export LONG_SIDE=0`
    - `export SHORT_SIDE=1`
    - `export ETH_STRIKE_CALL=32281802128991715328000`
    - `export ETH_STRIKE_PUT=31359464925306237747200`
    - Note: Strikes and inital volatility are in Fixed format, meaning they are calculated as `value * 2**64`

4. Deploy AMM 
   - `export OWNER_ADDR=...`
   - `depl $AMM_HASH $OWNER_ADDR`
   - `export AMM_ADDR=...`

5. Deploy LP Tokens
    - CALL
      - `depl $LPT_HASH str:ETHCALL str:EC $AMM_ADDR`
      - `export ETH_CALL_LPT=...`
    - PUT
      - `depl $LPT_HASH str:ETHPUT str:EP $AMM_ADDR`
      - `export ETH_PUT_LPT=...`


6. Add LP tokens to the AMM
    - `export VOLADJSPD_ETHC=18446744073709551616`
    - `export VOLADJSPD_ETHP=11529215046068469760000`
    - `export MILLIE_USDC=1000000000000`
    - `export MILLIE_ETH=1000000000000000000000000`

    - `sinv $AMM_ADDR add_lptoken $USDC_ADDR $ETH_ADDR $CALL_TYPE $ETH_CALL_LPT $ETH_ADDR $VOLADJSPD_ETHC 0 $MILLIE_ETH 0`
    - `sinv $AMM_ADDR add_lptoken $USDC_ADDR $ETH_ADDR $PUT_TYPE $ETH_PUT_LPT $USDC_ADDR $VOLADJSPD_ETHP 0 $MILLIE_USDC 0`

7. Deploy OP Tokens
    - `export MATURITY=...` (UNIX timestamp)
    - `export ETH_STRIKE_CALL=...` (Fixed format)
    - `export ETH_STRIKE_PUT=...` (Fixed format)

    - LONG CALL
        - `depl $OPT_HASH str:ETH-LC str:ELC $AMM_ADDR $USDC_ADDR $ETH_ADDR $CALL_TYPE $ETH_STRIKE_CALL $MATURITY $LONG_SIDE`
        - `export OPT_LONG_CALL=...`

    - SHORT CALL
        - `depl $OPT_HASH str:ETH-SC str:ESC $AMM_ADDR $USDC_ADDR $ETH_ADDR $CALL_TYPE $ETH_STRIKE_CALL $MATURITY $SHORT_SIDE`
        - `export OPT_SHORT_CALL=...`

    - LONG PUT
        - `depl $OPT_HASH str:ETH-LP str:ELC $AMM_ADDR $USDC_ADDR $ETH_ADDR $PUT_TYPE $ETH_STRIKE_PUT $MATURITY $LONG_SIDE`
        - `export OPT_LONG_PUT=...`

    - SHORT PUT
        - `depl $OPT_HASH str:ETH-SP str:ESC $AMM_ADDR $USDC_ADDR $ETH_ADDR $PUT_TYPE $ETH_STRIKE_PUT $MATURITY $SHORT_SIDE`
        - `export OPT_SHORT_PUT=...`

8. Add OP tokens to the AMM
    - `export INITIAL_VOL=1844674407370955161600`

    - CALLS
        - `sinv $AMM_ADDR add_option_both_sides $MATURITY $ETH_STRIKE_CALL 0 $USDC_ADDR $ETH_ADDR 0 $ETH_CALL_LPT $OPT_LONG_CALL $OPT_SHORT_CALL $INITIAL_VOL 0`

    - PUTS
        - `sinv $AMM_ADDR add_option_both_sides $MATURITY $ETH_STRIKE_PUT 0 $USDC_ADDR $ETH_ADDR 1 $ETH_PUT_LPT $OPT_LONG_PUT $OPT_SHORT_PUT $INITIAL_VOL 0`

9. Approve AMM for spending ETH/USDC
    - ETH
        - `sinv $ETH_ADDR approve $AMM_ADDR 1000000000000000000 0`

    - USDC
        - `sinv $USDC_ADDR approve $AMM_ADDR 2000000000 0`

10. Add liquidity
    - CALL
        - `sinv $AMM_ADDR deposit_liquidity $ETH_ADDR $USDC_ADDR $ETH_ADDR $CALL_TYPE 5000000000000000 0`

    - PUT
        - `sinv $AMM_ADDR deposit_liquidity $USDC_ADDR $USDC_ADDR $ETH_ADDR $PUT_TYPE 1000000000 0`

11. Check LP Token balance
    - CALL
        - `starkli call $ETH_CALL_LPT balanceOf $OWNER_ADDR`

    - PUT
        - `starkli call $ETH_PUT_LPT balanceOf $OWNER_ADDR`

12. Check AMM Lpool balances
    - CALL
        - `starkli call $AMM_ADDR get_lpool_balance $ETH_CALL_LPT`
    - PUT
        - `starkli call $AMM_ADDR get_lpool_balance $ETH_PUT_LPT`

13. Enable trading and set max option size
    - `sinv $AMM_ADDR set_trading_halt 1`
    - `sinv $AMM_ADDR set_max_option_size_percent_of_voladjspd 50`

14. YOLO into some Options
    - CALL 
        - LONG
            - `sinv $AMM_ADDR trade_open $CALL_TYPE $ETH_STRIKE_CALL 0 $MATURITY $LONG_SIDE 10000000000000 $USDC_ADDR $ETH_ADDR 23058430092136939520000 0 1701099575`

        - SHORT
            - `sinv $AMM_ADDR trade_open $CALL_TYPE $ETH_STRIKE_CALL 0 $MATURITY $SHORT_SIDE 10000000000000 $USDC_ADDR $ETH_ADDR 1 0 1701099575`
    
    - PUT
        - LONG
            - `sinv $AMM_ADDR trade_open $PUT_TYPE $ETH_STRIKE_PUT 0 $MATURITY $LONG_SIDE 10000000000000 $USDC_ADDR $ETH_ADDR 23058430092136939520000 0 1701099575`

        - SHORT
            - `sinv $AMM_ADDR trade_open $PUT_TYPE $ETH_STRIKE_PUT 0 $MATURITY $SHORT_SIDE 10000000000000 $USDC_ADDR $ETH_ADDR 1 0 1701099575`


15. Un-Yolo some Option
    - LONG CALL
        - `sinv $AMM_ADDR trade_close $CALL_TYPE $ETH_STRIKE_CALL 0 $MATURITY $LONG_SIDE 10000000000000 $USDC_ADDR $ETH_ADDR 1 0 1701099575`

