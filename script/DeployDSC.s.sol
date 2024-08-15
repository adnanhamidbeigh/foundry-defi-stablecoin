// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {DecentralisedStableCoin} from "src/DecentralisedStableCoin.sol";
/**
 * @notice Deploy DSC deploys DecentralisedStableCoin Contract!
 */

contract DeployDSC is Script {
    function run() external returns (DecentralisedStableCoin) {
        vm.startBroadcast();
        DecentralisedStableCoin decentralisedStableCoin = new DecentralisedStableCoin();
        vm.stopBroadcast();
        return (decentralisedStableCoin);
    }
}
