// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title CPAMM
 * @dev A simple Constant Product Automated Market Maker.
 * This contract manages a liquidity pool of two ERC20 tokens and allows users to swap them.
 * It also issues LP (liquidity provider) tokens to users who provide liquidity.
 */
contract CPAMM {
    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint256 public reserve0;
    uint256 public reserve1;

    uint256 public totalSupply; // Total LP tokens
    mapping(address => uint256) public balanceOf; // LP token balances

    /**
     * @dev Sets the two tokens for the liquidity pool.
     * @param _token0 Address of the first ERC20 token.
     * @param _token1 Address of the second ERC20 token.
     */
    constructor(address _token0, address _token1) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }

    /**
     * @dev Updates the token reserves of the pool.
     */
    function _update() private {
        reserve0 = token0.balanceOf(address(this));
        reserve1 = token1.balanceOf(address(this));
    }

    /**
     * @dev Mints LP tokens to a user.
     * @param to The address to mint LP tokens to.
     * @param amount The amount of LP tokens to mint.
     */
    function _mint(address to, uint256 amount) private {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    /**
     * @dev Burns LP tokens from a user.
     * @param from The address to burn LP tokens from.
     * @param amount The amount of LP tokens to burn.
     */
    function _burn(address from, uint256 amount) private {
        balanceOf[from] -= amount;
        totalSupply -= amount;
    }

    /**
     * @dev Swaps one token for another.
     * @param _tokenIn The address of the token being sent to the pool.
     * @param _amountIn The amount of the token being sent.
     * @return amountOut The amount of the other token received.
     */
    function swap(address _tokenIn, uint256 _amountIn) public returns (uint256 amountOut) {
        require(_tokenIn == address(token0) || _tokenIn == address(token1), "Invalid token");
        require(_amountIn > 0, "Amount in must be positive");

        (IERC20 tokenIn, IERC20 tokenOut, uint256 reserveIn, uint256 reserveOut) = 
            (_tokenIn == address(token0)) ? (token0, token1, reserve0, reserve1) : (token1, token0, reserve1, reserve0);

        // Transfer input tokens from user to the contract
        tokenIn.transferFrom(msg.sender, address(this), _amountIn);

        // Calculate output amount based on constant product formula (with a 0.3% fee)
        uint256 amountInWithFee = _amountIn * 997;
        amountOut = (reserveOut * amountInWithFee) / (reserveIn * 1000 + amountInWithFee);

        // Transfer output tokens to the user
        tokenOut.transfer(msg.sender, amountOut);

        _update();
    }

    /**
     * @dev Adds liquidity to the pool.
     * @param _amount0 The amount of token0 to add.
     * @param _amount1 The amount of token1 to add.
     * @return shares The amount of LP tokens minted.
     */
    function addLiquidity(uint256 _amount0, uint256 _amount1) public returns (uint256 shares) {
        token0.transferFrom(msg.sender, address(this), _amount0);
        token1.transferFrom(msg.sender, address(this), _amount1);

        if (totalSupply == 0) {
            // Initial liquidity provider
            shares = 100 ether; // Arbitrary starting supply
        } else {
            shares = (_amount0 * totalSupply) / reserve0;
        }

        _mint(msg.sender, shares);
        _update();
    }

    /**
     * @dev Removes liquidity from the pool.
     * @param _shares The amount of LP tokens to burn.
     * @return amount0 The amount of token0 received.
     * @return amount1 The amount of token1 received.
     */
    function removeLiquidity(uint256 _shares) public returns (uint256 amount0, uint256 amount1) {
        require(_shares > 0, "Shares must be positive");
        require(balanceOf[msg.sender] >= _shares, "Insufficient LP tokens");

        // Calculate the amount of tokens to withdraw
        amount0 = (_shares * reserve0) / totalSupply;
        amount1 = (_shares * reserve1) / totalSupply;

        // Transfer tokens to the user
        token0.transfer(msg.sender, amount0);
        token1.transfer(msg.sender, amount1);

        // Burn LP tokens
        _burn(msg.sender, _shares);
        _update();
    }

    /**
     * @dev Returns the amount of LP tokens held by a specific address.
     * @param _owner The address to query.
     * @return The LP token balance of the address.
     */
    function getLPTokens(address _owner) public view returns (uint256) {
        return balanceOf[_owner];
    }
}
