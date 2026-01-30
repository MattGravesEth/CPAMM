// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title CPAMM
 * @dev A simple Constant Product Automated Market Maker.
 * This contract manages a liquidity pool of two ERC20 tokens and allows users to swap them.
 * It also issues LP (liquidity provider) tokens to users who provide liquidity.
 */
contract CPAMM is ERC20 {
    IERC20 public immutable token0;
    IERC20 public immutable token1;

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

    /**
     * @dev Swaps one token for another.
     * @param _tokenIn The address of the token being sent to the pool.
     * @param _amountIn The amount of the token being sent.
     * @param _minAmountOut The minimum amount of tokens to receive.
     * @param _deadline The timestamp after which the transaction will revert.
     * @return amountOut The amount of the other token received.
     */
    function swap(
        address _tokenIn,
        uint256 _amountIn,
        uint256 _minAmountOut,
        uint256 _deadline
    ) public returns (uint256 amountOut) {
        require(block.timestamp <= _deadline, "Transaction expired");
        require(
            _tokenIn == address(token0) || _tokenIn == address(token1),
            "Invalid token"
        );
        require(_amountIn > 0, "Amount in must be positive");

        bool isToken0 = _tokenIn == address(token0);
        (
            IERC20 tokenIn,
            IERC20 tokenOut,
            uint256 reserveIn,
            uint256 reserveOut
        ) = isToken0
                ? (token0, token1, reserve0, reserve1)
                : (token1, token0, reserve1, reserve0);

        // Transfer input tokens from user to the contract
        tokenIn.transferFrom(msg.sender, address(this), _amountIn);

        // Calculate output amount based on constant product formula (with a 0.3% fee)
        uint256 amountInWithFee = _amountIn * FEE_NUMERATOR;
        amountOut =
            (reserveOut * amountInWithFee) /
            (reserveIn * FEE_DENOMINATOR + amountInWithFee);

        require(amountOut >= _minAmountOut, "Insufficient output amount");

        // Update reserves (Effects)
        if (isToken0) {
            reserve0 += _amountIn;
            reserve1 -= amountOut;
        } else {
            reserve1 += _amountIn;
            reserve0 -= amountOut;
        }

        // Transfer output tokens to the user (Interactions)
        tokenOut.transfer(msg.sender, amountOut);
    }

    /**
     * @dev Adds liquidity to the pool.
     * @param _amount0 The amount of token0 to add.
     * @param _amount1 The amount of token1 to add.
     * @return shares The amount of LP tokens minted.
     */
    function addLiquidity(
        uint256 _amount0,
        uint256 _amount1
    ) public returns (uint256 shares) {
        // Pull tokens in (Interactions)
        token0.transferFrom(msg.sender, address(this), _amount0);
        token1.transferFrom(msg.sender, address(this), _amount1);

        // Calculate shares
        if (totalSupply() == 0) {
            // Initial liquidity provider
            shares = 100 ether; // Arbitrary starting supply
        } else {
            shares = (_amount0 * totalSupply()) / reserve0;
        }

        require(shares > 0, "shares = 0");

        // Mint LP tokens (Effects)
        _mint(msg.sender, shares);

        // Update reserves (Effects)
        reserve0 += _amount0;
        reserve1 += _amount1;
    }

    /**
     * @dev Removes liquidity from the pool.
     * @param _shares The amount of LP tokens to burn.
     * @return amount0 The amount of token0 received.
     * @return amount1 The amount of token1 received.
     */
    function removeLiquidity(
        uint256 _shares
    ) public returns (uint256 amount0, uint256 amount1) {
        require(_shares > 0, "Shares must be positive");
        require(balanceOf(msg.sender) >= _shares, "Insufficient LP tokens");

        // Calculate the amount of tokens to withdraw
        amount0 = (_shares * reserve0) / totalSupply();
        amount1 = (_shares * reserve1) / totalSupply();

        // Burn LP tokens (Effects)
        _burn(msg.sender, _shares);

        // Update reserves (Effects)
        reserve0 -= amount0;
        reserve1 -= amount1;

        // Transfer tokens to the user (Interactions)
        token0.transfer(msg.sender, amount0);
        token1.transfer(msg.sender, amount1);
    }
}
