// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {WETH9} from "../../src/WETH9.sol";

contract Handler is Test {
    WETH9 public weth;

    constructor(WETH9 _weth) {
        weth = _weth;
    }
}
