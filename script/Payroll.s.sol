// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script, console2} from "forge-std/Script.sol";
import {Payroll} from "../src/Payroll.sol";

contract PayrollScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Payroll payroll = new Payroll(0xC520E73EE9Bb72Ef05EDB7d3aEb1AD0fEdE3bf5B, 0xD21341536c5cF5EB1bcb58f6723cE26e8D8E90e4);

        vm.stopBroadcast();
    }
}
