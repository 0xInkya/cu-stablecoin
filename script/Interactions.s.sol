// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {DSCEngine, DecentralizedStableCoin} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DepositCollateral is Script {
    function depositCollateralUsingConfig(address dsce) public {
        HelperConfig config = new HelperConfig();
        (address weth, address wethUsdPriceFeed, address wbtc, address wbtcUsdPriceFeed, address signer) = config.activeNetworkConfig();
        
        depositCollateral(weth, signer, dsce);
    }

    function depositCollateral(address collateralTokenAddress, address signer, address dsce) public {
        vm.startBroadcast(signer);
        DSCEngine(dsceAddress).depositCollateral(collateralTokenAddress, 0.01 ether);
        vm.stopBroadcast();
    }

    function run() public {
        address dsce = DevOpsTools.get_most_recent_deployment("DSCEngine");
        // address dsc = DevOpsTools.get_most_recent_deployment("DecentralizedStableCoin");
        depositCollateralUsingConfig(dsce);
    }
}
