pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

import {WETH9} from "../src/WETH9.sol";
import {Handler} from "./handlers/Handler.sol";

contract WETH9Invariants is Test {
    WETH9 public weth;
    Handler public handler;

    function setUp() public {
        weth = new WETH9();
        handler = new Handler(weth);

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = Handler.deposit.selector;
        selectors[1] = Handler.withdraw.selector;
        selectors[2] = Handler.sendFallback.selector;

        targetSelector(FuzzSelector({
            addr: address(handler),
            selectors: selectors
        }));

        targetContract(address(handler));
    }

    // PROPERTY: Conservation of Ether
    // ETH can only be wrapped into WETH, WETH can only
    // be unwrapped back into ETH. The sum of the Handler's
    // ETH balance plus the WETH totalSupply() should always
    // equal the total ETH_SUPPLY.
    function invariant_conservationOfETH() public {
        assertEq(
          handler.ETH_SUPPLY(),
          address(handler).balance + weth.totalSupply()
        );
    }

    // PROPERTY: Solvency of Deposits
    // The WETH contract's Ether balance should always
    // equal the sum of all the individual deposits
    // minus all the individual withdrawals.
    function invariant_solvencyDeposits() public {
        assertEq(
          address(weth).balance,
          handler.ghost_depositSum() - handler.ghost_withdrawSum()
        );
    }

    // PROPERTY: Solvency of Balances
    // The WETH contract's Ether balance should always be
    // at least as much as the sum of individual balances
    function invariant_solvencyBalances() public {
        uint256 sumOfBalances;
        address[] memory actors = handler.actors();
        for (uint256 i; i < actors.length; ++i) {
            sumOfBalances += weth.balanceOf(actors[i]);
        }
        assertEq(
            address(weth).balance,
            sumOfBalances
        );
    }

    // PROPERTY: Individual Balance Invariant
    // No individual account balance can exceed the
    // WETH totalSupply()
    function invariant_depositorBalances() public {
        address[] memory actors = handler.actors();
        for (uint256 i; i < actors.length; ++i) {
            assertLe(weth.balanceOf(actors[i]), weth.totalSupply());
        }
    }

    function invariant_callSummary() public view {
        handler.callSummary();
    }
}
