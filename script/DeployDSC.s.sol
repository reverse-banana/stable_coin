// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployDsc is Script {
    DSCEngine dscEngine;
    DecentralizedStableCoin decentralizedStableCoin;

    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig(); // This comes with our mocks!

        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            helperConfig.activeNetworkConfig();
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        decentralizedStableCoin = new DecentralizedStableCoin();
        dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(decentralizedStableCoin));
        decentralizedStableCoin.transferOwnership(address(dscEngine));
        // tranferring ownership to dscEngine, since the initial owner is msg.sender
        vm.stopBroadcast();
        return (decentralizedStableCoin, dscEngine, helperConfig);
        // returning the deployed contracts for further use in test as well as HelperConfig
    }
}
