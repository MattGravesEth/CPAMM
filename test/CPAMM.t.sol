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
    function test_constructor_setsTokens() public {
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
        assertEq(shares, 100 ether, "Initial shares should be 100 ether");
        assertEq(
            cpamm.balanceOf(USER),
            100 ether,
            "User LP balance should be 100 ether"
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
        assertEq(shares, 50 ether, "Shares should be proportional");
        assertEq(
            cpamm.balanceOf(USER),
            150 ether,
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
