// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

// Invariants
// 1. The total supply of DSC should be less than the total value of collateral
// 2. Getter functions should never revert

import {StdInvariant, Test, console2} from "forge-std/Test.sol";
import {DeployDSC, HelperConfig} from "script/DeployDSC.s.sol";
import {DecentralizedStableCoin, DSCEngine} from "src/DSCEngine.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract Invariants is StdInvariant, Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    Handler handler;

    address weth;
    address wbtc;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (weth,, wbtc,,) = config.activeNetworkConfig();
        handler = new Handler(dsce, dsc);
        targetContract(address(handler));
    }

    function invariant_totalCollateralValueInUsdMustBeGreaterThanTotalDscSupply() public view {
        uint256 totalDscSupply = dsc.totalSupply();

        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsce));
        uint256 totalWethValue = dsce.getUsdValue(weth, totalWethDeposited);
        uint256 totalWbtcValue = dsce.getUsdValue(wbtc, totalWbtcDeposited);
        uint256 totalCollateralValue = totalWethValue + totalWbtcValue;

        console2.log("Times mint is called: ", handler.timesMintIsCalled());

        assert(totalCollateralValue >= totalDscSupply); // we make it bigger or equal to instead of strictly bigger because if we dont deposit then totalCollateralValue and totalDscSupply will be 0
    }

    function invariant_gettersShouldNotRevert() public view {
        // code here
    }
}
