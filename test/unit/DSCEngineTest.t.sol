// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console2} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract Unit is Test {
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;

    address public USER = makeAddr("USER");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;

    address weth;
    address wethUsdPriceFeed;
    address wbtc;
    address wbtcUsdPriceFeed;

    function setUp() public {
        DeployDSC deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (weth, wethUsdPriceFeed, wbtc, wbtcUsdPriceFeed,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, AMOUNT_COLLATERAL);
    }

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function testRevertsIfTokensArrayLengthDoesntMatchPriceFeedsArray() public {
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed];

        vm.expectRevert(DSCEngine.DSCEngine__TokenCollateralAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /*//////////////////////////////////////////////////////////////
                              PRICE TESTS
    //////////////////////////////////////////////////////////////*/
    function testGetUsdValue() public {
        uint256 ethAmount = 15e18; // 15 ETH
        // 15e18 * $2000/ETH = 30_000e18
        uint256 expectedUsd = 30_000e18; // will fail in sepolia
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether; // $100
        // $2,000 / ETH, $100 = 0.05 ETH
        uint256 expectedWeth = 0.05 ether; // will fail in sepolia
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/
    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("Random", "RAN", USER, AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        vm.prank(USER);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
    }

    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeGreaterThanZero.selector);
        dsce.depositCollateral(weth, 0);
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 userDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);

        uint256 expectedUserDscMinted = 0;
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);

        assertEq(userDscMinted, expectedUserDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }
}
