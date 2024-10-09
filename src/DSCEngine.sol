// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal/private view & pure functions
// external/public view & pure functions

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/**
 * @title DSCEngine
 * @author 0xInkya
 * @notice
 * Properties:
 * 1. Relative stability: Pegged/Anchored to the USD
 * 2. Stability method: Algorithmic
 * 3. Collateral type: Exogenous (weth, wbtc)
 */
contract DSCEngine is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error DSCEngine__AmountMustBeGreaterThanZero();
    error DSCEngine__TokenCollateralAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TransferFailed();
    error DSCEngine__MintFailed();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__BreaksHealthFactor(uint256 userHealthFactor);
    error DSCEngine__HealthFactorOK(address user, uint256 startingUserHealthFactor);
    error DSCEngine__HealthFactorNotImproved();

    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    using OracleLib for AggregatorV3Interface;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus (since we are going to be dividing by 100, so 0.1)
    uint256 private constant MIN_HEALTH_FACTOR = 1e18; // 1e18 instead of 1 because of precision

    mapping(address collateralToken => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address collateralToken => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event CollateralDeposited(address indexed user, address indexed collateralToken, uint256 amountCollateral);
    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed collateralToken,
        uint256 amountCollateral
    );
    event DSCBurned(address indexed user, uint256 amountDsc);

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) revert DSCEngine__AmountMustBeGreaterThanZero();
        _;
    }

    modifier isAllowedCollateralToken(address collateralToken) {
        // checks to see if token is allowed by checking if it has a price feed
        if (s_priceFeeds[collateralToken] == address(0)) revert DSCEngine__TokenNotAllowed();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(address[] memory tokenCollateralAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenCollateralAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenCollateralAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenCollateralAddresses.length; i++) {
            s_collateralTokens.push(tokenCollateralAddresses[i]);
            s_priceFeeds[tokenCollateralAddresses[i]] = priceFeedAddresses[i];
        }

        i_dsc = DecentralizedStableCoin(dscAddress); // who deploys DSC?
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    function burnDscAndRedeemCollateral(uint256 amountDsc, address tokenCollateralAddress, uint256 amountCollateral)
        external
    {
        burnDsc(amountDsc);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    /**
     * @param collateralTokenAddress The ERC20 collateral address to liquidate from the user
     * @param user The user who has broken the health factor. Their _healthFactor should be below MIN_HEALTH_FACTOR
     * @param debtToCover The amount of DSC you want to burn to improve the users health factor
     * @notice You can partially liquidate a user.
     * @notice You will get a liquidation bonus for taking the users funds
     * @notice This function incentivices liquidators as long as the protocol is overcollateralized
     */
    function liquidate(address collateralTokenAddress, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOK(user, startingUserHealthFactor);
        }

        uint256 collateralAmountFromDebtCovered; // we don't want to just give 1:1 (debt:collateral) because we want to incentivize liquidators, so we will give a bonus

        // Example: 0.05 ETH * 0.1 (bonus / precision) = 0.005 ETH
        uint256 bonusCollateral = (collateralAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        // we want to give the liquidator the 1:1 collateral from debt covered + a bonus
        uint256 totalCollateralToRedeem = collateralAmountFromDebtCovered + bonusCollateral;

        _redeemCollateral(collateralTokenAddress, totalCollateralToRedeem, user, msg.sender);
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) revert DSCEngine__HealthFactorNotImproved();
        _revertIfHealthFactorIsBroken(msg.sender); // checks the liquidator's health factor
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        isAllowedCollateralToken(tokenCollateralAddress)
        moreThanZero(amountCollateral)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral); // why not transfer?
        if (!success) revert DSCEngine__TransferFailed();
    }

    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) revert DSCEngine__MintFailed();
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDsc(uint256 amountDsc) public moreThanZero(amountDsc) nonReentrant {
        _burnDsc(amountDsc, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // shouldnt be needed because we are repaying debt
    }

    /*//////////////////////////////////////////////////////////////
                           PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        _revertIfHealthFactorIsBroken(from); // isnt this order better?
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral); // same as transferFrom(from, to, amountCollateral)
        if (!success) revert DSCEngine__TransferFailed();
    }

    /**
     * @dev Low-level internal function, do not call unless the function calling it is checking for health factors being broken
     */
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        emit DSCBurned(msg.sender, amountDscToBurn);
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn); // we could send tokens directly to the 0 address but instead we first send it to our contract and then call the burn function from ERC20Burnable
        if (!success) revert DSCEngine__TransferFailed(); // hypotherically unreachable because if transferFrom fails it will throw its own error
        i_dsc.burn(amountDscToBurn);
    }

    /*//////////////////////////////////////////////////////////////
                 PRIVATE/INTERNAL VIEW & PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) revert DSCEngine__BreaksHealthFactor(userHealthFactor);
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 userDscMinted, uint256 userCollateralValueInUsd) = _getAccountInformation(user);

        // $150 ETH / 100 DSC
        // userCollateralValueInUsd -> collateralAdjustedForThreshold
        // ($150 ETH * 50) / 100 = 75
        // (75 / 100 DSC) < 1
        // UNDERCOLLATERALIZED (we only have 150% overcollateralization when 200% is required)

        return _calculateHealthFactor(userDscMinted, userCollateralValueInUsd);
    }

    function _calculateHealthFactor(uint256 userDscMinted, uint256 userCollateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (userDscMinted == 0) return type(uint96).max; // trying uint96 instead of uint256

        uint256 collateralAdjustedForThreshold =
            (userCollateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (collateralAdjustedForThreshold * PRECISION) / userDscMinted;
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 userDscMinted, uint256 userCollateralValueInUsd)
    {
        userDscMinted = s_DSCMinted[user];
        userCollateralValueInUsd = getUserCollateralValueInUsd(user);
    }

    /*//////////////////////////////////////////////////////////////
                 EXTERNAL/PUBLIC VIEW & PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * Opposite of getUsdValue
     */
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        // Example: ($10e18 * 1e18) / ($2000e8 * 1e10) = 0.05 ETH
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    /**
     * @notice Loops through all collateral token's amounts and gets their total USD value
     */
    function getUserCollateralValueInUsd(address user) public view returns (uint256 userCollateralValueInUsd) {
        uint256 collateralTokensLength = s_collateralTokens.length; // gas optimization

        for (uint256 i = 0; i < collateralTokensLength; i++) {
            address collateralToken = s_collateralTokens[i];
            uint256 amountCollateral = s_collateralDeposited[user][collateralToken];
            userCollateralValueInUsd += getUsdValue(collateralToken, amountCollateral);
        }
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        // If 1 ETH = $1000
        // The returned value from price feed will be 1000 * 1e8
        // Because CL's ETH / USD and BTC / USD price feeds have 8 decimals
        // https://docs.chain.link/data-feeds/price-feeds/addresses
        // We could check that we are using the right decimals but our only two collateral token price feeds have the same decimals

        // (not sure if the following is correct)
        // to put the amount in wei, we need to multiply by 1e18
        // so, if 1 ETH = $1000 and we have 1 ETH
        // price * amount would look like (1000 * 1e8) * (1 * 1e18)
        // but the decimals would be off, so we need to multiply the price by 1e10 like: (1000 * 1e8 * 1e10) * (1 * 1e18)

        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getCollateralTokenPriceFeed(address _collateralToken) external view returns (address) {
        return s_priceFeeds[_collateralToken];
    }

    function getCollateralDeposited(address _user, address _collateralToken) external view returns (uint256) {
        return s_collateralDeposited[_user][_collateralToken];
    }

    function getDSCMinted(address _user) external view returns (uint256) {
        return s_DSCMinted[_user];
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getAccountInformation(address _user)
        external
        view
        returns (uint256 userDscMinted, uint256 userCollateralValueInUsd)
    {
        (userDscMinted, userCollateralValueInUsd) = _getAccountInformation(_user);
    }

    function getUserHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getHealthFactor(uint256 userDscMinted, uint256 userCollateralValueInUsd) external pure returns (uint256) {
        return _calculateHealthFactor(userDscMinted, userCollateralValueInUsd);
    }
}
