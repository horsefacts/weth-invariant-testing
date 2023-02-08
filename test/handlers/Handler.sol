// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {WETH9} from "../../src/WETH9.sol";

uint256 constant ETH_SUPPLY = 120_500_000;

struct AddressSet {
    address[] addrs;
    mapping(address => bool) saved;
}

library LibAddressSet {
    function add(AddressSet storage s, address addr) internal {
        if (!s.saved[addr]) {
            s.addrs.push(addr);
            s.saved[addr] = true;
        }
    }

    function contains(AddressSet storage s, address addr) internal view returns (bool) {
        return s.saved[addr];
    }

    function count(AddressSet storage s) internal view returns (uint256) {
        return s.addrs.length;
    }

    function forEach(AddressSet storage s, function(address) external func) internal {
        for (uint256 i; i < s.addrs.length; ++i) {
            func(s.addrs[i]);
        }
    }

    function reduce(AddressSet storage s, uint256 acc, function(uint256,address) external returns (uint256) func)
        internal
        returns (uint256)
    {
        for (uint256 i; i < s.addrs.length; ++i) {
            acc = func(acc, s.addrs[i]);
        }
        return acc;
    }
}

contract Handler is Test {
    using LibAddressSet for AddressSet;

    WETH9 public weth;

    uint256 public ghost_depositSum;
    uint256 public ghost_withdrawSum;

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

    function withdraw(uint256 amount) public captureCaller {
        amount = bound(amount, 0, weth.balanceOf(address(this)));

        vm.prank(msg.sender);
        weth.withdraw(amount);

        ghost_withdrawSum += amount;
    }

    function approve(address spender, uint256 amount) public {
        vm.prank(msg.sender);
        weth.approve(spender, amount);
    }

    function transfer(address to, uint256 amount) public {
        amount = bound(amount, 0, weth.balanceOf(msg.sender));
        _actors.add(to);

        vm.prank(msg.sender);
        weth.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public {
        amount = bound(amount, 0, weth.balanceOf(from));
        _actors.add(to);

        vm.prank(msg.sender);
        weth.transferFrom(from, to, amount);
    }

    function sendFallback(uint256 amount) public captureCaller {
        amount = bound(amount, 0, address(this).balance);
        _pay(msg.sender, amount);

        vm.prank(msg.sender);
        (bool success,) = address(weth).call{value: amount}("");

        require(success, "sendFallback failed");
        ghost_depositSum += amount;
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
