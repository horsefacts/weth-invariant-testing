// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {WETH9} from "../../src/WETH9.sol";

struct AddressSet {
    address[] addrs;
    mapping(address => bool) saved;
}

library AddressSetLib {
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

    function rand(AddressSet storage s, uint256 seed) internal view returns (address) {
        return s.addrs[_bound(seed, 0, s.addrs.length - 1)];
    }

    function map(AddressSet storage s, function(address) external func) internal {
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

    // Yoinked directly from StdUtils _bound
    function _bound(uint256 x, uint256 min, uint256 max) internal pure returns (uint256 result) {
        require(min <= max, "Max is less than min.");
        if (x >= min && x <= max) return x;

        uint256 size = max - min + 1;

        if (x <= 3 && size > x) return min + x;
        if (x >= type(uint256).max - 3 && size > type(uint256).max - x) return max - (type(uint256).max - x);

        if (x > max) {
            uint256 diff = x - max;
            uint256 rem = diff % size;
            if (rem == 0) return max;
            result = min + rem - 1;
        } else if (x < min) {
            uint256 diff = min - x;
            uint256 rem = diff % size;
            if (rem == 0) return min;
            result = max - rem + 1;
        }
    }
}

contract ForceSend {
    constructor(address dst) payable {
        selfdestruct(payable(dst));
    }
}

contract Handler is Test {
    using AddressSetLib for AddressSet;

    event HandlerBalance(uint256 bal);
    event WethSupply(uint256 ts);

    WETH9 public weth;

    uint256 public ETH_SUPPLY = 120_000_000 ether;

    uint256 public ghost_depositSum;
    uint256 public ghost_withdrawSum;
    uint256 public ghost_forceSendSum;

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
        pay(msg.sender, amount);

        vm.prank(msg.sender);
        weth.deposit{value: amount}();

        ghost_depositSum += amount;
    }

    function sendETH(uint256 amount) public captureCaller {
        amount = bound(amount, 0, address(this).balance);
        pay(msg.sender, amount);

        vm.prank(msg.sender);
        (bool success,) = address(weth).call{value: amount}("");

        if (success) {
            ghost_depositSum += amount;
        } else {
            vm.prank(msg.sender);
            payable(address(this)).transfer(amount);
        }
    }

    function withdraw(uint256 amount) public captureCaller {
        vm.prank(msg.sender);
        weth.withdraw(amount);

        vm.prank(msg.sender);
        payable(address(this)).transfer(amount);

        ghost_withdrawSum += amount;
    }

    function forceSend(uint256 amount) public {
        amount = bound(amount, 0, address(this).balance);
        new ForceSend{ value: amount }(address(weth));
        ghost_forceSendSum += amount;
    }

    function transfer(uint256 dstSeed, uint256 wad) public {
        address dst = _actors.rand(dstSeed);

        vm.prank(msg.sender);
        weth.transfer(dst, wad);
    }

    function transferFrom(uint256 srcSeed, uint256 dstSeed, uint256 wad) public {
        address src = _actors.rand(srcSeed);
        address dst = _actors.rand(dstSeed);

        vm.prank(msg.sender);
        weth.transferFrom(src, dst, wad);
    }

    function mapActors(function(address) external func) public {
        return _actors.map(func);
    }

    function reduceActors(uint256 acc, function(uint256,address) external returns (uint256) func)
        public
        returns (uint256)
    {
        return _actors.reduce(acc, func);
    }

    function actors() public view returns (address[] memory) {
        return _actors.addrs;
    }

    function pay(address to, uint256 amount) public {
        try this._pay(to, amount) {} catch {}
    }

    function _pay(address to, uint256 amount) public {
        (bool s,) = to.call{value: amount}("");
        require(s, "pay() failed");
    }

    receive() external payable {}
}
