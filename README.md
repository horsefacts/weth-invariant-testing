# WETH invariant testing 

The Wrapped Ether token allows users to `deposit` and "wrap" native Ether, which is represented as `WETH`, an ERC20 token.  Users who own `WETH` can `withdraw` native Ether by exchanging `WETH` for Ether at a 1:1 exchange rate. 

Wrapped Ether is a simple but critical primitive in the Ethereum application layer. It enables applications designed for composability with ERC20 tokens to use a representation of native Ether and mitigates the security risks to end users and smart contract systems associated with native Ether transfers.

The canonical wrapped Ether contract, known as `WETH9`, is only a litle over 50 lines of code:

```solidity
contract WETH9 {
    string public name = "Wrapped Ether";
    string public symbol = "WETH";
    uint8 public decimals = 18;

    event Approval(address indexed src, address indexed guy, uint256 wad);
    event Transfer(address indexed src, address indexed dst, uint256 wad);
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    fallback() external payable {
        deposit();
    }

    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 wad) public {
        require(balanceOf[msg.sender] >= wad);
        balanceOf[msg.sender] -= wad;
        payable(msg.sender).transfer(wad);
        emit Withdrawal(msg.sender, wad);
    }

    function totalSupply() public view returns (uint256) {
        return address(this).balance;
    }

    function approve(address guy, uint256 wad) public returns (bool) {
        allowance[msg.sender][guy] = wad;
        emit Approval(msg.sender, guy, wad);
        return true;
    }

    function transfer(address dst, uint256 wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint256 wad) public returns (bool) {
        require(balanceOf[src] >= wad);

        if (src != msg.sender && allowance[src][msg.sender] != type(uint256).max) {
            require(allowance[src][msg.sender] >= wad);
            allowance[src][msg.sender] -= wad;
        }

        balanceOf[src] -= wad;
        balanceOf[dst] += wad;

        emit Transfer(src, dst, wad);

        return true;
    }
}
```

Let's add the `WETH9` contract as `src/WETH9.sol`:

```bash
$ tree src                                                                       ~/Projects/weth-invariant-testing
src
└── WETH9.sol
```

An invariant test contract looks just like the test contracts you know and love from unit and fuzz testing with Foundry.  In fact, all the helpers we'll need to define and test invariants are now included in the base `forge-std/Test.sol` contract.

Let's add a test contract in `test/WETH9.invariants.t.sol`:

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {WETH9} from "../src/WETH9.sol";

contract WETH9Invariants is Test {
    WETH9 public weth;

    function setUp() public {
        weth = new WETH9();
    }

    function invariant_badInvariantThisShouldFail() public {
        assertEq(1, weth.totalSupply());
    }
}
```

(I like to include `invariants` in the name of my invariant test files to distinguish them from others, but that's just a convention, not required by the test runner).

Hopefully this looks familiar if you've used Foundry: we declare our contract under test as a state variable, create an instance in `setUp`, and write test functions using helpers like `assertEq` that make assertions about the state of the system.

Unlike unit and fuzz tests, invariants must start with the `invariant_` prefix, but otherwise this looks a lot like an everyday Forge unit test.

In case the name wasn't clear, our example invariant should fail:

```solidity
    function invariant_badInvariantThisShouldFail() public {
        assertEq(1, weth.totalSupply());
    }
```

Let's give it a try and see what happens:

```bash
$ forge test -vvv
[⠢] Compiling...
No files changed, compilation skipped

Running 1 test for test/WETH9.invariants.t.sol:WETH9Invariants
[FAIL. Reason: Assertion failed.] invariant_badInvariantThisShouldFail()
(runs: 1, calls: 0, reverts: 0)
Test result: FAILED. 0 passed; 1 failed; finished in 2.11ms

Failing tests:
Encountered 1 failing test in test/WETH9.invariants.t.sol:WETH9Invariants
[FAIL. Reason: Assertion failed.] invariant_badInvariantThisShouldFail()
(runs: 1, calls: 0, reverts: 0)

