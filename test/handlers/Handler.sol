pragma solidity ^0.8.13;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {WETH9} from "../../src/WETH9.sol";

contract Handler is CommonBase, StdCheats, StdUtils {
    WETH9 public weth;

    constructor(WETH9 _weth) {
        weth = _weth;
        deal(address(this), 10 ether);
    }

    function deposit(uint256 amount) public {
        weth.deposit{ value: amount }();
    }
}
