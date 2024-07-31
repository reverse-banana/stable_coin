// SPDX-License-Identifier: MIT


pragma solidity ^0.8.19;    

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DeployDsc} from "../script/DeployDSC.s.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";   
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Handler} from "test/Handler.t.sol";


contract InvariantTest is StdInvariant, Test {
    
    DeployDsc deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;  
    Handler handler;
    
    function setUp() public {
        deployer = new DeployDsc();
        (dsc, dsce, config) = deployer.run();
        (, , weth, wbtc, ) = config.activeNetworkConfig();
        handler = new Handler(dsce, dsc);
        // passing needed args to handler contructor during init
        targetContract(address(handler));
        // telling foundry go wild on this (open invariant testing)
    }   

    function invariant_protocolMustHaveMoreValueThatTotalSupply() public view {
        // get the value of the all the collateral deposited in the protocol
        // compare it with the total supply of the DSC (debt)

        uint256 totalSupply = dsc.totalSupply();
        uint256 totatWethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totatWbtcDeposited = IERC20(wbtc).balanceOf(address(dsce));

        uint256 wethValue = dsce.getUsdValue(weth, totatWethDeposited);
        uint256 wbtcValue = dsce.getUsdValue(wbtc, totatWbtcDeposited);

        assert(wethValue + wbtcValue >= totalSupply);
        // checking total collateral value is equal or greater than  total supply (aka debt)
        // equal here needed for the option where the prototcol have zero debt
    }
}