Encountered a total of 1 failing tests, 0 tests succeeded
```

The test fails right away. In fact, it's failing the _very first time_ we check the invariants, immediately after `setUp`, and before the fuzzer even makes any calls to the contract under test. Since the `totalSupply()` starts at zero, the assertion fails.

Let's make a change and try again. We'll change the name, too, since it should actually pass now:

```solidity
    function invariant_wethSupplyIsAlwaysZero() public {
        assertEq(0, weth.totalSupply());
    }
```

It's not a particularly useful or realistic assertion, but hey, it works!

```bash
$ forge test                                                                        Running 1 test for test/WETH9.invariants.t.sol:WETH9Invariants
[PASS] invariant_wethSupplyIsAlwaysZero()
(runs: 1000, calls: 15000, reverts: 8671)
Test result: ok. 1 passed; 0 failed; finished in 873.42ms
```

This time,  we can see that the fuzzer has made some actual calls to the contract under test: `1000` runs, `15000` calls, and `8671` reverts. This is very useful diagnostic information as you write and refine invariant tests:

- Runs: the total number of random call sequences generated by the fuzzer
- Calls: the total number of _calls_ the fuzzer made to our contract under test during this test run. This is equal to the number of `runs` times the `depth` defined in `foundry.toml`.
- Reverts: the number of calls that reverted in this test run. In this case, around 58% of the randomly generated calls to our contract reverted.

Of course, in the real world the WETH supply is not always zero. So why does our test pass? A unit test can help clarify. It's possible to define unit and invariant tests in the same test class. Add this right after our invariant test function:

```solidity
    function test_zeroDeposit() public {
        weth.deposit{ value: 0 }();
        assertEq(0, weth.balanceOf(address(this)));
        assertEq(0, weth.totalSupply());
    }
```

```bash
$ forge test -m test_zeroDeposit 

Running 1 test for test/WETH9.invariants.t.sol:WETH9Invariants
[PASS] test_zeroDeposit() (gas: 11071)
Test result: ok. 1 passed; 0 failed; finished in 2.07ms
```

The WETH contract allows callers to "deposit" zero ETH in exchange for zero WETH!

So here's what's happening under the hood:
- The fuzzer is examining all the public functions on the `WETH9` contract and calling them with random arguments.
- Many of these calls will revert. For example, `withdraw`, `transfer`, and `transferFrom` should all revert in most cases since there are no balances or tokens to transfer.
- Some of these calls will succeed, but do nothing, like calling `deposit` with zero `msg.value`.
- The fuzzer generates random call sequences and calldata, but does not fuzz `msg.value`, so all calls have zero value. Since WETH is only created when a caller deposits native ETH, no ETH enters the WETH contract and no WETH tokens are ever created.

This kind of "open testing"—allowing the fuzzer to wreak havoc on all contracts, all methods, and all arguments—can be useful in some scenarios, and it's usually a good place to start when building up an invariant test suite. But you'll often want to simulate specific conditions (like a caller sending along native ETH to make a WETH `deposit`) more precisely. 

There is also a probabilistic trade-off between exploring more random call sequences and finding "meaningful" sequences that actually test our invariants. Exposing more contracts and functions to the fuzzer generates much more "surface area" to fuzz that _could_ expose interesting ways to break the invariants. But if 99% of those sequences revert because their arguments or ordering are unrealistic, we might not really be testing our invariants in a useful way at all.

In order to simulate native Ether transfers and test the conditions we really care about, we need to introduce another contract: a _handler_.

A handler is a wrapper contract that we'll use to manage interactions with our contract under test. Rather than expose the `WETH9` functions directly to the fuzzer, we'll instead point the fuzzer at our _handler_ contract and add functions that delegate to `WETH9`. This lets us use standard Forge testing tools like `vm.prank` and `deal` to set up tests with the conditions we care about. 

A handler is just another helper contract. Let's add the following in `test/handlers/Handler.sol`:

```solidity
import {WETH9} from "../../src/WETH9.sol";

