// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {InvariantTest} from "forge-std/InvariantTest.sol";
import "forge-std/console.sol";

import {Depositor} from "./actors/Depositor.sol";
import {WETH9} from "../src/WETH9.sol";

contract WETH9Invariants is Test, InvariantTest {
    WETH9 public weth;

    Depositor public depositor;

    function setUp() public {
        weth = new WETH9();
        depositor = new Depositor(weth);

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = Depositor.deposit.selector;
        selectors[1] = Depositor.withdraw.selector;
        selectors[2] = Depositor.sendETH.selector;
        selectors[3] = Depositor.forceSend.selector;

        targetSelector(FuzzSelector({addr: address(depositor), selectors: selectors}));
        excludeContract(address(weth));
    }

    // ETH can only be wrapped into WETH, WETH can only be
    // unwrapped back into ETH. The sum of Depositor's
    // ETH balance plus their WETH balance should always
    // equal the total ETH_SUPPLY.
    function invariant_preservationOfETH() public {
        assertEq(depositor.ETH_SUPPLY(), address(depositor).balance + weth.totalSupply());
    }

    // WETH balance should always be at least as much as
    // the sum of individual deposits.
    function invariant_WETHSolvency() public {
        assertEq(weth.totalSupply(), depositor.ghost_depositSum() + depositor.ghost_forceSendSum() - depositor.ghost_withdrawSum());
    }

    // No individual depositor balance can exceed the
    // wETH totalSupply()
    function invariant_depositorBalances() public {
        address[] memory depositors = depositor.depositors();
        for (uint256 i; i < depositors.length; ++i) {
            assertLe(weth.balanceOf(depositors[i]), weth.totalSupply());
        }
    }
}
