// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DecentralisedStableCoin} from "src/DecentralisedStableCoin.sol";

contract TestDSC is Test {
    DeployDSC deployer;
    DecentralisedStableCoin dsc;
    address public USER = makeAddr("User");

    function setUp() public {
        dsc = new DecentralisedStableCoin();
    }

    function testMintDsc() public {
        vm.prank(dsc.owner());
        dsc.mint(USER, 1000);
        assert(dsc.balanceOf(USER) == 1000);
    }

    function testBurnDsc() public {
        vm.startPrank(dsc.owner());
        dsc.mint(dsc.owner(), 200);
        dsc.burn(200);
        vm.stopPrank();
    }
}