contract Handler {
    WETH9 public weth;

    constructor(WETH9 _weth) {
        weth = _weth;
    }
}
```

A word of warning: as soon as we introduce a handler, we are starting to introduce assumptions about the system under test. It's necessary to constrain the system in order to test it meaningfully, but it's also important to stop and consider the assumptions we're making along the way, lest we end up testing a system that's nothing like the real world at all. 

With that caveat in mind, let's start building out our handler contract. We'll start with a `deposit` function that calls through to `weth.deposit()` and passes on a fuzzed `amount` as  `msg.value`:

```solidity
import {Test} from "forge-std/Test.sol";
import {WETH9} from "../../src/WETH9.sol";

contract Handler is Test {
    WETH9 public weth;

    constructor(WETH9 _weth) {
        weth = _weth;
    }
    
    function deposit(uint256 amount) public {
        weth.deposit{ value: amount }();
    }
}
```

Of course, we'll need an ETH balance in order to make a deposit. Let's `deal` ourselves some in the constructor:

```solidity
contract Handler is Test {
    WETH9 public weth;

    constructor(WETH9 _weth) {
        weth = _weth;
        deal(address(this), 10 ether);
    }
    
    function deposit(uint256 amount) public {
        weth.deposit{ value: amount }();
    }
}
```

Over in the tests, we'll need to create our handler contract in `setUp` and configure the fuzzer to test its functions rather than `WETH9`. The helper functions `targetContract(address)` and `excludeContract(address)` in`forge-std/StdInvariant` allow us to include and exclude contracts from invariant fuzzing. 

```solidity
import {Handler} from "./handlers/Handler.sol";

contract WETH9Invariants is Test {
    WETH9 public weth;
    Handler public handler;

    function setUp() public {
        weth = new WETH9();
        handler = new Handler(weth); 

        excludeContract(address(weth));
    }

    function invariant_wethSupplyIsAlwaysZero() public {
        assertEq(0, weth.totalSupply());
    }
}
```

Don't forget to call `excludeContract`! If we don't configure the fuzzer to explictly filter for a given contract, it will implicitly fuzz all methods on all contracts created during `setUp`.

Let's give our new, wrapped tests a run:

```bash
$ forge test
Running 1 test for test/WETH9.invariants.t.sol:WETH9Invariants
Test result: FAILED. 0 passed; 1 failed; finished in 3.89ms

Failing tests:
Encountered 1 failing test in test/WETH9.invariants.t.sol:WETH9Invariants
[FAIL. Reason: Assertion failed.]
        [Sequence]
                sender=0x00000000000000000000000000000000000000a4 
                addr=[test/handlers/Handler.sol:Handler]
                     0x2e234dae75c793f67a35089c9d99245e1c58470b 
                calldata=deposit(uint256),
                args=[65]

 invariant_wethSupplyIsAlwaysZero() (runs: 1, calls: 1, reverts: 0)

