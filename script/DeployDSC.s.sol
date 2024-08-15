// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {DecentralisedStableCoin} from "src/DecentralisedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
/**
 * @notice Deploy DSC deploys DecentralisedStableCoin Contract!
 */

contract DeployDSC is Script {
    address[] public priceFeedAddresses;
    address[] public tokenAddresses;

    function run() external returns (DecentralisedStableCoin, DSCEngine) {
        HelperConfig config = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            config.activeNetworkConfig();
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        DecentralisedStableCoin decentralisedStableCoin = new DecentralisedStableCoin();
        DSCEngine dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(decentralisedStableCoin));
        decentralisedStableCoin.transferOwnership(address(dscEngine));
        vm.stopBroadcast();

        return (decentralisedStableCoin, dscEngine);
    }
}
