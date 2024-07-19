// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DecentralizedStableCoin
 * @author reverse_banana
 * @notice
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == 1 dollar peg
 *
 *
 * Our DSC system should always be "overcollateralized".
 * At no point, should be the value of all collateral <= the value of all the DSC stablecoins
 *
 * Is similar to Dai if Dai had no fees, and was only bach by weth and wbtc
 * @notice This contract is the core of the DSC Sytem.
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

    ////////////////////////////
    // State variables        //
    ////////////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION_1e10 = 1e10;
    uint256 private constant PRECISION_1e18 = 1e18;

    uint256 private constant LIQUIDATION_THRESHOLD = 50; 
    uint256 private constant LIQUIDATION_PRECISION = 100; 
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) private s_priceFeeds;
    // the default value for a bool is false. This means that in your mapping s_tokenToAllowed, all token addresses will map to false unless explicitly set to true.

    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    // mapping the user address to the token contract address, with the amount deposited

    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    // actual amounted of the dsc that is minted by a given user

    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    ////////////////////////////
    // Events              //
    ////////////////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    ////////////////////////////
    // Modifiers              //
    ////////////////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThatZero();
            _;
        }
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
            // creating key array of the s_priceFeeds mapping that we can loop thorught
            // to get the total deposite amount from all available tokens
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
        // DecentralizedStableCoin(dscAddress) converts the address dscAddress to a DecentralizedStableCoin contract type. which value assigns to the i_dsc
    }

    ////////////////////////////
    // External Functions     //
    ////////////////////////////

    function depositCollateralAndMintDsc() external {}

    /**
     * @notice follows CEI (checks, affects, interactions) pattern
     * @param  tokenCollateralAddress - address of the token that will be deposited as collateral
     * @param amountCollateral - amount of Collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
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

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    /**
     * @notice  follows CEI
     * @param amountDscToMint the amount stable coin to mint
     * @notice they must have more collateral value that minimum threshold
     */
    function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscToMint) {
        _revertIfHealthFactorIsBroken(msg.sender);
        s_DSCMinted[msg.sender] += amountDscToMint;
        // ask question about order of lines
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DCSEngine__MintFailed();
        }

    }

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    ////////////////////////////////////////
    // Privat & Internal view Functions  //
    ///////////////////////////////////////

    /**
     * @notice  returns how close to liquidations a user is
     * If  a user goes below 1, they can get liquidated
     *
     * @param user - address of the user which health factro we wanna fetch
     *
     * @dev - in order to get the health factoe we so=houdl compare the actual amount
     * of the fund that was minted and allocated in general for it we implement another nested function
     * that will return the that values for us to make calculation on
     *
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);

        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        // $150 ETH / 100 DCS = 1.5;
        // 150 * 50 = 7500 / 100 = (75 / 100) < 1;
        // (meaning the user have to be 200 collaralized)

        return (collateralAdjustedForThreshold * LIQUIDATION_PRECISION) / totalDscMinted;
        // 75 * 100 = 7500 / 100 = 75
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
        // will be a public function so other user could monitor health status and buy off the liquidation for each other
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
        return (uint256(price) * amount) / tokenDecimalsAmount;
        // since the eth and btc return a 1e8 decimal value we created a additional 1e10 value to bring the price  into 1e18 decimals format with we would multiply with actual amount and than substract the same 1e18 to get clean number
        // upd: to make the fucntion more flexible I fetch the decimals amount of the token pasted from the priceFeed and then divide it to get clean number (not tested yet)
    }
}