Encountered a total of 1 failing tests, 0 tests succeeded
```

A successful failure! Unlike our very first failure, which broke right after `setUp`, this time we failed after the first _call_. The fuzzer has helpfully printed the call sequence that broke our invariant: we called `deposit` with `65` wei, which broke our (now invalid) invariant that `weth.totalSupply()` is always zero.

So then, what should our invariant condition actually be? Thinking in invariants can be very different from the way we think about the system when writing unit tests. Invariants are about properties of the system as a whole, rather than specific reactions to specific inputs. Can we define a property that should always hold for the entire system?

Here's one: in the constrained world of our tests, our `Handler` contract and `WETH9` are a closed system. ETH is only created in the `Handler` when we `deal` it to ourselves, and can only flow into `WETH9` as a `deposit`, since that's the only function we've exposed so far. So we can test a "conservation of ETH" property:  the `weth.totalSupply()`  plus the handler's native ETH balance should always equal the circulating supply of ETH in our closed system.

We gave ourselves 10 Ether when we set up our handler contract, but let's make that a little more realistic. There are currently around 120 million ETH in circulation. Let's `deal` all of it to ourselves when we create the handler:

```solidity
contract Handler is Test {
    WETH9 public weth;

    uint256 public constant ETH_SUPPLY = 120_500_000;

    constructor(WETH9 _weth) {
        weth = _weth;
        deal(address(this), ETH_SUPPLY);
    }

    function deposit(uint256 amount) public {
        weth.deposit{ value: amount }();
    }

}
```

And let's update our invariant to describe this property: 

```solidity
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
```

We'll also add one more condition to our test: we'll `bound` the deposit amount to be less than or equal to the remaining Ether balance in the handler contract:

```solidity
contract Handler is Test {
    WETH9 public weth;

    uint256 public constant ETH_SUPPLY = 120_500_000;

    constructor(WETH9 _weth) {
        weth = _weth;
        deal(address(this), ETH_SUPPLY);
    }

    function deposit(uint256 amount) public {
        amount = bound(amount, 0, address(this).balance);
        weth.deposit{ value: amount }();
    }

}
```

Our tests now pass—and since we're never attempting an invalid deposit that exceeds our balance, none of our calls revert:

```bash
$ forge test
Running 1 test for test/WETH9.invariants.t.sol:WETH9Invariants
[PASS] invariant_conservationOfETH() (runs: 1000, calls: 15000, reverts: 0)
Test result: ok. 1 passed; 0 failed; finished in 1.24s
```

Switching between open/constrained tests and bounded/unbounded calls can be a useful technique as we write invariant tests. For now we'll constrain the values as we build up our handler and invariants, but eventually we may want to remove these assumptions and let the fuzzer run unconstrained to shake out any invalid assumptions we've made along the way.

OK, our tests pass, but we've only exposed one function from `WETH9` through our handler. To test the real world behavior of WETH, we need to expose `withdraw`, `transfer`, and all the rest. Let's add `withdraw` to our handler next:

```solidity
    function withdraw(uint256 amount) public {
        weth.withdraw(amount);
    }

    receive() external payable {}
```

Since `withdraw` will transfer back native Ether to the caller, we also need to add a `receive()` function to our handler contract in order to receive it.

```solidity
$ forge test
Running 1 test for test/WETH9.invariants.t.sol:WETH9Invariants
[PASS] invariant_conservationOfETH() (runs: 1000, calls: 15000, reverts: 3535)
Test result: ok. 1 passed; 0 failed; finished in 1.17s
```

Our tests still pass and the invariant holds! Native Ether is now flowing in two directions in our closed system: from `Handler` into `WETH9` on `deposit` and from `WETH9` back to `Handler` on `withdraw`. But our invariant property—"conservation of ETH" still holds, as we should expect.

Note also that we're now seeing some reverts in the test runs: these will be the cases when the fuzzer attempts to `withdraw` more than our actual balance of WETH. If we `bound` the withdrawal amount to less than the handler's WETH balance, we should see them go away:

```solidity
    function withdraw(uint256 amount) public {
        amount = bound(amount, 0, weth.balanceOf(address(this)));
        weth.withdraw(amount);
    }

    receive() external payable {}
```

```bash
$ forge test
Running 1 test for test/WETH9.invariants.t.sol:WETH9Invariants
[PASS] invariant_conservationOfETH() (runs: 1000, calls: 15000, reverts: 0)
Test result: ok. 1 passed; 0 failed; finished in 1.54s
```

There is one remaining way WETH can come into the world: by sending Ether directly to the `WETH9` fallback function. Let's add a handler function for this, too:

```solidity
    function sendFallback(uint256 amount) public {
        amount = bound(amount, 0, address(this).balance);
        (bool success,) = address(weth).call{ value: amount }("");
        require(success, "sendFallback failed");
    }

