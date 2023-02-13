// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {AddressSet, LibAddressSet} from "../helpers/AddressSet.sol";
import {WETH9} from "../../src/WETH9.sol";

uint256 constant ETH_SUPPLY = 120_500_000 ether;

contract ForcePush {
    constructor(address dst) payable {
        selfdestruct(payable(dst));
    }
}

contract Handler is CommonBase, StdCheats, StdUtils {
    using LibAddressSet for AddressSet;

    WETH9 public weth;

    uint256 public ghost_depositSum;
    uint256 public ghost_withdrawSum;
    uint256 public ghost_forcePushSum;

    AddressSet internal _actors;

    modifier captureCaller() {
        _actors.add(msg.sender);
        _;
    }

    constructor(WETH9 _weth) {
        weth = _weth;
        deal(address(this), ETH_SUPPLY);
    }

    function deposit(uint256 amount) public captureCaller {
        amount = bound(amount, 0, address(this).balance);
        _pay(msg.sender, amount);

        vm.prank(msg.sender);
        weth.deposit{value: amount}();

        ghost_depositSum += amount;
    }

    function withdraw(uint256 callerSeed, uint256 amount) public {
        address caller = _actors.rand(callerSeed);
        amount = bound(amount, 0, weth.balanceOf(caller));

        vm.startPrank(caller);
        weth.withdraw(amount);
        _pay(address(this), amount);
        vm.stopPrank();

        ghost_withdrawSum += amount;
    }

    function approve(uint256 callerSeed, uint256 spenderSeed, uint256 amount) public {
        address caller = _actors.rand(callerSeed);
        address spender = _actors.rand(spenderSeed);

        vm.prank(caller);
        weth.approve(spender, amount);
    }

    function transfer(uint256 callerSeed, uint256 toSeed, uint256 amount) public {
        address caller = _actors.rand(callerSeed);
        address to = _actors.rand(toSeed);

        amount = bound(amount, 0, weth.balanceOf(caller));

        vm.prank(caller);
        weth.transfer(to, amount);
    }

    function transferFrom(uint256 callerSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) public {
        address caller = _actors.rand(callerSeed);
        address from = _actors.rand(fromSeed);
        address to = _actors.rand(toSeed);

        amount = bound(amount, 0, weth.balanceOf(from));
        amount = bound(amount, 0, weth.allowance(caller, from));
        _actors.add(to);

        vm.prank(caller);
        weth.transferFrom(from, to, amount);
    }

    function sendFallback(uint256 amount) public captureCaller {
        amount = bound(amount, 0, address(this).balance);
        _pay(msg.sender, amount);

        vm.prank(msg.sender);
        _pay(address(weth), amount);

        ghost_depositSum += amount;
    }

    function forcePush(uint256 amount) public {
        amount = bound(amount, 0, address(this).balance);
        new ForcePush{ value: amount }(address(weth));
        ghost_forcePushSum += amount;
    }

    function forEachActor(function(address) external func) public {
        return _actors.forEach(func);
    }

    function reduceActors(uint256 acc, function(uint256,address) external returns (uint256) func)
        public
        returns (uint256)
    {
        return _actors.reduce(acc, func);
    }

    function actors() external view returns (address[] memory) {
        return _actors.addrs;
    }

    function _pay(address to, uint256 amount) internal {
        (bool s,) = to.call{value: amount}("");
        require(s, "pay() failed");
    }

    receive() external payable {}
}
