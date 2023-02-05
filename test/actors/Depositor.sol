// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {WETH9} from "../../src/WETH9.sol";

contract ForceSend {
    function forceSend(address payable dst) external payable {
        selfdestruct(dst);
    }
}

contract Depositor is Test {
    WETH9 public weth;

    uint256 public ETH_SUPPLY = 120_000_000 ether;

    uint256 public ghost_depositSum;
    uint256 public ghost_withdrawSum;
    uint256 public ghost_forceSendSum;

    address[] internal _depositors;

    constructor(WETH9 _weth) {
        weth = _weth;
        deal(address(this), ETH_SUPPLY);
    }
    
    function deposit(uint256 amount) public {
        try weth.deposit{value: amount}() {
            ghost_depositSum += amount;
            _depositors.push(msg.sender);
        } catch {}
    }

    function sendETH(uint256 amount) public {
        (bool success,) = payable(address(weth)).call{value: amount}("");
        if (success) {
            ghost_depositSum += amount;
            _depositors.push(msg.sender);
        }
    }

    function withdraw(uint256 amount) public {
        try weth.withdraw(amount) {
            ghost_withdrawSum += amount;
        } catch {}
    }

    function forceSend(uint256 amount) public {
        ForceSend sender = new ForceSend();
        try sender.forceSend{value: amount}(payable(address(weth))) {
            ghost_forceSendSum += amount;
        } catch {}
    }

    function depositors() public view returns (address[] memory) {
        return _depositors;
    }

    receive() external payable {}
}