```

```
$ forge test
Running 1 test for test/WETH9.invariants.t.sol:WETH9Invariants
[PASS] invariant_conservationOfETH() (runs: 1000, calls: 15000, reverts: 0)
Test result: ok. 1 passed; 0 failed; finished in 1.66s
```

Looks good—our invariant still holds.

We'll eventually want to add transfers and approvals to our handler, to ensure that WETH transfers from one account to another don't somehow create or destroy any unaccounted-for WETH. But for now, let's skip them, since we know they don't directly wrap or unwrap Ether.

And if you've read the `WETH9` contract carefully, you may know that there's a big gotcha in this invariant that we haven't quite covered yet. We'll handle it soon.

But for now, let's move on to a second invariant: _solvency_.

It's pretty important that the WETH contract's native Ether balance is always enough to cover all possible withdrawals. Since WETH and native Ether are convertible 1:1, the `WETH9` contract's Ether balance should always equal the sum of all deposits. We can test this invariant in a couple ways: at a high level, we can look at all deposits minus all withdrawals from the contract. At a lower level, we can sum up the individual balances of each WETH token owner. Let's look at each in turn. Both of these approaches will require a new technique, "ghost variables".

We can use "ghost variables" in our handler contract to track state that is not otherwise exposed by the contract under test. For example, keeping track of the sum of all individual deposits into the `WETH9` contract using an accumulator variable.

Let's add a `ghost_depositSum` state variable to our contract, and increase it every time we make a deposit:

```solidity
    uint256 ghost_depositSum;

    function deposit(uint256 amount) public {
        amount = bound(amount, 0, address(this).balance); 
        weth.deposit{ value: amount }();
        ghost_depositSum += amount;
    }
    
```

I like to prefix these variable names with `ghost_`, but that's just a convention. 

While we're at it, let's also add `ghost_withdrawSum` to track all withdrawals. We expect the native Ether balance of the WETH contract to be equal to all the deposits minus all the withdrawals. 

```solidity
    uint256 ghost_depositSum;
    uint256 ghost_withdrawSum;

    function deposit(uint256 amount) public {
        amount = bound(amount, 0, address(this).balance); 
        weth.deposit{ value: amount }();
        ghost_depositSum += amount;
    }
    
    function withdraw(uint256 amount) public {
        amount = bound(amount, 0, weth.balanceOf(address(this))); 
        weth.withdraw(amount);
        ghost_withdrawSum += amount;
    }
    
```

We could just as easily decrement `ghost_depositSum` on withdrawals, but I prefer separate variables for two reasons. First, it's nice to have these accounting values available as separate properties. Often, building up a good invariant test suite requires defining properties in terms of intermediate values like "all deposits" and "all withdrawals". I find that exposing these explicitly helps me think about the "building blocks" available to test against when defining new invariants.

Second, I think it's good to be wary about any complex or conditional behavior in ghost variables, which makes it easy to introduce invalid assumptions about the system under test. Sometimes this can't be avoided, but if you can use a simple no-behavior accumulator, you usually should.

Let's add our new invariant:

```solidity
    // The WETH contract's Ether balance should always be
    // at least as much as the sum of all the individual 
    // deposits minus all the individual withdrawals
    function invariant_solvencyDeposits() public {
        assertEq(
          address(weth).balance, 
          handler.ghost_depositSum() - handler.ghost_withdrawSum()
        );
    }
```

```bash
$ forge test
[PASS] invariant_conservationOfETH() (runs: 1000, calls: 14988, reverts: 0)
[FAIL. Reason: Assertion failed.]
        [Sequence]
                sender=0x0000000000000000000000000000000000000c88
                  addr=[test/handlers/Handler.sol:Handler]
                       0x2e234dae75c793f67a35089c9d99245e1c58470b 
                  calldata=deposit(uint256), 
                  args=[826074471]
                sender=0x0000000000000000000000000000000000000ffb 
                  addr=[test/handlers/Handler.sol:Handler]
                       0x2e234dae75c793f67a35089c9d99245e1c58470b 
                  calldata=deposit(uint256), 
                  args=[1]
                sender=0xeaae00d9e5544c3fd4fc519f81e2a4747920f369 
                  addr=[test/handlers/Handler.sol:Handler]
                       0x2e234dae75c793f67a35089c9d99245e1c58470b                 
                  calldata=sendFallback(uint256), 
                  args=[1007]

 invariant_solvencyDeposits() (runs: 1000, calls: 14988, reverts: 0)
