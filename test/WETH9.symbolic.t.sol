// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {SymTest} from "halmos-cheatcodes/SymTest.sol";
import {Test} from "forge-std/Test.sol";

import {WETH9} from "../src/WETH9.sol";

contract WETHSymTest is SymTest, Test {
    WETH9 weth;

    function setUp() public {
        weth = new WETH9();
    }

    function check_globalInvariants(bytes4 selector, address caller) public {
        // Execute an arbitrary tx
        vm.prank(caller);
        (bool success,) = address(weth).call(gen_calldata(selector));
        vm.assume(success); // ignore reverting cases

        // Record post-state
        assert(weth.totalSupply() == address(weth).balance);
    }

    // @dev deposit() increases the caller's balance by exactly msg.value;
    function check_deposit_depositorBalanceUpdate(address guy, uint256 wad) public {
        uint256 balanceBefore = weth.balanceOf(guy);

        vm.deal(guy, wad);
        vm.prank(guy);
        weth.deposit{value: wad}();

        uint256 balanceAfter = weth.balanceOf(guy);

        assert(balanceAfter == balanceBefore + wad);
    }

    // @dev deposit() does not change the balance of any address besides the caller.
    function check_deposit_balancePreservation(address guy, address gal, uint256 wad) public {
        vm.assume(guy != gal);
        uint256 balanceBefore = weth.balanceOf(gal);

        vm.deal(guy, wad);

        vm.prank(guy);
        weth.deposit{value: wad}();

        uint256 balanceAfter = weth.balanceOf(gal);

        assert(balanceAfter == balanceBefore);
    }

    // @dev withdraw() decreases the caller's balance by exactly msg.value;
    function check_withdraw_withdrawerBalanceUpdate(address guy, uint256 wad) public {
        vm.deal(guy, wad);
        vm.prank(guy);
        weth.deposit{value: wad}();

        uint256 balanceBefore = weth.balanceOf(guy);

        vm.prank(guy);
        weth.withdraw(wad);

        uint256 balanceAfter = weth.balanceOf(guy);

        assert(balanceAfter == balanceBefore - wad);
    }

    // @dev withdraw() does not change the balance of any address besides the caller.
    function check_withdraw_balancePreservation(address guy, address gal, uint256 wad) public {
        vm.assume(guy != gal);
        vm.deal(guy, wad);
        vm.prank(guy);
        weth.deposit{value: wad}();

        uint256 balanceBefore = weth.balanceOf(gal);

        vm.prank(guy);
        weth.withdraw(wad);

        uint256 balanceAfter = weth.balanceOf(gal);

        assert(balanceAfter == balanceBefore);
    }

    // @dev approve(dst, wad) sets dst allowance to wad.
    function check_approve_allowanceUpdate(address guy, address dst, uint256 wad) public {
        vm.prank(guy);
        weth.approve(dst, wad);

        uint256 allowanceAfter = weth.allowance(guy, dst);

        assert(allowanceAfter == wad);
    }

    // @dev approve(dst, wad) does not change the allowance of any other address/spender.
    function check_approve_allowancePreservation(address guy, address dst1, uint256 wad, address gal, address dst2)
        public
    {
        vm.assume(guy != gal);
        uint256 allowanceBefore = weth.allowance(gal, dst2);

        vm.prank(guy);
        weth.approve(dst1, wad);

        uint256 allowanceAfter = weth.allowance(gal, dst2);

        assert(allowanceAfter == allowanceBefore);
    }

    // @dev transfer(dst, wad):
    //      - decreases guy's balance by exactly wad.
    //      - increases dst's balance by exactly wad.
    function check_transfer_balanceUpdate(address guy, address dst, uint256 wad) public {
        vm.assume(guy != dst);
        vm.deal(guy, wad);
        vm.prank(guy);
        weth.deposit{value: wad}();

        uint256 guyBalanceBefore = weth.balanceOf(guy);
        uint256 dstBalanceBefore = weth.balanceOf(dst);

        vm.prank(guy);
        weth.transfer(dst, wad);

        uint256 guyBalanceAfter = weth.balanceOf(guy);
        uint256 dstBalanceAfter = weth.balanceOf(dst);

        assert(guyBalanceAfter == guyBalanceBefore - wad);
        assert(dstBalanceAfter == dstBalanceBefore + wad);
    }

    // @dev transfer(dst, wad):
    //      - does not change balance of any other address
    function check_transfer_balancePreservation(address guy, address dst, uint256 wad, address gal) public {
        vm.assume(guy != dst);
        vm.assume(guy != gal);
        vm.assume(dst != gal);
        vm.deal(guy, wad);
        vm.prank(guy);
        weth.deposit{value: wad}();

        uint256 galBalanceBefore = weth.balanceOf(gal);

        vm.prank(guy);
        weth.transfer(dst, wad);

        uint256 galBalanceAfter = weth.balanceOf(gal);

        assert(galBalanceAfter == galBalanceBefore);
    }

    // @dev transferFrom(src, dst, wad):
    //      - decreases src's balance by exactly wad.
    //      - increases dst's balance by exactly wad.
    function check_transferFrom_balanceUpdate(address guy, address src, address dst, uint256 wad) public {
        vm.assume(src != dst);
        vm.deal(src, wad);
        vm.prank(src);
        weth.deposit{value: wad}();

        uint256 srcBalanceBefore = weth.balanceOf(src);
        uint256 dstBalanceBefore = weth.balanceOf(dst);

        vm.prank(guy);
        weth.transferFrom(src, dst, wad);

        uint256 srcBalanceAfter = weth.balanceOf(src);
        uint256 dstBalanceAfter = weth.balanceOf(dst);

        assert(srcBalanceAfter == srcBalanceBefore - wad);
        assert(dstBalanceAfter == dstBalanceBefore + wad);
    }

    // @dev transfer(dst, wad):
    //      - does not change balance of any other address
    function check_transferFrom_balancePreservation(address guy, address src, address dst, uint256 wad, address gal)
        public
    {
        vm.assume(guy != dst);
        vm.assume(guy != gal);
        vm.assume(dst != gal);
        vm.assume(src != gal);

        vm.deal(guy, wad);
        vm.prank(guy);
        weth.deposit{value: wad}();

        uint256 galBalanceBefore = weth.balanceOf(gal);

        vm.prank(guy);
        weth.transferFrom(src, dst, wad);

        uint256 galBalanceAfter = weth.balanceOf(gal);

        assert(galBalanceAfter == galBalanceBefore);
    }

    // @dev transferFrom(src, dst, wad):
    //      - decreases msg.sender's allowance by exactly wad.
    function check_transferFrom_allowanceUpdate(address guy, address src, address dst, uint256 wad) public {
        vm.assume(guy != src);
        vm.assume(src != dst);
        vm.deal(src, wad);
        vm.prank(src);
        weth.deposit{value: wad}();

        uint256 guyAllowanceBefore = weth.allowance(src, guy);
        vm.assume(guyAllowanceBefore != type(uint256).max);

        vm.prank(guy);
        weth.transferFrom(src, dst, wad);

        uint256 guyAllowanceAfter = weth.allowance(src, guy);

        assert(guyAllowanceAfter == guyAllowanceBefore - wad);
    }

    // @dev transferFrom(src, dst, wad):
    //      - does not change allowance if caller is src.
    function check_transferFrom_allowanceUpdate_callerIsSrc(address guy, address src, address dst, uint256 wad)
        public
    {
        vm.assume(guy != src);
        vm.assume(src != dst);
        vm.deal(guy, wad);
        vm.prank(guy);
        weth.deposit{value: wad}();

        uint256 guyAllowanceBefore = weth.allowance(guy, guy);
        vm.assume(guyAllowanceBefore != type(uint256).max);

        vm.prank(guy);
        weth.transferFrom(guy, dst, wad);

        uint256 guyAllowanceAfter = weth.allowance(guy, guy);

        assert(guyAllowanceAfter == guyAllowanceBefore);
    }

    // @dev transferFrom(src, dst, wad):
    //      - does not change msg.sender's allowance if set to type(uint256).max
    function check_transferFrom_allowanceUpdate_maxAllowance(address guy, address src, address dst, uint256 wad)
        public
    {
        vm.assume(src != dst);
        vm.deal(src, wad);
        vm.startPrank(src);
        weth.deposit{value: wad}();
        weth.approve(guy, type(uint256).max);
        vm.stopPrank();

        uint256 guyAllowanceBefore = weth.allowance(src, guy);

        vm.prank(guy);
        weth.transferFrom(src, dst, wad);

        uint256 guyAllowanceAfter = weth.allowance(src, guy);

        assert(guyAllowanceAfter == guyAllowanceBefore);
        assert(guyAllowanceAfter == type(uint256).max);
    }

    function gen_calldata(bytes4 selector) internal returns (bytes memory) {
        // Ignore view functions
        // Skip for now

        // Create symbolic values to be included in calldata
        address guy = svm.createAddress("guy");
        address src = svm.createAddress("src");
        address dst = svm.createAddress("dst");
        uint256 wad = svm.createUint256("wad");

        // Generate calldata based on the function selector
        bytes memory args;
        if (selector == weth.withdraw.selector) {
            args = abi.encode(wad);
        } else if (selector == weth.approve.selector) {
            args = abi.encode(guy, wad);
        } else if (selector == weth.transfer.selector) {
            args = abi.encode(dst, wad);
        } else if (selector == weth.transferFrom.selector) {
            args = abi.encode(src, dst, wad);
        } else {
            // For functions where all parameters are static (not dynamic arrays or bytes),
            // a raw byte array is sufficient instead of explicitly specifying each argument.
            args = svm.createBytes(1024, "data"); // choose a size that is large enough to cover all parameters
        }
        return abi.encodePacked(selector, args);
    }
}
