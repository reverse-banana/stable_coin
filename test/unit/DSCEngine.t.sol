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
    address btcUsdPriceFeed;
    address USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 100 ether;
    uint256 public constant INITIAL_BALANCE = 1000 ether;

    function setUp() public {
        deployer = new DeployDsc();
        (dsc, dscEngine, helperConfig) = deployer.run();
        // assigning the returned objects to the declared variables from the deployer.run function for futher use in test
        (ethUsdPriceFeed,, weth,,) = helperConfig.activeNetworkConfig();

        ERC20Mock(weth).mint((USER), STARTING_ERC20_BALANCE);
    }
    ////////////////////////////
    // Constructor test       //
    ////////////////////////////

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);  
        priceFeedAddresses.push(btcUsdPriceFeed);  
        // creating different in length arrays

        vm.expectRevert(DSCEngine.DCSEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLenght.selector);
        // stating that we arr expecting a revert with the selector to the custom error 
        
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc)); 
        //deploying a new DSCEngine contract with the different in length arrays  that declared at the start of the test
    }



    ////////////////////////////
    // Price Tests            //
    ////////////////////////////

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18; // 15 eth
        // 15e18 * 2000/eth = 30000e18;
        uint256 expectedUsdValue = 30000e18; // 15 * 2000
        uint256 actualUsdValue = dscEngine.getUsdValue(weth, ethAmount);
        // will give error wuth real fork url due to the dynamic actualUsdValue in that case

        assertEq(actualUsdValue, expectedUsdValue, "USD value of 15 eth should be 30000");
    }


    function testGetTokenAmountFronUsd() public {
        uint256 usdAmount = 30000e18; // 30000 usd
        // 30000 / 2000 = 15
        uint256 expectedTokenAmount = 15e18; // 30000 / 2000
        uint256 actualTokenAmount = dscEngine.getTokenAmountFromUsd(weth, usdAmount);
        // will give error wuth real fork url due to the dynamic actualTokenAmount in that case

        assertEq(actualTokenAmount, expectedTokenAmount, "Token amount for 30000 usd should be 15 eth");
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

    function testRevertsWithUnApprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, INITIAL_BALANCE);
        // creating a new erc20mock that isn't verified that we will try to deposit with

        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DCSEngine__NotAllowedToken.selector);
        dscEngine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        // attempting to deposit the AMOUNT_COLLATERAL of the ranToken that wasn't passed  to the contructor during intial deploy 
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        // we telling the weth contract to approve the dscEngine contract to spend the AMOUNT_COLLATERAL by the user which we pranked
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        // depositing the AMOUNT_COLLATERAL of weth to the dscEngine contract
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
        // getting the account information of the user

        uint256 expectedTotalDscMinted = 0;
        // uint256 expectedCollateralValueInUsd = 20000e18; // 10 * 2000

        uint256 expectedCollateralValueInUsd = dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL);

        uint256 expectedDepositAMount = dscEngine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        // kinda tricky part, where we are converting the usd value of the collateral which we are fetching from via _getAccountInformation to get the token amount of the collateral and comparing it to the AMOUNT_COLLATERAL

        assertEq(totalDscMinted, expectedTotalDscMinted, "Total DSC minted should be 0");
        assertEq(collateralValueInUsd, expectedCollateralValueInUsd, "Collateral value in USD should be 20000");
        assertEq(AMOUNT_COLLATERAL, expectedDepositAMount, "Deposit amount should be 10 eth");
    

    }



}
