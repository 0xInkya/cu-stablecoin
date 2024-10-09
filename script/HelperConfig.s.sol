// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address weth;
        address wethUsdPriceFeed;
        address wbtc;
        address wbtcUsdPriceFeed;
        uint256 deployerKey;
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 40000e8;
    uint256 public constant DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 31337) activeNetworkConfig = getOrCreateAnvilNetworkConfig();
        else if (block.chainid == 11155111) activeNetworkConfig = getSepoliaEthConfig();
    }

    function getOrCreateAnvilNetworkConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) return activeNetworkConfig;

        vm.startBroadcast();
        ERC20Mock wethMock = new ERC20Mock("Wrapped Ether", "WETH", msg.sender, 1000e8);
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20Mock wbtcMock = new ERC20Mock("Wrapped Bitcoin", "WBTC", msg.sender, 1000e8);
        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
        vm.stopBroadcast();

        return NetworkConfig({
            weth: address(wethMock),
            wethUsdPriceFeed: address(ethUsdPriceFeed),
            wbtc: address(wbtcMock),
            wbtcUsdPriceFeed: address(btcUsdPriceFeed),
            deployerKey: DEFAULT_ANVIL_KEY
        });
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }
}
