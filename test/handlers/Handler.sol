pragma solidity ^0.8.13;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {WETH9} from "../../src/WETH9.sol";

contract Handler is CommonBase, StdCheats, StdUtils {
    WETH9 public weth;

    uint256 public constant ETH_SUPPLY = 120_500_000 ether;

    uint256 public ghost_depositSum;
    uint256 public ghost_withdrawSum;

    constructor(WETH9 _weth) {
        weth = _weth;
        deal(address(this), ETH_SUPPLY);
    }

    function deposit(uint256 amount) public {
        amount = bound(amount, 0, address(this).balance);
        _pay(msg.sender, amount);

        ghost_depositSum += amount;

        vm.prank(msg.sender);
        weth.deposit{ value: amount }();
    }

    function withdraw(uint256 amount) public {
        amount = bound(amount, 0, weth.balanceOf(msg.sender));

        ghost_withdrawSum += amount;

        vm.startPrank(msg.sender);
        weth.withdraw(amount);
        _pay(address(this), amount);
        vm.stopPrank();
    }

    function sendFallback(uint256 amount) public {
        amount = bound(amount, 0, address(this).balance);
        _pay(msg.sender, amount);

        ghost_depositSum += amount;

        vm.prank(msg.sender);
        (bool success,) = address(weth).call{ value: amount }("");
        require(success, "sendFallback failed");
    }

    function _pay(address to, uint256 amount) internal {
        (bool success,) = to.call{ value: amount }("");
        require(success, "pay failed");
    }

    receive() external payable {}
}
