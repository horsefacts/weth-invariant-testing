pragma solidity ^0.8.13;

import "forge-std/console.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {WETH9} from "../../src/WETH9.sol";
import {LibAddressSet, AddressSet} from "../helpers/AddressSet.sol";

contract Handler is CommonBase, StdCheats, StdUtils {
    using LibAddressSet for AddressSet;

    WETH9 public weth;

    AddressSet internal _actors;
    address internal currentActor;

    mapping(bytes32 => uint256) public calls;

    uint256 public constant ETH_SUPPLY = 120_500_000 ether;

    uint256 public ghost_depositSum;
    uint256 public ghost_withdrawSum;
    uint256 public ghost_zeroWithdrawals;

    modifier createActor() {
        currentActor = msg.sender;
        _actors.add(msg.sender);
        _;
    }

    modifier useActor(uint256 seed) {
        currentActor = _actors.rand(seed);
        _;
    }

    modifier countCall(bytes32 key) {
        calls[key]++;
        _;
    }

    constructor(WETH9 _weth) {
        weth = _weth;
        deal(address(this), ETH_SUPPLY);
    }

    function actors() external view returns (address[] memory) {
        return _actors.addrs;
    }

    function callSummary() external view {
        console.log("Call summary:");
        console.log("-------------------");
        console.log("deposit", calls["deposit"]);
        console.log("withdraw", calls["withdraw"]);
        console.log("sendFallback", calls["sendFallback"]);
        console.log("approve", calls["approve"]);
        console.log("transfer", calls["transfer"]);
        console.log("transferFrom", calls["transferFrom"]);
        console.log("-------------------");
        console.log("Zero withdrawals:", ghost_zeroWithdrawals);
    }

    function deposit(uint256 amount) public createActor countCall("deposit") {
        amount = bound(amount, 0, address(this).balance);
        _pay(currentActor, amount);

        ghost_depositSum += amount;

        vm.prank(currentActor);
        weth.deposit{ value: amount }();
    }

    function withdraw(uint256 amount, uint256 seed) public useActor(seed) countCall("withdraw") {
        amount = bound(amount, 0, weth.balanceOf(currentActor));

        if (amount == 0) ghost_zeroWithdrawals++;
        ghost_withdrawSum += amount;

        vm.startPrank(currentActor);
        weth.withdraw(amount);
        _pay(address(this), amount);
        vm.stopPrank();
    }

    function sendFallback(uint256 amount) public createActor countCall("sendFallback") {
        amount = bound(amount, 0, address(this).balance);
        _pay(currentActor, amount);

        ghost_depositSum += amount;

        vm.prank(currentActor);
        (bool success,) = address(weth).call{ value: amount }("");
        require(success, "sendFallback failed");
    }

    function approve(
        uint256 seed,
        uint256 spenderSeed,
        uint256 amount
    ) public useActor(seed) countCall("approve") {
        address spender = _actors.rand(spenderSeed);

        vm.prank(currentActor);
        weth.approve(spender, amount);
    }

    function transfer(
        uint256 seed,
        uint256 toSeed,
        uint256 amount
    ) public useActor(seed) countCall("transfer") {
        address to = _actors.rand(toSeed);

        amount = bound(amount, 0, weth.balanceOf(currentActor));

        vm.prank(currentActor);
        weth.transfer(to, amount);
    }

    function transferFrom(
        uint256 seed,
        uint256 fromSeed,
        uint256 toSeed,
        bool _approve,
        uint256 amount
    ) public useActor(seed) countCall("transferFrom")
    {
        address from = _actors.rand(fromSeed);
        address to = _actors.rand(toSeed);

        amount = bound(amount, 0, weth.balanceOf(from));

        if (_approve) {
            vm.prank(from);
            weth.approve(currentActor, amount);
        } else {
            amount = bound(amount, 0, weth.allowance(currentActor, from));
        }

        vm.prank(currentActor);
        weth.transferFrom(from, to, amount);
    }

    function _pay(address to, uint256 amount) internal {
        (bool success,) = payable(to).call{ value: amount }("");
        require(success, "pay failed");
    }

    receive() external payable {}
}
