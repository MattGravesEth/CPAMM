// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title CPAMM
 * @dev A simple Constant Product Automated Market Maker.
 * This contract manages a liquidity pool of two ERC20 tokens and allows users to swap them.
 * It also issues LP (liquidity provider) tokens to users who provide liquidity.
 */
contract CPAMM is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable token0;
    IERC20 public immutable token1;

    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);

    uint256 public constant MINIMUM_LIQUIDITY = 1000;
    uint256 public reserve0;
    uint256 public reserve1;

    uint256 public constant FEE_NUMERATOR = 997;
    uint256 public constant FEE_DENOMINATOR = 1000;

    /**
     * @dev Sets the two tokens for the liquidity pool.
     * @param _token0 Address of the first ERC20 token.
     * @param _token1 Address of the second ERC20 token.
     */
    constructor(address _token0, address _token1) ERC20("CPAMM LP", "CPLP") {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }

    /*
     * @dev Calculates the optimal amount of tokens to swap to matching the reserve ratio.
     *
     * The optimal swap amount `x` is the solution to the quadratic equation:
     * F_n * x^2 + R * (F_n + F_d) * x - R * A * F_d = 0
     *
     * where:
     * x   = optimal swap amount
     * R   = reserve of input token (resIn)
     * A   = amount of input token (amtIn)
     * F_n = FEE_NUMERATOR
     * F_d = FEE_DENOMINATOR
     */
    function _getOptimalSwapAmount(uint256 amtIn, uint256 resIn) internal pure returns (uint256) {
        // We use the quadratic formula x = (-b + sqrt(b^2 - 4ac)) / 2a

        uint256 a = FEE_NUMERATOR;
        uint256 b = resIn * (FEE_NUMERATOR + FEE_DENOMINATOR);
        uint256 ac4 = 4 * a * resIn * amtIn * FEE_DENOMINATOR;

        return (Math.sqrt(b * b + ac4) - b) / (2 * a);
    }

    /**
     * @dev Swaps one token for another.
     * @param tokenIn The address of the token being sent to the pool.
     * @param amountIn The amount of the token being sent.
     * @param minAmountOut The minimum amount of tokens to receive.
     * @param deadline The timestamp after which the transaction will revert.
     * @return amountOut The amount of the other token received.
     */
    function swap(address tokenIn, uint256 amountIn, uint256 minAmountOut, uint256 deadline)
        public
        nonReentrant
        returns (uint256 amountOut)
    {
        require(block.timestamp <= deadline, "Transaction expired");
        require(tokenIn == address(token0) || tokenIn == address(token1), "Invalid token");
        require(amountIn > 0, "Amount in must be positive");

        bool isToken0 = tokenIn == address(token0);
        IERC20 inputToken = isToken0 ? token0 : token1;

        // Transfer input tokens from user to the contract
        uint256 balanceBefore = inputToken.balanceOf(address(this));
        inputToken.safeTransferFrom(msg.sender, address(this), amountIn);
        uint256 amountInActual = inputToken.balanceOf(address(this)) - balanceBefore;

        amountOut = _swap(isToken0, amountInActual, msg.sender);

        require(amountOut >= minAmountOut, "Insufficient output amount");
    }

    /**
     * @dev Internal swap function working with current balances.
     */
    function _swap(bool isToken0, uint256 _amountIn, address _to) internal returns (uint256 amountOut) {
        (uint256 reserveIn, uint256 reserveOut) = isToken0 ? (reserve0, reserve1) : (reserve1, reserve0);

        // Calculate output amount based on constant product formula (with a 0.3% fee)
        uint256 amountInWithFee = _amountIn * FEE_NUMERATOR;
        amountOut = (reserveOut * amountInWithFee) / (reserveIn * FEE_DENOMINATOR + amountInWithFee);

        // Update reserves (Effects)
        if (isToken0) {
            reserve0 += _amountIn;
            reserve1 -= amountOut;
        } else {
            reserve1 += _amountIn;
            reserve0 -= amountOut;
        }

        // Transfer output tokens (Interactions)
        if (_to != address(this)) {
            IERC20 tokenOut = isToken0 ? token1 : token0;
            tokenOut.safeTransfer(_to, amountOut);
        }

        if (isToken0) {
            emit Swap(msg.sender, _amountIn, 0, 0, amountOut, _to);
        } else {
            emit Swap(msg.sender, 0, _amountIn, amountOut, 0, _to);
        }
    }

    /**
     * @dev Adds liquidity to the pool.
     * @param amount0 The amount of token0 to add.
     * @param amount1 The amount of token1 to add.
     * @return shares The amount of LP tokens minted.
     */
    function addLiquidity(uint256 amount0, uint256 amount1) public nonReentrant returns (uint256 shares) {
        uint256 bal0Before = token0.balanceOf(address(this));
        uint256 bal1Before = token1.balanceOf(address(this));

        token0.safeTransferFrom(msg.sender, address(this), amount0);
        token1.safeTransferFrom(msg.sender, address(this), amount1);

        uint256 amount0Actual = token0.balanceOf(address(this)) - bal0Before;
        uint256 amount1Actual = token1.balanceOf(address(this)) - bal1Before;

        shares = _addLiquidity(amount0Actual, amount1Actual, msg.sender);
    }

    function _addLiquidity(uint256 _amount0, uint256 _amount1, address _to) internal returns (uint256 shares) {
        if (totalSupply() == 0) {
            // Initial liquidity provider
            shares = 100 ether; // Arbitrary starting supply
            // Lock the first MINIMUM_LIQUIDITY tokens to prevent inflation attacks
            if (shares > MINIMUM_LIQUIDITY) {
                shares -= MINIMUM_LIQUIDITY;
                _mint(address(0x000000000000000000000000000000000000dEaD), MINIMUM_LIQUIDITY);
            }
        } else {
            uint256 shares0 = (_amount0 * totalSupply()) / reserve0;
            uint256 shares1 = (_amount1 * totalSupply()) / reserve1;
            shares = shares0 < shares1 ? shares0 : shares1;
        }

        require(shares > 0, "shares must be greater than 0");

        // Mint LP tokens (Effects)
        _mint(_to, shares);

        // Update reserves (Effects)
        reserve0 += _amount0;
        reserve1 += _amount1;

        emit Mint(_to, _amount0, _amount1);
    }

    /**
     * @dev Swaps excess token to balance ratios, then adds liquidity.
     */
    function swapAndAddLiquidity(uint256 amount0, uint256 amount1, uint256 minShares, uint256 deadline)
        external
        returns (uint256 shares)
    {
        require(block.timestamp <= deadline, "Transaction expired");

        uint256 bal0Before = token0.balanceOf(address(this));
        uint256 bal1Before = token1.balanceOf(address(this));

        token0.safeTransferFrom(msg.sender, address(this), amount0);
        token1.safeTransferFrom(msg.sender, address(this), amount1);

        // Re-assign to update local variables with actual transferred amounts
        amount0 = token0.balanceOf(address(this)) - bal0Before;
        amount1 = token1.balanceOf(address(this)) - bal1Before;

        if (totalSupply() > 0) {
            if (amount0 * reserve1 > amount1 * reserve0) {
                // Token0 is in surplus
                uint256 amount0Optimal = (amount1 * reserve0) / reserve1;
                uint256 excess0 = amount0 - amount0Optimal;

                // We actually want to swap the excess against the TOTAL reserves, not just the pre-existing.
                // But _getOptimalSwapAmount uses the RESERVE amount.
                // The surplus is effectively sitting "on top" of what would match.
                // We treat the "matching" part as if it's already paired, and we are zapping the "excess"
                // into a pool that consists of (reserve0 + matched0, reserve1 + matched1).
                // Except we can't easily separate them.
                // Simplified: we just want to swap enough of amount0 such that the remaining amount0 and the new amount1 match ratios.
                // It turns out optimal swap amount only depends on the *current* reserves logic if we treat the input as a "trade".

                uint256 swapAmount = _getOptimalSwapAmount(excess0, reserve0);
                uint256 amountOut = _swap(true, swapAmount, address(this));

                amount0 -= swapAmount;
                amount1 += amountOut;
            } else if (amount1 * reserve0 > amount0 * reserve1) {
                // Token1 is in surplus
                uint256 amount1Optimal = (amount0 * reserve1) / reserve0;
                uint256 excess1 = amount1 - amount1Optimal;

                uint256 swapAmount = _getOptimalSwapAmount(excess1, reserve1);
                uint256 amountOut = _swap(false, swapAmount, address(this));

                amount1 -= swapAmount;
                amount0 += amountOut;
            }
        }

        shares = _addLiquidity(amount0, amount1, msg.sender);
        require(shares >= minShares, "Insufficient shares");
    }

    /**
     * @dev Removes liquidity from the pool.
     * @param shares The amount of LP tokens to burn.
     * @return amount0 The amount of token0 received.
     * @return amount1 The amount of token1 received.
     */
    function removeLiquidity(uint256 shares) public nonReentrant returns (uint256 amount0, uint256 amount1) {
        require(shares > 0, "Shares must be positive");
        require(balanceOf(msg.sender) >= shares, "Insufficient LP tokens");

        // Calculate the amount of tokens to withdraw
        amount0 = (shares * reserve0) / totalSupply();
        amount1 = (shares * reserve1) / totalSupply();

        // Burn LP tokens (Effects)
        _burn(msg.sender, shares);

        // Update reserves (Effects)
        reserve0 -= amount0;
        reserve1 -= amount1;

        // Transfer tokens to the user (Interactions)
        token0.safeTransfer(msg.sender, amount0);
        token1.safeTransfer(msg.sender, amount1);

        emit Burn(msg.sender, amount0, amount1, msg.sender);
    }
}
