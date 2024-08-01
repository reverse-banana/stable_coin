// SPDX-License-Identifier: MIT
// Handler is going to narrow down the way we call functions in the contract

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DeployDsc} from "script/DeployDsc.s.sol";

contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    DeployDsc deployer;
    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timeMintIsCalled;
    uint96 public constant MAX_DEPOSIT_SIZE = type(uint96).max;
    
    address[] public usersWithCollateral;
    // uint256 max option isn't use to have to the edge to deposit even more in future

    // function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig)

    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc) {
        dsce = _dsce;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
        console.log("Handler: weth address:", address(weth));
        console.log("Handler: wbtc address:", address(wbtc));
    }
    // in order to let know handler about the contract we are going to interact with we import it
    // and init it during the deployment of the handler contract


    function mintDsc(uint256 amount) public {


        (uint256 totalDscminted, uint256 totalCollateralValue) = dsce.getAccountInformation(msg.sender);
        int256 maxAmount = (int256(totalCollateralValue / 2) - int256(totalDscminted));
        // due to the 2:1 ratio of the collateral to the minted DSC rule
        
        if (amount < 0) {
            return;
        }
        
    
        // if the maxDscToMint is less than or equal to zero then we don't mint any DSC
        amount = bound(amount, 0, uint256(maxAmount));
        if (amount == 0) {
            return;
        }
        timeMintIsCalled++;

        vm.startPrank(address(dsce));
        // pranking being the dsce whi is the owner of the dsc with the .owner() cheatcode
        dsc.mint(msg.sender, amount);
        vm.stopPrank();
    }


    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {

        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        console.log("Supply amount:", collateral.totalSupply());
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        // bounding our amount to be somenthing between 1 and the max uint96 range value

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        // minting the tokens cause how else we gonna send them to the contract
        collateral.approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        usersWithCollateral.push(msg.sender);
    }


    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        uint256 maxCollateralToRedeem = dsce.getCollateralBalanceOfUser(msg.sender, address(collateral));

        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        // bounding our amount to be somenthing between 0 and the max balance of the user
        // giving the zero cause in cause user don't have any collateral at the given address
        //the maxCollateralToRedeem will be zero will be zero also whichi will break the bound
        if (amountCollateral == 0) {
            return;
            // just return means quit from the function and don't call the redeem fucntion
        }


        vm.startPrank(msg.sender);
        dsce.redeemCollateral(address(collateral), amountCollateral);

    }

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock collateral) {
        // getting the index from the seed via the modulo operator
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }

}
