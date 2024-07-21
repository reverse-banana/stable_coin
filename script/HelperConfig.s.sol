// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DeployDsc} from "script/DeployDsc.s.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    uint8 constant DECIMALS = 8;
    int256 constant ETH_USD_PRICE = 2000e8;
    int256 constant BTC_USD_PRICE = 10000e8;
    uint256 public DEFAULT_SEPOLIA_KEY = 0x6701d2bc4b7381e0b7803817c021269aed40abf4db4f8d4f26bf810689f18735;
    uint256 public DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    struct NetworkConfig {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployerKey: DEFAULT_SEPOLIA_KEY
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20Mock weth = new ERC20Mock("Wrapped Ether", "WETH", msg.sender, 100e18);

        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
        ERC20Mock wbtc = new ERC20Mock("Wrapped Bitcoin", "WBTC", msg.sender, 1000e18);
        vm.stopBroadcast();

        return NetworkConfig({
            wethUsdPriceFeed: address(ethUsdPriceFeed),
            wbtcUsdPriceFeed: address(btcUsdPriceFeed),
            weth: address(weth),
            wbtc: address(wbtc),
            deployerKey: DEFAULT_ANVIL_KEY
        });
    }
}

/**
 * Certainly! Here's a summary of the key points for your notes:
 *
 * 1. Blockchain Contract State:
 *    - Unlike Web2, each deployment of a smart contract creates a new instance with fresh state.
 *    - State doesn't persist between different networks or redeployments.
 *
 * 2. HelperConfig Contract Logic:
 *    - Constructor determines the network (Sepolia or Anvil) and sets appropriate config.
 *    - Sepolia: Always returns static configuration.
 *    - Anvil: Uses dynamic logic to create or reuse mock contracts.
 *
 * 3. Anvil Configuration Behavior:
 *    - First call: Creates new mock contracts.
 *    - Subsequent calls: Reuses existing mock contracts.
 *    - Purpose: Avoid redundant mock creation within a single Anvil session.
 *
 * 4. Network Isolation:
 *    - Configurations for different networks (e.g., Sepolia, Anvil) are completely separate.
 *    - Deploying to a new network always starts with a clean slate.
 *
 * 5. Key Takeaway:
 *    - The check `if (activeNetworkConfig.wethUsdPriceFeed != address(0))` in Anvil config:
 *      - Doesn't prevent mixing configs from different networks (impossible due to separate deployments).
 *      - Ensures efficiency by creating mocks only once per Anvil session.
 *
 * This design allows for flexible testing and deployment across different networks while maintaining efficiency in local development environments.
 *
 *  You're absolutely correct, and I'm glad you're seeking to cement this understanding. Let's verify and clarify this point:
 *
 * You're right on target. When you deploy to Anvil a second time (or any number of times after the first), each deployment is indeed completely fresh and isolated. This means:
 *
 * 1. In this second (or any subsequent) deploy to Anvil:
 *    - The contract starts with a completely blank slate.
 *    - `activeNetworkConfig` is uninitialized at the start of the deployment.
 *    - `activeNetworkConfig.wethUsdPriceFeed` will indeed be `address(0)` initially.
 *
 * 2. The constructor will run again, calling `getOrCreateAnvilEthConfig()`.
 *
 * 3. Inside `getOrCreateAnvilEthConfig()`, the check `if (activeNetworkConfig.wethUsdPriceFeed != address(0))` will fail because it is indeed `address(0)`.
 *
 * 4. As a result, new mock contracts will be created for this fresh deployment.
 *
 * 5. This process repeats for every new deployment, even on the same network (Anvil in this case).
 *
 * You're absolutely correct that each deploy is isolated from each other, even on the same network. The state from the previous Anvil deployment doesn't carry over to the new one.
 *
 * This reinforces the key concept: in blockchain development, each contract deployment, regardless of how many times you've deployed to that network before, starts fresh. The logic for reusing mocks only applies within a single deployed instance of the contract, not across multiple deployments.
 *
 * Excellent observation! You've truly grasped the concept now.
 */