Test result: FAILED. 1 passed; 1 failed; finished in 2.06s
```

It failed—can you see why? Learning to read failed call sequences is part of the art of invariant testing. One important clue is that the last call in the sequence should always be the one that caused the invariant to fail. In this case, it looks like we forgot to account for deposits into the contract through the fallback function. These need to increment our ghost variable, too:

```solidity
    function sendFallback(uint256 amount) public {
        amount = bound(amount, 0, address(this).balance);
        (bool success,) = address(weth).call{ value: amount }("");
        require(success, "sendFallback failed");
        ghost_depositSum += amount;
    }
```

With this change in place, our tests should now pass:

```bash
$ forge test
Running 2 tests for test/WETH9.invariants.t.sol:WETH9Invariants
[PASS] invariant_conservationOfETH() (runs: 1000, calls: 15000, reverts: 0)
[PASS] invariant_solvencyDeposits() (runs: 1000, calls: 15000, reverts: 0)
Test result: ok. 2 passed; 0 failed; finished in 2.18s
```

Let's move on and test another solvency invariant: the Ether balance of the WETH contract should be equal to the sum of all _balances_, including balances before and after transfers.

```solidity
    // The WETH contract's Ether balance should always be
    // at least as much as the sum of individual balances
    function invariant_solvencyBalances() public {
        uint256 sumOfBalances = ???
        assertEq(
            address(weth).balance, 
            sumOfBalances
        );
    }
```

How can we track the sum of individual balances? We could add more complicated ghost variables to our handler, like a mapping that tracks each caller's balance, increments on deposits, decrements on withdrawals, and updates the sender and receiver on transfers. But by adding this, we'd basically be replicating the ERC20 logic included in the WETH contract! WETH is simple enough that we could probably get away with it, but this is a dangerous path: if any of our assumptions are wrong in both the contract under test _and_ in our ghost variable logic that replicates it, we will simply be replicating bugs in the implementation in our tests.

In general, I think it's a good principle to always rely on external state from the contract under test when possible. And it _is_ possible here: we can store the address of every caller and iterate over them to add up the `weth.balanceOf` each caller.

If you've paid close attention to the design of the handler so far, you may notice one more thing that's a bit out of sync with reality: so far, every call to `WETH9` is originating from the address of our _handler_ contract. That means only one address (the handler contract) ever has a balance in the `WETH9` contract, which is not representative of the real world, where many different callers each have an individual balance.

Although Foundry will fuzz different `msg.sender` addresses for each call to our handler, we need to pass them on using `vm.prank` if we want to propagate them to the contract under test.

Let's take a detour to add support for many different _actors_, then return to adding up their balances.

We should be able to introduce multiple actors with different `msg.sender` addresses without breaking any of our existing tests.

We can start by simply passing through `msg.sender` using `vm.prank` before we call into the WETH contract:

```solidity
    function deposit(uint256 amount) public {
        amount = bound(amount, 0, address(this).balance);

        vm.prank(msg.sender);
        weth.deposit{value: amount}();

        ghost_depositSum += amount;
    }

    function withdraw(uint256 amount) public {
        amount = bound(amount, 0, weth.balanceOf(address(this)));

        vm.prank(msg.sender);
        weth.withdraw(amount);
        
        ghost_withdrawSum += amount;
    }

    function sendFallback(uint256 amount) public {
        amount = bound(amount, 0, address(this).balance);

        vm.prank(msg.sender);
        (bool success,) = address(weth).call{value: amount}("");
        
        require(success, "sendFallback failed");
        ghost_depositSum += amount;
    }
