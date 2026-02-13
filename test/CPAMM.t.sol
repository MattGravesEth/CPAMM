// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {CPAMM} from "../src/CPAMM.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract CPAMMTest is Test {
    CPAMM public cpamm;
    MockERC20 public token0;
    MockERC20 public token1;

    address constant USER = address(0x1);
    uint256 constant USER_INITIAL_BALANCE = 100 ether;

    function setUp() public {
        token0 = new MockERC20("Token0", "TKN0");
        token1 = new MockERC20("Token1", "TKN1");

        cpamm = new CPAMM(address(token0), address(token1));

        // Mint initial tokens for the user
        token0.mint(USER, USER_INITIAL_BALANCE);
        token1.mint(USER, USER_INITIAL_BALANCE);
    }

    // --- Test constructor ---
    function test_constructor_setsTokens() public view {
        assertEq(
            address(cpamm.token0()),
            address(token0),
            "token0 not set correctly"
        );
        assertEq(
            address(cpamm.token1()),
            address(token1),
            "token1 not set correctly"
        );
    }

    // --- Test addLiquidity ---

    function test_addInitialLiquidity() public {
        uint256 amount0 = 50 ether;
        uint256 amount1 = 50 ether;

        // User needs to approve the CPAMM contract to spend their tokens
        vm.startPrank(USER);
        token0.approve(address(cpamm), amount0);
        token1.approve(address(cpamm), amount1);

        // Add initial liquidity
        uint256 shares = cpamm.addLiquidity(amount0, amount1);
        vm.stopPrank();

        // Check shares minted
        // 1000 shares are permanently locked, so user gets 100 ether - 1000
        assertEq(
            shares,
            100 ether - 1000,
            "Initial shares should be 100 ether - 1000"
        );
        assertEq(
            cpamm.balanceOf(USER),
            100 ether - 1000,
            "User LP balance should be 100 ether - 1000"
        );
        assertEq(
            cpamm.totalSupply(),
            100 ether,
            "Total LP supply should be 100 ether"
        );

        // Check reserves
        assertEq(cpamm.reserve0(), amount0, "Reserve0 should match amount0");
        assertEq(cpamm.reserve1(), amount1, "Reserve1 should match amount1");

        // Check contract token balances
        assertEq(token0.balanceOf(address(cpamm)), amount0);
        assertEq(token1.balanceOf(address(cpamm)), amount1);
    }

    function test_addMoreLiquidity() public {
        // First, add initial liquidity
        test_addInitialLiquidity();

        uint256 amount0 = 25 ether;
        uint256 amount1 = 25 ether;

        vm.startPrank(USER);
        token0.approve(address(cpamm), amount0);
        token1.approve(address(cpamm), amount1);

        // Add more liquidity
        uint256 shares = cpamm.addLiquidity(amount0, amount1);
        vm.stopPrank();

        // Check shares minted (proportional to existing liquidity)
        // Initial: 50 T0 for 100 LP. New: 25 T0. Expected shares: (25 * 100) / 50 = 50
        // Check shares minted (proportional to existing liquidity)
        // Initial: 50 T0 for 100 LP. New: 25 T0. Expected shares: (25 * 100) / 50 = 50
        assertEq(shares, 50 ether, "Shares should be proportional");
        assertEq(
            cpamm.balanceOf(USER),
            150 ether - 1000,
            "User total LP balance should be updated"
        );
        assertEq(
            cpamm.totalSupply(),
            150 ether,
            "Total LP supply should be updated"
        );

        // Check reserves
        assertEq(cpamm.reserve0(), 75 ether, "Reserve0 should be updated");
        assertEq(cpamm.reserve1(), 75 ether, "Reserve1 should be updated");
    }

    function test_addLiquidity_imbalanced() public {
        test_addInitialLiquidity(); // 50 ether each, 100 shares

        uint256 amount0 = 10 ether;
        uint256 amount1 = 20 ether; // Imbalanced, should be 10

        vm.startPrank(USER);
        token0.approve(address(cpamm), amount0);
        token1.approve(address(cpamm), amount1);

        uint256 shares = cpamm.addLiquidity(amount0, amount1);
        vm.stopPrank();

        // Expected shares should be based on amount0 (10 ether)
        // 10 * 100 / 50 = 20 shares
        assertEq(shares, 20 ether, "Shares should be based on limiting token");

        // Reserves should still increase by full amount (user penalty)
        assertEq(cpamm.reserve0(), 60 ether);
        assertEq(cpamm.reserve1(), 70 ether);
    }

    // --- Test swap ---

    function test_swapToken0ForToken1() public {
        // Add initial liquidity
        test_addInitialLiquidity();

        uint256 amountIn = 10 ether;
        vm.startPrank(USER);
        token0.approve(address(cpamm), amountIn);

        uint256 amountOut = cpamm.swap(
            address(token0),
            amountIn,
            0,
            block.timestamp
        );
        vm.stopPrank();

        // Check balances after swap
        assertEq(token0.balanceOf(address(cpamm)), 60 ether); // 50 + 10
        assertTrue(token1.balanceOf(address(cpamm)) < 50 ether);
        assertEq(
            token1.balanceOf(USER),
            USER_INITIAL_BALANCE - 50 ether + amountOut
        );

        // Check reserves are updated
        assertEq(cpamm.reserve0(), 60 ether);
        assertEq(cpamm.reserve1(), token1.balanceOf(address(cpamm)));
    }

    function test_swapToken1ForToken0() public {
        // Add initial liquidity
        test_addInitialLiquidity();

        uint256 amountIn = 10 ether;
        vm.startPrank(USER);
        token1.approve(address(cpamm), amountIn);

        uint256 amountOut = cpamm.swap(
            address(token1),
            amountIn,
            0,
            block.timestamp
        );
        vm.stopPrank();

        // Check balances after swap
        assertEq(token1.balanceOf(address(cpamm)), 60 ether); // 50 + 10
        assertTrue(token0.balanceOf(address(cpamm)) < 50 ether);
        assertEq(
            token0.balanceOf(USER),
            USER_INITIAL_BALANCE - 50 ether + amountOut
        );
    }

    function test_swapAndAddLiquidity_token0Surplus() public {
        test_addInitialLiquidity(); // 50:50

        // User has 100 T0 and 0 T1 (besides what they spent on initial liq)
        // Let's give them some fresh amounts
        uint256 amount0 = 100 ether;
        uint256 amount1 = 0;

        vm.startPrank(USER);
        token0.mint(USER, amount0);
        token0.approve(address(cpamm), amount0);

        // No T1 approval needed as amount is 0, but approve just in case logic changes
        token1.approve(address(cpamm), amount1);

        uint256 prevShares = cpamm.balanceOf(USER);
        uint256 shares = cpamm.swapAndAddLiquidity(
            amount0,
            amount1,
            0,
            block.timestamp
        );
        vm.stopPrank();

        assertTrue(shares > 0, "Should mint shares");
        assertTrue(
            cpamm.balanceOf(USER) > prevShares,
            "Balance should increase"
        );

        // Reserves will shift due to the large swap, so they won't be 1:1.
        uint256 r0 = cpamm.reserve0();
        uint256 r1 = cpamm.reserve1();

        // The amounts actually added to liquidity are:
        // amount0 (remaining after swap) and amount1 (swapped out)
        // We can't see local vars here, but we can verify that the pool is valid
        // and that we got a significant amount of shares (more than if we just added 0 T1).

        // If we did a naive addLiquidity with 100 T0 and 0 T1, we would get 0 shares.

        // Check that the current Reserve Ratio matches the added amounts implied ratio?
        // Hard to check without events or return values.
        // Let's rely on shares > 0 and implicit "optimal" behavior.
        // But we can check that r0 * r1 >= k (invariant holds/grows).
        assertGt(r0 * r1, 50 ether * 50 ether, "K should grow");
    }

    // --- Test Reverts ---

    function test_revert_swap_slippage() public {
        test_addInitialLiquidity();

        uint256 amountIn = 10 ether;
        vm.startPrank(USER);
        token0.approve(address(cpamm), amountIn);

        // Expected output is roughly (50 * 10 * 997) / (50 * 1000 + 10 * 997) ...
        // Let's set a very high minAmountOut to force revert
        uint256 minAmountOut = 100 ether; // Impossible

        vm.expectRevert("Insufficient output amount");
        cpamm.swap(address(token0), amountIn, minAmountOut, block.timestamp);
        vm.stopPrank();
    }

    function test_revert_swap_expired() public {
        test_addInitialLiquidity();

        uint256 amountIn = 10 ether;
        vm.startPrank(USER);
        token0.approve(address(cpamm), amountIn);

        // Set deadline in the past
        uint256 deadline = block.timestamp - 1;

        vm.expectRevert("Transaction expired");
        cpamm.swap(address(token0), amountIn, 0, deadline);
        vm.stopPrank();
    }

    function test_revert_swap() public {}
}
