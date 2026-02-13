// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {CPAMM} from "../src/CPAMM.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";

contract DeployCPAMM is Script {
    function run() public returns (CPAMM) {
        // Get the private key from the environment for broadcasting
        //uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address token0Address;
        address token1Address;

        // Check the chain ID to determine which network we are on
        uint256 chainId = block.chainid;

        if (chainId == 11155111) {
            // Sepolia testnet
            console.log("Deploying to Sepolia...");
            token0Address = vm.envAddress("SEPOLIA_TOKEN0_ADDRESS");
            token1Address = vm.envAddress("SEPOLIA_TOKEN1_ADDRESS");
            require(token0Address != address(0), "SEPOLIA_TOKEN0_ADDRESS not set");
            require(token1Address != address(0), "SEPOLIA_TOKEN1_ADDRESS not set");
        } else if (chainId == 8453) {
            // Base Mainnet
            console.log("Deploying to Base Mainnet...");
            token0Address = vm.envAddress("BASE_TOKEN0_ADDRESS");
            token1Address = vm.envAddress("BASE_TOKEN1_ADDRESS");
            require(token0Address != address(0), "BASE_TOKEN0_ADDRESS not set");
            require(token1Address != address(0), "BASE_TOKEN1_ADDRESS not set");
        } else if (chainId == 84532) {
            // Base Sepolia
            console.log("Deploying to Base Sepolia...");
            token0Address = vm.envAddress("BASE_SEPOLIA_TOKEN0_ADDRESS");
            token1Address = vm.envAddress("BASE_SEPOLIA_TOKEN1_ADDRESS");
            require(token0Address != address(0), "BASE_SEPOLIA_TOKEN0_ADDRESS not set");
            require(token1Address != address(0), "BASE_SEPOLIA_TOKEN1_ADDRESS not set");
        } else {
            // Assume local network (Anvil, Hardhat, etc.)
            console.log("Deploying to local network...");
            // On a local network, deploy mock tokens first
            vm.startBroadcast();
            MockERC20 mockToken0 = new MockERC20("Mock Token 0", "MT0");
            MockERC20 mockToken1 = new MockERC20("Mock Token 1", "MT1");
            vm.stopBroadcast();
            token0Address = address(mockToken0);
            token1Address = address(mockToken1);
            console.log("Deployed MockToken0 at:", token0Address);
            console.log("Deployed MockToken1 at:", token1Address);
        }

        console.log("Deploying CPAMM with tokens:", token0Address, "and", token1Address);

        vm.startBroadcast();

        CPAMM cpamm = new CPAMM(token0Address, token1Address);

        vm.stopBroadcast();

        console.log("CPAMM deployed at:", address(cpamm));

        return cpamm;
    }
}
