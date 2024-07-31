// SPDX-License-Identifier: MIT
// Handler is going to narrow down the way we call functions in the contract


pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "lib/ERC20Mock.sol";


contract Handler is Test {

    DSCEngine dsce;
    DecentralizedStableCoin dsc;

    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc) {
        dsce = _dsce;
        dsc = _dsc;
    }
    // in order to let know handler about the contract we are going to interact with we import it 
    // and init it during the deployment of the handler contract

    function depositCollateral(uint256 collateralSeed, uint256 amount) public {
        dsce.depositCollateral(collateral, amount);

    }


    fundtion _getCollateralFromSeed(uint256 collaterSeed) private view returns (ERC20Mock) {

    }

}