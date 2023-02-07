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
    }

    function invariant_badInvariantThisShouldFail() public {
        assertEq(1, weth.totalSupply());
    }
}