```

However, all these calls will revert if we don't first send the `msg.sender` enough ETH for their deposits. Since our tests are a closed system with a fixed amount of ETH used in our invariant properties, we'll want to actually send Ether using `<address>.call` rather than using a cheatcode to "print" Ether:

```solidity
    function deposit(uint256 amount) public {
        amount = bound(amount, 0, address(this).balance);
        _pay(msg.sender, amount);

        vm.prank(msg.sender);
        weth.deposit{value: amount}();

        ghost_depositSum += amount;
    }

    function withdraw(uint256 amount) public {
        amount = bound(amount, 0, weth.balanceOf(address(this)));

        vm.prank(msg.sender);
        weth.withdraw(amount);
        
        ghost_withdrawSum += amount;
    }

    function sendFallback(uint256 amount) public {
        amount = bound(amount, 0, address(this).balance);
        _pay(msg.sender, amount);

        vm.prank(msg.sender);
        (bool success,) = address(weth).call{value: amount}("");
        
        require(success, "sendFallback failed");
        ghost_depositSum += amount;
    }

    function _pay(address to, uint256 amount) internal {
        (bool s,) = to.call{value: amount}("");
        require(s, "pay() failed");
    }
```

Finally, we need to update the `bound` condition in `withdraw` not to exceed the `msg.sender`'s WETH balance on withdrawals:

```solidity
    function deposit(uint256 amount) public {
        amount = bound(amount, 0, address(this).balance);
        _pay(msg.sender, amount);

        vm.prank(msg.sender);
        weth.deposit{value: amount}();

        ghost_depositSum += amount;
    }

    function withdraw(uint256 amount) public {
        amount = bound(amount, 0, weth.balanceOf(address(this)));

        vm.prank(msg.sender);
        weth.withdraw(amount);
        
        ghost_withdrawSum += amount;
    }

    function sendFallback(uint256 amount) public {
        amount = bound(amount, 0, address(this).balance);
        _pay(msg.sender, amount);

        vm.prank(msg.sender);
        (bool success,) = address(weth).call{value: amount}("");
        
        require(success, "sendFallback failed");
        ghost_depositSum += amount;
    }

    function _pay(address to, uint256 amount) internal {
        (bool s,) = to.call{value: amount}("");
        require(s, "pay() failed");
    }
```

```bash
$ forge test
Running 2 tests for test/WETH9.invariants.t.sol:WETH9Invariants
[PASS] invariant_conservationOfETH() (runs: 10000, calls: 150000, reverts: 8)
[PASS] invariant_solvencyDeposits() (runs: 10000, calls: 150000, reverts: 8)
Test result: ok. 2 passed; 0 failed; finished in 95.41s
```

So far, so good. Many different addresses are now interacting with the `WETH9` contract under test during our invariant runs, but we need to capture them in our handler in order to reconstruct their balances as part of our test assertion. Ideally, we'd capture a deduplicated list of all the caller addresses we care about.

If you'll forgive a short detour into Solidity data structures, one clean way to capture this is with a modifier and a simple `AddressSet`. Let's start with an `AddressSet` struct that stores a dynamic `address[]` array and a mapping to track which addresses it contains:

```solidity
struct AddressSet {
    address[] addrs;
    mapping(address => bool) saved;
}
```

We can then define a library that adds some behavior to this data structure. `add(address)` will push an address into the `saved` array only if it has not already been seen. `contains(address)` returns whether an address is in the set, and `count` returns the total number of addresses in the set:

```solidity
library LibAddressSet {
    function add(AddressSet storage s, address addr) internal {
        if (!s.saved[addr]) {
            s.addrs.push(addr);
            s.saved[addr] = true;
        }
    }

    function contains(
      AddressSet storage s, 
      address addr
    ) internal view returns (bool) {
        return s.saved[addr];
    }

    function count(AddressSet storage s) internal view returns (uint256) {
        return s.addrs.length;
    }
}
```

Let's use the library in our handler and create an internal `AddressSet` named `_actors`. And let's expose the array of saved actors through an external function so we can access it from our tests:

```solidity
contract Handler is Test {
    using LibAddressSet for AddressSet;

    AddressSet internal _actors;

    // Other handler stuff omitted here

    function actors() external returns (address[] memory) {
      return _actors.addrs;
    }	
}
```

Finally, we'll add  a `captureCaller` modifier that automatically adds `msg.sender` to our `_actors` set on every function where it's applied:

```solidity
    modifier captureCaller() {
        _actors.add(msg.sender);
        _;
    }
