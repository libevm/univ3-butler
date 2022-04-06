# Univ3 Butler

```
        .--.
       /    \ .   
      ## a  a 
      (   '._)      Univ3 
       |'-- |  single-sided LP
     _.\___/_  ____|_____|___
   ."\> \Y/|<'.  '._.-'
  /  \ \_\/ /  '-' /
  | --'\_/|/ |   _/
  |___.-' |  |`'`
    |     |  |
    |    / './
   /__./` | |
      \   | |
       \  | |
       ;  | |
       /  | |
      |___\_.\_
      `-"--'---'  
```

UniswapV3 Single Sided Liquidity Providing made *simple*. Basically [this](https://blog.alphaventuredao.io/onesideduniswap/) but for UniswapV3.

Given a Univ3 pool of tokenA/tokenB:
- We only have tokenA
- We would like to add liquidity to the pool
  - Where the current sqrtRatioX96 (spot price) is within our liquidity range
- How many tokenA do we swap to tokenB to optimally add liquidity to the pool within the range?
  - Swapping tokens also changes the reserves
- Goal is to end up with minimal leftover tokenA and tokenB

I know that Uniswap has an [official SDK dedicated to this](https://docs.uniswap.org/sdk/guides/liquidity/swap-and-add), but I already made mine before finding out theirs exist so...
## Usage


Only supporting solidity 0.7.x.

```bash
forge install libevm/univ3-butler
```

Add this to your `remappings.txt`:
```
@univ3-butler/=lib/univ3-butler/src
@uniswap-v3-core/=lib/v3-core/
@uniswap/v3-core/=lib/v3-core/
@uniswap-v3-periphery/=lib/v3-periphery/
@uniswap/v3-periphery/=lib/v3-periphery/
@openzeppelin/=lib/openzeppelin-contracts/
```

**Note: The purpose of this function is to be called off-chain**

```javascript
import "@univ3-butler/SingleSidedLiquidityLib.sol";

contract MyContract {
   // You only have baseTokens, how many baseTokens to swap to quoteTokens?
   function getBaseAmountsToSwapToQuote(
      address pool,
      int24 lowerTick,
      int24 upperTick,
      address baseToken,
      address quoteToken,
      uint256 baseAmountIn
  ) public returns (uint256 liquidity, uint256 tokensToSwap) {
    return SingleSidedLiquidityLib.getParamsForSingleSidedAmount(
      pool,
      lowerTick,
      upperTick,
      baseAmountIn,
      baseToken < quoteToken
    )
  }
}
```

## Development

Uses [foundry](https://getfoundry.sh/).

```bash
git clone https://github.com/libevm/univ3-butler.git
cd univ3-butler
git submodule update --init --recursive

# forge 0.2.0 (721093d 2022-04-05T00:07:09.103400+00:00)
forge test --optimize --optimize-runs 200 -v -f https://mainnet.infura.io/v3/84842078b09946638c03157f83405213
```
