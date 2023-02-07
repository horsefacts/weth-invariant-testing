// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {InvariantTest} from "forge-std/InvariantTest.sol";
import "forge-std/console.sol";

import {Handler} from "./handlers/Handler.sol";
import {WETH9} from "../src/WETH9.sol";

contract WETH9Invariants is Test, InvariantTest {
    WETH9 public weth;

    Handler public handler;

    function setUp() public {
        weth = new WETH9();
        handler = new Handler(weth);

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = Handler.deposit.selector;
        selectors[1] = Handler.withdraw.selector;
        selectors[2] = Handler.sendETH.selector;
        selectors[3] = Handler.forceSend.selector;
        selectors[4] = Handler.transfer.selector;
        selectors[5] = Handler.transferFrom.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        excludeContract(address(weth));
        excludeSender(address(weth));
        excludeSender(address(this));
    }

    // ETH can only be wrapped into WETH, WETH can only be
    // unwrapped back into ETH. The sum of Handler's
    // ETH balance plus the WETH totalSupply() should always
    // equal the total ETH_SUPPLY.
    function invariant_conservationOfETH() public {
        assertEq(handler.ETH_SUPPLY(), address(handler).balance + weth.totalSupply());
    }

    // WETH balance should always be at least as much as
    // the sum of individual deposits.
    function invariant_WETHSolvency_deposits() public {
        assertEq(
            weth.totalSupply(), handler.ghost_depositSum() + handler.ghost_forceSendSum() - handler.ghost_withdrawSum()
        );
    }

    // WETH balance should always be at least as much as
    // the sum of individual balances.
    function invariant_WETHSolvency_balances() public {
        uint256 sumOfBalances = handler.reduceActors(0, this.accumulateBalance);
        assertEq(weth.totalSupply(), sumOfBalances + handler.ghost_forceSendSum());
    }

    function accumulateBalance(uint256 balance, address caller) external view returns (uint256) {
        return balance + weth.balanceOf(caller);
    }

    // No individual depositor's balance can exceed the
    // WETH totalSupply().
    function invariant_depositorBalances() public {
        handler.mapActors(this.assertCallerBalanceLteTotalSupply);
    }

    function assertCallerBalanceLteTotalSupply(address caller) external {
        assertLe(weth.balanceOf(caller), weth.totalSupply());
    }
}
