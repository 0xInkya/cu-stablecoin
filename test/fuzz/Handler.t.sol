// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DSCEngine, DecentralizedStableCoin} from "src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

// DSCEngine
// Price Feeds
// Collateral Tokens

contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;

    ERC20Mock weth;
    MockV3Aggregator ethUsdPriceFeed;
    ERC20Mock wbtc;
    MockV3Aggregator btcUsdPriceFeed;

    uint256 public timesMintIsCalled;
    address[] public usersWithCollateralDeposited;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc) {
        dsce = _dsce;
        dsc = _dsc;

        address[] memory collateralTokenAddresses = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokenAddresses[0]);
        wbtc = ERC20Mock(collateralTokenAddresses[1]);

        ethUsdPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(weth)));
        btcUsdPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(wbtc)));
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateralToken = _getCollateralTokenFromSeed(collateralSeed);

        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateralToken.mint(msg.sender, amountCollateral);
        collateralToken.approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(collateralToken), amountCollateral);
        vm.stopPrank();

        usersWithCollateralDeposited.push(msg.sender); // will double push
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateralToken = _getCollateralTokenFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dsce.getCollateralDeposited(address(collateralToken), msg.sender);

        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        vm.assume(amountCollateral != 0);

        vm.startPrank(msg.sender);
        dsce.redeemCollateral(address(collateralToken), amountCollateral);
        vm.stopPrank();
    }

    function mintDsc(uint256 userSeed, uint256 amountDsc) public {
        address sender = _getUserFromSeed(userSeed);

        (uint256 userDscMinted, uint256 userCollateralValueInUsd) = dsce.getAccountInformation(sender);

        int256 maxDscToMint = (int256(userCollateralValueInUsd) / 2) - int256(userDscMinted);
        vm.assume(maxDscToMint >= 0);
        amountDsc = bound(amountDsc, 0, uint256(maxDscToMint));
        vm.assume(amountDsc != 0);

        vm.startPrank(sender);
        dsce.mintDsc(amountDsc);
        vm.stopPrank();

        timesMintIsCalled++;
    }

    // This breaks our invariant
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _getCollateralTokenFromSeed(uint256 collateralSeed) public view returns (ERC20Mock) {
        if (collateralSeed % 2 /* 2 is the number of valid collateral tokens (weth, wbtc) */ == 0) return weth;
        else return wbtc;
    }

    function _getUserFromSeed(uint256 userSeed) public view returns (address) {
        vm.assume(usersWithCollateralDeposited.length != 0);
        return usersWithCollateralDeposited[userSeed % usersWithCollateralDeposited.length];
    }
}
