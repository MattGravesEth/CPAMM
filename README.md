# Constant Product AMM (CPAMM)

A Solidity implementation of a Constant Product Automated Market Maker, similar to Uniswap V2. This contract allows users to swap between two ERC20 tokens and provides liquidity providers with LP tokens.

## Features

### Core Functionality

-   **Swap**: Trade between two tokens using the constant product formula (xy = k).
    -   Includes a 0.3% protocol fee.
-   **Add Liquidity**: Deposit equal value of both tokens to earn LP shares.
-   **Remove Liquidity**: Burn LP shares to withdraw the underlying tokens.

### Security & Safety

-   **Slippage Protection**: The `swap` function accepts a `_minAmountOut` parameter. The transaction reverts if the received amount is lower than this threshold.
-   **Deadline Check**: The `swap` and `swapAndAddLiquidity` functions accept a `_deadline` timestamp to prevent stale executions.
-   **Reentrancy Safety**: The contract uses OpenZeppelin's `ReentrancyGuard` (`nonReentrant` modifier) and follows the **Checks-Effects-Interactions (CEI)** pattern for double protection.
-   **Security**: Uses OpenZeppelin's `SafeERC20` for token transfers and `Math` library for square root calculations.
-   **Observability**: Emits `Swap`, `Mint`, and `Burn` events for all state changes.

### Advanced Functionality

-   **Zap (Swap and Add Liquidity)**: The `swapAndAddLiquidity` function allows users to add liquidity with a single token (or unbalanced amounts). It automatically swaps the optimal amount of tokens to minimize dust and adds liquidity in one transaction.

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

### Fuzz Test

```shell
forge test --match-path test/CPAMM.fuzz.t.sol
```

## Contract Details

### `swap`

```solidity
function swap(
    address tokenIn,
    uint256 amountIn,
    uint256 minAmountOut,
    uint256 deadline
) public returns (uint256 amountOut)
```

-   **tokenIn**: Address of the token to sell.
-   **amountIn**: Amount of tokens to sell.
-   **minAmountOut**: Minimum amount of tokens to buy (slippage protection).
-   **deadline**: Timestamp after which the transaction expires.

### `addLiquidity`

```solidity
function addLiquidity(
    uint256 amount0,
    uint256 amount1
) public returns (uint256 shares)
```

Adds liquidity to the pool. The ratio of `amount0` to `amount1` should match the current reserve ratio to avoid arbitrage.

### `removeLiquidity`

```solidity
function removeLiquidity(
    uint256 shares
) public returns (uint256 amount0, uint256 amount1)
```

Burns LP tokens (`shares`) and returns the proportional underlying assets.

### `swapAndAddLiquidity`

```solidity
function swapAndAddLiquidity(
    uint256 amount0,
    uint256 amount1,
    uint256 minShares,
    uint256 deadline
) external returns (uint256 shares)
```

Automatically swaps tokens to balance the pool ratio and adds liquidity. Perfect for single-sided liquidity provision.
