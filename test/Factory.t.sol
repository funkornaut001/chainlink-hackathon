// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {TokenTransferor} from "../src/TokenTransferor.sol";
import {Payroll} from "../src/Payroll.sol";
import {Test, console2} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ERC20Mock} from "@openzeppelin/mocks/ERC20Mock.sol";

contract FactoryTest is Test {
    // Set the deployment fee
    uint256 public deployment_fee = 1 wei; // Example fee
    address router = makeAddr("router"); 

    Payroll public payroll;
    ERC20Mock public mockBnMToken;
    TokenTransferor public ccip;

    function setUp() public {
        mockBnMToken = new ERC20Mock("BnM", "BnM", address(this), 18);
        ccip = new TokenTransferor(router, address(mockBnMToken));
        payroll = new Payroll(address(ccip), address(mockBnMToken));
    }

    function test_deployPayrollAndTokenTransferor() public {
        address company = makeAddr("company");
        vm.startPrank(company);
        
        //deployPayrollAndTokenTransferor();
        //assertEq(payroll.owner(), address(this));
        //assertEq(ccip.owner(), address(this));
    }

}