```

Now we can load the `actors()` in our test, add up their balances, and make our assertion:

```solidity
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
```

```bash
$ forge test
Running 3 tests for test/WETH9.invariants.t.sol:WETH9Invariants
[PASS] invariant_conservationOfETH() (runs: 10000, calls: 150000, reverts: 10)
[PASS] invariant_solvencyBalances() (runs: 10000, calls: 150000, reverts: 10)
[PASS] invariant_solvencyDeposits() (runs: 10000, calls: 150000, reverts: 10)
Test result: ok. 3 passed; 0 failed; finished in 134.45s
```

Can we do better? Iterating over all callers to calculate a ghost variable or make some assertion is a pretty common pattern, and as we write more tests, we'll probably find ourselves repeating it. Let's flex some rarely used Solidity muscles and add one more abstraction.

Did you know you can pass function types as arguments in Solidity? We can define `forEach` and `reduce` for `AddressSet`:

```solidity
library LibAddressSet {

    function forEach(
        AddressSet storage s, 
        function(address) external returns (address[] memory) func
    ) internal {
        for (uint256 i; i < s.addrs.length; ++i) {
            func(s.addrs[i]);
        }
    }

    function reduce(
        AddressSet storage s, 
        uint256 acc, 
        function(uint256,address) external returns (uint256) func
    )
        internal
        returns (uint256)
    {
        for (uint256 i; i < s.addrs.length; ++i) {
            acc = func(acc, s.addrs[i]);
        }
        return acc;
    }
}
```

(One thing that's kind of fun about testing in Solidity is getting the chance to do stuff like this that is usually gas-cost-prohibitive in production contracts).

To use these from our tests, we can expose them from the handler:

```solidity
    function forEachActor(function(address) external func) public {
        return _actors.forEach(func);
    }

    function reduceActors(
        uint256 acc, 
        function(uint256,address) external returns (uint256) func
    )
        public
        returns (uint256)
    {
        return _actors.reduce(acc, func);
    }

```

Now, we can rewrite our test and tally up balances using a reducer:

```solidity
    // The WETH contract's Ether balance should always be
    // at least as much as the sum of individual balances
    function invariant_solvencyBalances() public {
        uint256 sumOfBalances = handler.reduceActors(0, this.accumulateBalance);
        assertEq(
            address(weth).balance, 
            sumOfBalances
        );
    }

    function accumulateBalance(
      uint256 balance, 
      address caller
    ) external view returns (uint256) {
        return balance + weth.balanceOf(caller);
    }
```

Cool trick, right? There's one more change we need to make in the test contract to make this all work. Now that we've added some external functions to our handler to expose our iterators, we want to exclude them from fuzzing. We need to use the more complex `targetSelector` helper to specify the exact selectors we want the fuzzer to target and exclude everything else: 

```solidity
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

        excludeContract(address(weth));
    }
```

```bash
$ forge test
Running 3 tests for test/WETH9.invariants.t.sol:WETH9Invariants
[PASS] invariant_conservationOfETH() (runs: 10000, calls: 150000, reverts: 10)
[PASS] invariant_solvencyBalances() (runs: 10000, calls: 150000, reverts: 10)
[PASS] invariant_solvencyDeposits() (runs: 10000, calls: 150000, reverts: 10)
Test result: ok. 3 passed; 0 failed; finished in 179.86s
```