// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {CPAMMTest} from "./CPAMM.t.sol";

contract CPAMMFuzzTest is CPAMMTest {
    function testFuzz_addLiquidity(uint256 amount0, uint256 amount1) public {
        vm.assume(amount0 > 1000 && amount0 < 1e30);
        vm.assume(amount1 > 1000 && amount1 < 1e30);

        vm.startPrank(USER);
        token0.mint(USER, amount0);
        token1.mint(USER, amount1);
        token0.approve(address(cpamm), amount0);
        token1.approve(address(cpamm), amount1);

        uint256 shares = cpamm.addLiquidity(amount0, amount1);
        vm.stopPrank();

        assertGt(shares, 0, "Shares should be minted");
        assertLe(shares, cpamm.totalSupply(), "Shares <= Total Supply");
    }

    function testFuzz_swap(uint256 amountIn, bool swap0For1) public {
        test_addInitialLiquidity(); // Setup initial pool state

        // amountIn must be large enough to produce at least 1 unit of output
        // and small enough to not overflow reserves significantly
        vm.assume(amountIn > 1000 && amountIn < 1e30);

        vm.startPrank(USER);
        if (swap0For1) {
            token0.mint(USER, amountIn);
            token0.approve(address(cpamm), amountIn);
            uint256 amountOut = cpamm.swap(address(token0), amountIn, 0, block.timestamp);
            assertGt(amountOut, 0, "Swap output should be > 0");
        } else {
            token1.mint(USER, amountIn);
            token1.approve(address(cpamm), amountIn);
            uint256 amountOut = cpamm.swap(address(token1), amountIn, 0, block.timestamp);
            assertGt(amountOut, 0, "Swap output should be > 0");
        }
        vm.stopPrank();
    }

    function testFuzz_removeLiquidity(uint256 amount0, uint256 amount1, uint256 sharesToBurn) public {
        // Increase minimum amounts to ensure we get > 0 shares and > 0 output
        vm.assume(amount0 > 100000 && amount0 < 1e30);
        vm.assume(amount1 > 100000 && amount1 < 1e30);

        // Setup: user adds liquidity
        vm.startPrank(USER);
        token0.mint(USER, amount0);
        token1.mint(USER, amount1);
        token0.approve(address(cpamm), amount0);
        token1.approve(address(cpamm), amount1);
        uint256 shares = cpamm.addLiquidity(amount0, amount1);

        // Fuzz constraint: burn amount <= shares owned
        // We modulate sharesToBurn to be within [MINIMUM_LIQUIDITY, shares]
        // If shares are too low, skip
        if (shares <= 1000) return;

        // Ensure we burn enough shares to get at least 1 unit of each token
        // amount = (shares * reserve) / totalSupply; amount >= 1 => shares * reserve >= totalSupply
        // So shares >= totalSupply / reserve
        if (cpamm.reserve0() == 0 || cpamm.reserve1() == 0) return;
        uint256 minSharesForToken0 = (cpamm.totalSupply() + cpamm.reserve0() - 1) / cpamm.reserve0();
        uint256 minSharesForToken1 = (cpamm.totalSupply() + cpamm.reserve1() - 1) / cpamm.reserve1();
        uint256 minShares = minSharesForToken0 > minSharesForToken1 ? minSharesForToken0 : minSharesForToken1;

        // Add a buffer to be safe and ensure > 0
        minShares += 1000;

        if (shares < minShares) return;

        sharesToBurn = bound(sharesToBurn, minShares, shares);

        uint256 bal0Before = token0.balanceOf(USER);
        uint256 bal1Before = token1.balanceOf(USER);

        (uint256 out0, uint256 out1) = cpamm.removeLiquidity(sharesToBurn);
        vm.stopPrank();

        assertGt(out0, 0, "Output0 should be > 0");
        assertGt(out1, 0, "Output1 should be > 0");
        assertEq(token0.balanceOf(USER), bal0Before + out0);
        assertEq(token1.balanceOf(USER), bal1Before + out1);
    }

    function testFuzz_swapAndAddLiquidity(uint256 amount0, uint256 amount1) public {
        test_addInitialLiquidity(); // Setup initial pool

        // Use reasonable limits to avoid overflow in calculations
        // The error appeared with amount1 ~ 1.7e70, which when multiplied by reserves overflows
        vm.assume(amount0 > 1000 && amount0 < 1e25);
        vm.assume(amount1 > 0 && amount1 < 1e25);

        vm.startPrank(USER);
        token0.mint(USER, amount0);
        token1.mint(USER, amount1);
        token0.approve(address(cpamm), amount0);
        token1.approve(address(cpamm), amount1);

        // We use fuzzing to test that it doesn't revert and mints shares
        // for valid inputs where at least one token is provided
        if (amount0 == 0 && amount1 == 0) return;

        uint256 shares = cpamm.swapAndAddLiquidity(amount0, amount1, 0, block.timestamp);
        vm.stopPrank();

        assertGt(shares, 0, "Shares should be minted");
    }
}
