# Constant Product AMM (CPAMM)

A Solidity implementation of a Constant Product Automated Market Maker, similar to Uniswap V2. This contract allows users to swap between two ERC20 tokens and provides liquidity providers with LP tokens.

## Features

### Core Functionality

-   **Swap**: Trade between two tokens using the constant product formula ($x \times y = k$).
    -   Includes a 0.3% protocol fee.
-   **Add Liquidity**: Deposit equal value of both tokens to earn LP shares.
-   **Remove Liquidity**: Burn LP shares to withdraw the underlying tokens.

### Security & Safety

-   **Slippage Protection**: The `swap` function accepts a `_minAmountOut` parameter. The transaction reverts if the received amount is lower than this threshold.
-   **Deadline Check**: The `swap` function accepts a `_deadline` timestamp. The transaction reverts if executed after this time, protecting against stale executions.
-   **Reentrancy Safety**: All functions follow the strict **Checks-Effects-Interactions (CEI)** pattern. We perform manual reserve updates before external transfers to prevent reentrancy attacks without needing a `nonReentrant` modifier.

## Usage

### Prerequisites

-   [Foundry](https://getfoundry.sh/) installed.

### Build

```shell
forge build
```

### Test

```shell
forge test
```

## Contract Details

### `swap`

```solidity
function swap(
    address _tokenIn,
    uint256 _amountIn,
    uint256 _minAmountOut,
    uint256 _deadline
) public returns (uint256 amountOut)
```

-   **_tokenIn**: Address of the token to sell.
-   **_amountIn**: Amount of tokens to sell.
-   **_minAmountOut**: Minimum amount of tokens to buy (slippage protection).
-   **_deadline**: Timestamp after which the transaction expires.

### `addLiquidity`

```solidity
function addLiquidity(
    uint256 _amount0,
    uint256 _amount1
) public returns (uint256 shares)
```

Adds liquidity to the pool. The ratio of `_amount0` to `_amount1` should match the current reserve ratio to avoid arbitrage.

### `removeLiquidity`

```solidity
function removeLiquidity(
    uint256 _shares
) public returns (uint256 amount0, uint256 amount1)
```

Burns LP tokens (`_shares`) and returns the proportional underlying assets.
