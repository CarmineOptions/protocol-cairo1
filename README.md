# protocol-cairo1
This repo contains Carmine Options AMM written in C1, version `2.3.0`.


The contracts are build using Scarb `2.3.0.` Install with:
`curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | sh -s -- -v 2.3.0`

Then build by running `scarb build` command.

Tests can be run with Starknet foundry `0.10.1.` Install by first installing `snfoundryup`:
`curl -L https://raw.githubusercontent.com/foundry-rs/starknet-foundry/master/scripts/install.sh | sh`

And then install the correct version: `snfoundryup -v 0.10.1`

Now you can run tests with `snforge test`.

Alternatively you can open this folder in VSCode Devcontainer, which comes with all the tooling installed.

## List of files to be audited:
- src/amm_core/oracles/agg
- src/amm_core/oracles/oracle_helpers
- src/amm_core/oracles/pragma
- src/amm_core/pricing/fees
- src/amm_core/pricing/option_pricing
- src/amm_core/pricing/option_pricing_helpers
- src/amm_core/amm
- src/amm_core/constants
- src/amm_core/helpers
- src/amm_core/liquidity_pool
- src/amm_core/options
- src/amm_core/state
- src/amm_core/trading
- src/types/option_
- src/types/pool


