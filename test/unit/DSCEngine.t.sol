// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployDsc} from "script/DeployDsc.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDsc deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig helperConfig;
    address ethUsdPriceFeed;
    address weth;
    address USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 100 ether;

    function setUp() public {
        deployer = new DeployDsc();
        (dsc, dscEngine, helperConfig) = deployer.run();
        // assigning the returned objects to the declared variables from the deployer.run function for futher use in test
        (ethUsdPriceFeed,, weth,,) = helperConfig.activeNetworkConfig();

        ERC20Mock(weth).mint((USER), STARTING_ERC20_BALANCE);

    }

    ////////////////////////////
    // Price Tests            //
    ////////////////////////////

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18; // 15 eth
        // 15e18 * 2000/eth = 30000e18;
        uint256 expectedUsdValue = 30000e18; // 15 * 2000
        uint256 actualUsdValue = dscEngine.getUsdValue(weth, ethAmount);

        assertEq(actualUsdValue, expectedUsdValue, "USD value of 15 eth should be 30000");
    }

    ////////////////////////////
    // Collateral Tests       //
    ////////////////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);

        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        // we telling the weth contract to approve the dscEngine contract to spend the AMOUNT_COLLATERAL by the user which we pranked
     
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThatZero.selector);
        // seems like the selector is used cause the expectrevert will check if the revert was done with the same selector which makes sense
        dscEngine.depositCollateral(weth, 0);
        // seems like it tranfers from the msg.sender name
        vm.stopPrank(); 
    }

}
