// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {WETH9} from "../src/WETH9.sol";

import {Handler, ETH_SUPPLY} from "./handlers/Handler.sol";

contract WETH9Invariants is Test {
    WETH9 public weth;
    Handler public handler;

    function setUp() public {
        weth = new WETH9();
        handler = new Handler(weth);

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = Handler.deposit.selector;
        selectors[1] = Handler.withdraw.selector;
        selectors[2] = Handler.sendFallback.selector;
        selectors[3] = Handler.approve.selector;
        selectors[4] = Handler.transfer.selector;
        selectors[5] = Handler.transferFrom.selector;
        selectors[6] = Handler.forcePush.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));

        excludeContract(address(weth));
    }

    // ETH can only be wrapped into WETH, WETH can only
    // be unwrapped back into ETH. The sum of the Handler's
    // ETH balance plus the WETH totalSupply() should always
    // equal the total ETH_SUPPLY.
    function invariant_conservationOfETH() public {
        assertEq(ETH_SUPPLY, address(handler).balance + weth.totalSupply());
    }

    // The WETH contract's Ether balance should always be
    // at least as much as the sum of individual deposits
    function invariant_solvencyDeposits() public {
        assertEq(
            address(weth).balance,
            handler.ghost_depositSum() + handler.ghost_forcePushSum() - handler.ghost_withdrawSum()
        );
    }

    // The WETH contract's Ether balance should always be
    // at least as much as the sum of individual balances
    function invariant_solvencyBalances() public {
        uint256 sumOfBalances = handler.reduceActors(0, this.accumulateBalance);
        assertEq(address(weth).balance - handler.ghost_forcePushSum(), sumOfBalances);
    }

    function accumulateBalance(uint256 balance, address caller) external view returns (uint256) {
        return balance + weth.balanceOf(caller);
    }

    // No individual account balance can exceed the
    // WETH totalSupply().
    function invariant_depositorBalances() public {
        handler.forEachActor(this.assertAccountBalanceLteTotalSupply);
    }

    function assertAccountBalanceLteTotalSupply(address account) external {
        assertLe(weth.balanceOf(account), weth.totalSupply());
    }

    function test_concrete_wat() public {
        vm.prank(address(0x76006C4471fb6aDd17728e9c9c8B67d5AF06cDA0));
        handler.transfer(address(0xe7E5d90B7F2995E37f675FbfFe3ecBad84ae3F96), 1214023766310705805701176537853568069216);

        vm.prank(address(0x0000000000000000000000000000000000000750));
        handler.forcePush(120206896941022903464812169);

        vm.prank(address(0x60c67673Ac7f198805e70CD86BA42e822f0131b0));
        handler.sendFallback(115792089237316195423570985008687907853269984665640564039457584007913129639933);

        vm.prank(address(0xDBaD009C67eD04C03AEc0Dc77178A6A6629A6bbD));
        handler.sendFallback(208312292878968729819296);

        vm.prank(address(0x1142aBdFeCFb75618fcFc1F8868966C1dB895a6e));
        handler.transferFrom(
            address(0x00000000000000000053Ed0A792881a65224e6a5),
            address(0xcEaEfAEB86d7e8A75BeD1d28Da9d22C4eF33516A),
            19039762917734506487814490
        );

        vm.prank(address(0x60c67673Ac7f198805e70CD86BA42e822f0131b0));
        handler.withdraw(20699250629484519464169139825047693);

        assertEq(ETH_SUPPLY, address(handler).balance + weth.totalSupply());
    }
}
