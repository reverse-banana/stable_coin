// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/v0.8/interfaces/AggregatorV3Interface.sol";
import {console} from "forge-std/console.sol";

/**
 * @title DecentralizedStableCoin
 * @author reverse_banana
 * @notice
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == 1 dollar peg
 *
 * Our DSC system should always be "overcollateralized".
 * At no point, should be the value of all collateral <= the value of all the DSC stablecoins
 *
 * Is similar to Dai if Dai had no fees, and was only bach by weth and wbtc
 * @notice This contract is the core of the DSC System.
 * It handles all the logic for mining and reediming DSC, as well as depositing & withdrawing collateral
 * @notice This contract is VERY looosely based on the Maker DAO DSS (DAI) system
 */
contract DSCEngine is ReentrancyGuard {
    ////////////////////////////
    // Errors              //
    ////////////////////////////
    error DSCEngine__NeedsMoreThatZero();
    error DCSEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLenght();
    error DCSEngine__NotAllowedToken();
    error DCSEngine__TransferFailed();
    error DCSEngine__BreakHealthFactor(uint256 healthFactor);
    error DCSEngine__revertIfHealthFactorIsBroken(address user);
    error DCSEngine__MintFailed();
    error DCSEngine__HealthFactorOk(address user, uint256 healthFactor);
    error DCSEngine__HealthFactorNotImpoved(address user, uint256 healthFactor);

    ////////////////////////////
    // State variables        //
    ////////////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION_1e10 = 1e10;
    uint256 private constant PRECISION_1e18 = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;
    uint256 private constant LIQUIDATION_BONUS = 10; // ten percent bonus for the liquidator

    mapping(address token => address priceFeed) private s_priceFeeds;
    // the default value for a bool is false. This means that in your mapping s_tokenToAllowed, all token addresses will map to false unless explicitly set to true.
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    // mapping the user address to the token contract address, with the amount deposited
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    // actual amount of the dsc that is minted by a given user
    address[] private s_collateralTokens;
    DecentralizedStableCoin private immutable i_dsc;

    ////////////////////////////
    // Events              //
    ////////////////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    /**
     * notice: if (redeemFrom != redeemedTo), then it was liquidated
     */
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );
 

    ////////////////////////////
    // Modifiers              //
    ////////////////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThatZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DCSEngine__NotAllowedToken();
        }
        _;
    }

    ////////////////////////////
    // Functions              //
    ////////////////////////////

    /**
     * @param tokenAddresses array of tokenadresses that will mapped with pricefeeds
     * @param priceFeedAddresses array of the chainlink pricefeeds that will be napped with token addresses array correspondigly
     * @param dscAddress - address of the stablecoin contract instance
     */
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DCSEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLenght();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
            // ushing tokenaddresses to keep track for futher amount deosit calculations
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
        // DecentralizedStableCoin(dscAddress) converts the address dscAddress to a DecentralizedStableCoin contract type. which value assigns to the i_dsc
    }

    ///////////////////////////////////////
    // Public and external Functions     //
    //////////////////////////////////////

    /**
     * dev: the function is a wrapper for the depositCollateral and mintDsc functions
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

  
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        isAllowedToken(tokenCollateralAddress)
        moreThanZero(amountCollateral)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DCSEngine__TransferFailed();
        }
    }


    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) {
        _revertIfHealthFactorIsBroken(msg.sender);
        s_DSCMinted[msg.sender] += amountDscToMint;
        // ask question about order of lines
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DCSEngine__MintFailed();
        }
    }

    /**
     * dev: the function is a wrapper for the redeemCollateral and burntDsc functions
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // redeemingCollateral alredy check the health factor in itself
    }

    /**
     * notice: the function is utilizing the internal fucntion with advanced permissioning 
     * dev: the _redeeemCollateral collateral is able redeem the collateral from both msg.sender and any other user
     */

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        // due to the design of the function where we use from / to pair we making the tranfer from the msg.sender locked collaterall value of the hashmap (which pinned to his address) to his address (so the the msg.sender is the hash map key) and the second is the actual address we will send the funds
        _revertIfHealthFactorIsBroken(msg.sender);
        // even thought we tranferred the amount first (which isn't super clean logically) we adding the revert function at the end of the fucntion scope which will revert if something not right
    }



    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        // here we are burning the dsc from the user address
        // the seconds arguments the key pinter in the hash map to the minted amount balance from which we will subtract the amount
        // and the third argument is the actual address of the user that will be tranfering the dsc
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * notice: the fucntion main idea is keep the protocol overcollateralized by giving the remainder of the health-factor violators collateral amount to the user that liquidates them
     * notice: $100 eth => 50 dsc
     * notice: eth price drops making: $75 eth => 50 dsc (which violates the health factor criteria of the protocol)
     * notice: any user can liquidate the violator by paying $75 eth and burning 50 dsc
     * notice: which will give the liquidator 10 percent bonus of the collateral amount
     * @param tokenCollateralAddress - address of the user that will be liquidated
     * @param violator - address of the violator that will be liquidated
     * @param debtToCoverInUsd - amount of the dsc that will be burned (amount of the borrowed dsc)
     * notice: you can't partial liquidate a user
     * notice: know bug would be if the protocol were 100% or less collateralized, then we wouldn't be able to incentivize the liquidator
     * notice: $100 eth => 50 dsc
     * notice: eth price drops making: $20 eth => 50 dsc
     * notice: the liquidator would have to pay $50 to burn dsc and will get $20 eth worth of the collateral
     */

    function liquidate(address tokenCollateralAddress, address violator, uint256 debtToCoverInUsd)
        external
        moreThanZero(debtToCoverInUsd)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(violator);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DCSEngine__HealthFactorOk(violator, startingUserHealthFactor);
        }
        uint256 tokenAmountToCoverTheDebt = getTokenAmountFromUsd(tokenCollateralAddress, debtToCoverInUsd);
        uint256 bonusCollateral = (tokenAmountToCoverTheDebt * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        // is 10 percent of the tokenAmountToCoverTheDebt

        uint256 totalCollateralToRedeem = tokenAmountToCoverTheDebt + bonusCollateral;
        _redeemCollateral(violator, msg.sender, tokenCollateralAddress, totalCollateralToRedeem);
        _burnDsc(debtToCoverInUsd, violator, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(violator);
        if (endingUserHealthFactor <= MIN_HEALTH_FACTOR) {
            revert DCSEngine__HealthFactorNotImpoved(violator, endingUserHealthFactor);
        }

        _revertIfHealthFactorIsBroken(msg.sender);
        // checking if the liquidator health factor is okay
    }

    function getHealthFactor(address user) external view returns (uint256 healthFactor) {
            healthFactor = _healthFactor(user);
    }

    ////////////////////////////////////////
    // Privat & Internal view Functions  //
    ///////////////////////////////////////

    /**
     * notice: the main idea of the function is to create a modular way for both burning dsc from the msg.sender
     * notice: but also being able to reuse it in the liquidation function flow
     * @param amountDscToBurn  - amount of the dsc that will be burned
     * @param onBehalfOf  - address of the user from balance the amount will be substracted
     * @param dscFrom  - address of the user that will be burning the dsc
     */

    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        // subtracting the amount of the dsc from the user deposit hash map
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        // dscFrom sends tokens to the contract and the sended amount is substracted from the onBehalfOf address balance (aka paying off his debt)
        if (!success) {
            revert DCSEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
        // making the actual burn of the dsc
    }

    /**
     * notice: the main idea of the function is to create a modular way for both redeeming the collateral from the msg.sender
     * notice: but also being able to reuse it in the liquidation function flow
     * @param from  - address of the user from balance the amount will be substracted
     * @param to  - receiver of the collateral
     * @param tokenCollateralAddress - address of the token that will be redeemed
     * @param amountCollateral - amount of the token that will be redeemed
     */

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        // minus the amount of the collateral from the user deposit hash map
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(from, to, amountCollateral);
        if (!success) {
            revert DCSEngine__TransferFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
        // adding check if the user health factor is okay after redeeming the collateral
    }

    /**
     * notice: returns how close to liquidations a user is
     * @dev If a user goes below 1, they can get liquidated
     *
     * @param user - address of the user which health factro we wanna fetch
     *
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);

        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        // $150 ETH / 100 DCS = 1.5;
        // 150 * 50 = 7500 / 100 = (75 / 100) < 1;
        // (meaning the user have to be 200 collaralized)

        return (collateralAdjustedForThreshold * LIQUIDATION_PRECISION) / totalDscMinted;
        // (75 * 100 = 7500) / 100 = 75 which is less that 100
        // meaning the user is in the liquidation zone due to the health factor less that 1
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DCSEngine__BreakHealthFactor(userHealthFactor);
        }
    }

    //////////////////////////////////////////////
    // Public and External view  functions      //
    //////////////////////////////////////////////

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        uint8 tokenDecimalsAmount = priceFeed.decimals();
        // The amount is assumed to be in 18 decimals, adjust the price to match this decimal place.
        // Example: If priceFeedDecimals is 8 and the amount is in 18 decimals, we need to scale the price by 10^(18 - priceFeedDecimals).
        uint256 scaledPrice_1e18 = uint256(price) * 10 ** (18 - tokenDecimalsAmount);

        // we are multiplying the usdAmountInWei by 1e18 to get the amount in 18 decimals cause during substraction 1e18 will be gone
        return (usdAmountInWei * 1e18) / scaledPrice_1e18;
    }

    /**
     * @dev in order to get the full amount of the collateral of the given account
     * we have loop throught each collateral token, get the amount the have deposited in general
     */
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            // getting the token address at iterator index from the array we passed to constructor
            uint256 amount = s_collateralDeposited[user][token];
            // passing the iteration value of the token to the as the mappings key
            // and saving the amount value in the variable (but it's only the iterative token amount that sent not actual usd amount) for which we should define a fucntion

            totalCollateralValueInUsd += getUsdValue(token, amount);
            // will calucate the actual value of the iterated on token amount via getUsdValue func
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        uint8 tokenDecimalsAmount = priceFeed.decimals();
        // The amount is assumed to be in 18 decimals, adjust the price to match this decimal place.
        // Example: If priceFeedDecimals is 8 and the amount is in 18 decimals, we need to scale the price by 10^(18 - priceFeedDecimals).
        uint256 scaledPrice_1e18 = uint256(price) * 10 ** (18 - tokenDecimalsAmount);

        // Calculate USD value
        return (scaledPrice_1e18 * amount) / 1e18;
    }
    // since the eth and btc return a 1e8 decimal value we created a additional 1e10 value to bring the price  into 1e18 decimals format with we would multiply with actual amount and than substract the same 1e18 to get clean number
    // upd: to make the fucntion more flexible I fetch the decimals amount of the token pasted from the priceFeed and then divide it to get clean number (not tested yet)

    function getAccountInformation(address user) external view returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }
    // created a external visibility wrapper for the private function for the test purposes
    // seems that due to the private visibility we have explicitly define the returnrf values from the function

    //////////////////////////////////////////////
    // Test related getters                     //
    //////////////////////////////////////////////

    

}
