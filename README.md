# WETH Invariant Testing

![Build Status](https://github.com/horsefacts/weth-invariant-testing/actions/workflows/.github/workflows/test.yml/badge.svg?branch=main)

There's been a lot of interest recently in _invariant testing_, a new feature in the [Foundry](https://github.com/foundry-rs/foundry) toolkit, but so far there's not much documentation on getting started with this advanced testing technique. The Maple Finance [invariant test repo](https://github.com/maple-labs/maple-core-v2/tree/main/tests/invariants), this [example repo](https://github.com/lucas-manuel/invariant-examples) from [Lucas Manuel](https://twitter.com/lucasmanuel_eth), and a forthcoming section in the [Foundry book](https://github.com/foundry-rs/book/pull/760/files) are all great resources, but it's still tough to get up and running. 

In this short guide, we'll write invariant tests from the ground up for Wrapped Ether, one of the most important contracts on mainnet.

## How invariant tests work

I like to think of invariant testing as a kind of super-fuzzing. If you've written Forge [fuzz tests](https://book.getfoundry.sh/forge/fuzz-testing) before, the core concepts are similar. You might write a Forge fuzz test like the following one to test a property about a given function, like `a + b == b + a`:

```solidity
    function test_fuzz_additionIsCommutative(uint256 a, uint256 b) public {
        assertEq(math.add(a, b), math.add(b, a));
    }
```

During a fuzz test run, the fuzzer will call this test with many randomly generated values for `a` and `b`, and verify that our assertion holds for each one. This lets us test a specific property of a specific function in a specific contract.

Invariant tests apply the same idea to the _system as a whole_. Rather than defining properties of specific functions, we define "invariant properties" about a specific contract or system of contracts that should always hold. These may be things like "this vault contract always holds enough tokens to cover all withdrawals," "x * y always equals k in a Uniswap pool," or "this ERC20 token's total supply always equals the sum of all individual balances."

During an invariant test run, the fuzzer goes ham, running against _all_ functions in _all_ contracts (at least until we choose to constrain it). The fuzzer generates random call sequences with random calldata, and checks our defined invariants after every call. If any call sequence breaks a defined invariant, the tests fail.  

Invariant tests can be great tools for shaking out invalid assumptions, complex edge cases, and unexpected interactions in a smart contract system. But it can also be challenging to channel the  fuzzer's unconstrained chaos into a suite of meaningful, reliable tests. 

## The WETH contract

We'll be testing the Wrapped Ether contract in this guide.

The Wrapped Ether token allows users to `deposit` and "wrap" native Ether, which is represented as `WETH`, an ERC20 token.  Users who own `WETH` can `withdraw` native Ether by exchanging their `WETH` tokens for Ether at a 1:1 exchange rate. 

Wrapped Ether is a simple but critical primitive in the Ethereum application layer. It enables applications designed to be composable with ERC20 tokens to use a representation of native Ether, and it mitigates the security risks to end users and smart contract systems associated with native Ether transfers.

The canonical [wrapped Ether contract](https://github.com/gnosis/canonical-weth/blob/0dd1ea3e295eef916d0c6223ec63141137d22d67/contracts/WETH9.sol), known as `WETH9`, is only a little over 50 lines of code:

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

    function transferFrom(
        address src, 
        address dst, 
        uint256 wad
    ) public returns (bool) {
        require(balanceOf[src] >= wad);

        if (
            src != msg.sender && 
            allowance[src][msg.sender] != type(uint256).max
        ) {
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

(I've slightly modified the version above to compile in Solidity 0.8.x).

The [mainnet WETH contract](https://etherscan.io/address/0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2) currently holds over 3.9 million Ether, worth over $6.5 billion USD. Any bugs in WETH would be a very big deal. So let's write some invariant tests that verify that the most important properties of WETH really do hold. 

## Getting started

Invariant test features in Foundry and `forge-std` have been under active development lately, so before we start, make sure to run `foundryup` to install the latest version of `forge`:

```bash
$ foundryup
```

Next, let's spin up a new Foundry project, remove the example `Counter.sol` and `Counter.t.sol`, and add the `WETH9` contract as `src/WETH9.sol`:

```bash
$ tree src
src
└── WETH9.sol
```

## Invariant test setup

An invariant test contract looks just like the `Test` contracts you already know and love from unit and fuzz testing with Foundry.  In the latest version of `forge-std`, all the helpers we'll need in order to define and test invariants are now included in the base `forge-std/Test.sol` contract. (If you're using `1.3.0`, the latest stable release, you may also need to import and inherit from `forge-std/InvariantTest.sol`).

Let's create a test contract in `test/WETH9.invariants.t.sol`:

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {InvariantTest} from "forge-std/InvariantTest.sol";
import {WETH9} from "../src/WETH9.sol";

contract WETH9Invariants is Test, {
    WETH9 public weth;

    function setUp() public {
        weth = new WETH9();
    }

    function invariant_badInvariantThisShouldFail() public {
        assertEq(1, weth.totalSupply());
    }
}
```

I like to include `invariants` in the name of my invariant test files to distinguish them from others, but that's just a convention, not required by the test runner.

Hopefully this looks familiar if you've used Foundry: we declare our contract under test as a state variable, create an instance of the contract in `setUp`, and write test functions using helpers like `assertEq` that make assertions about the state of the system.

Unlike unit and fuzz tests, invariants must start with the `invariant_` prefix, but otherwise this looks a lot like an everyday Forge unit test.

In case the name wasn't clear, our example invariant should fail:

```solidity
    function invariant_badInvariantThisShouldFail() public {
        assertEq(1, weth.totalSupply());
    }
```

Let's give it a try and see what happens. The test runner picks up invariant tests alongside normal unit and fuzz tests automatically. Just run `forge test`:

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

The test fails right away. In fact, it's failing the _very first time_ it checks the invariants, immediately after `setUp`, and before the fuzzer even makes any calls to the contract under test. Since the WETH `totalSupply()` starts at zero, the assertion fails. (Good, that's what we expected).

Let's make a change and try again. We'll change the name, too, since our invariant should actually pass now:

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

This time,  we can see that the fuzzer made some actual calls to the contract under test: `1000` runs, `15000` calls, and `8671` reverts. This feedback from the fuzzer is very useful diagnostic information as you write and refine invariant tests:

- Runs: the total number of random call sequences generated by the fuzzer.
- Calls: the total number of _calls_ the fuzzer made to our contract under test during this test run. This is equal to the number of `runs` times the `depth` of each call sequence defined in `foundry.toml`.
- Reverts: the number of calls that reverted in this test run. In this case, around 58% of the randomly generated calls to our contract reverted.

Of course, in the real world the WETH supply is not always zero. So why does our test pass? A unit test might help clarify. 

A nice feature of Foundry is that it's possible to define unit and invariant tests in the same test class. This can be useful for quick explorations like this, or for concretizing and testing a failed fuzz/invariant result to understand why it failed. Add this right after our invariant test function:

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

Turns out, the WETH contract allows callers to "deposit" zero ETH in exchange for zero WETH!

So here's what's happening under the hood:
- The fuzzer is examining all the public functions on the `WETH9` contract and calling them with random arguments.
- Many of these calls will revert. For example, `withdraw`, `transfer`, and `transferFrom` should all revert in most cases since there are no balances or tokens to transfer.
- Some of these calls will succeed, but do nothing, like calling `deposit` with zero `msg.value`.
- The fuzzer generates random call sequences and calldata, but does not fuzz `msg.value`, so all calls to the WETH contract have zero value. Since WETH is only created when a caller deposits native ETH, no ETH enters the WETH contract and no WETH tokens are ever created.
- The WETH balance remains zero and our invariant holds.

This kind of "open testing"—allowing the fuzzer to wreak havoc on all contracts, all methods, and all arguments at once—can be useful in some scenarios, and it's usually a good place to start when building up an invariant test suite. But you'll often want to simulate specific conditions, like a caller sending along native ETH to make a WETH `deposit`, more precisely. 

There is also a probabilistic trade-off between exploring more random call sequences and finding "meaningful" sequences that actually test our invariants. Exposing more contracts and functions to the fuzzer generates much more "surface area" to fuzz that _could_ expose interesting ways to break the invariants. But if 99% of those sequences revert because their arguments or ordering are unrealistic, we might not really be testing our invariants in a useful way at all.

In order to simulate native Ether transfers and test the conditions we really care about, we need to introduce a new concept and another contract: a _handler_.

## Handlers

A _handler_ is a wrapper contract that we'll use to manage interactions with our contract under test. Rather than expose the `WETH9` functions directly to the fuzzer, we'll instead point the fuzzer at our _handler_ contract and add functions to the handler that delegate to `WETH9`. This lets us use standard Forge cheatcodes and helpers like `vm.prank` and `deal` to set up tests with the conditions we care about. 

A handler is just another helper contract. Typically, I pass in the contract under test as a constructor argument. Let's add the following in `test/handlers/Handler.sol`:

```solidity
import {WETH9} from "../../src/WETH9.sol";

contract Handler {
    WETH9 public weth;

    constructor(WETH9 _weth) {
        weth = _weth;
    }
}
```

A word of warning: as soon as we introduce a handler, we are starting to introduce assumptions about the system under test. It's necessary to constrain the system in order to test it meaningfully, but it's also important to stop and consider the assumptions we're making along the way, lest we end up testing a system that's nothing like the real world at all. As we build out our tests, we should make sure we think about each assumption that we add along the way. 

With that caveat in mind, let's start building out our handler contract. We'll start with a `deposit` function that calls through to `weth.deposit()` and passes on a fuzzed `amount` as  `msg.value`:

```solidity
import {WETH9} from "../../src/WETH9.sol";

contract Handler {
    WETH9 public weth;

    constructor(WETH9 _weth) {
        weth = _weth;
    }
    
    function deposit(uint256 amount) public {
        weth.deposit{ value: amount }();
    }
}
```

Remember, the fuzzer will now generate random calls with random values to the functions we define on the _handler_. It's up to us to pass through these arguments to the contract under test, or constrain them if necessary.

Of course, we'll need an ETH balance in order to make a deposit. Let's `deal` ourselves some Ether in the constructor:

```solidity
import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

contract Handler is CommonBase, StdCheats, StdUtils {
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

Over in the tests, we'll need to create our handler contract in `setUp` and configure the fuzzer to test its functions rather than call `WETH9` directly. The helper functions `targetContract(address)` and `excludeContract(address)` in`forge-std/StdInvariant` allow us to include and exclude contracts from invariant fuzzing. 

```solidity
import {Handler} from "./handlers/Handler.sol";

contract WETH9Invariants is Test {
    WETH9 public weth;
    Handler public handler;

    function setUp() public {
        weth = new WETH9();
        handler = new Handler(weth); 

        targetContract(address(handler));
    }

    function invariant_wethSupplyIsAlwaysZero() public {
        assertEq(0, weth.totalSupply());
    }
}
```

Don't forget to call `targetContract`! If we don't configure the fuzzer to explictly filter for a given contract, it will implicitly fuzz all methods on all contracts created during `setUp`.

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

## Conservation of Ether

So then, what should our invariant condition actually be? Thinking in invariants can be very different from the way we think about the system when writing unit tests. Invariants are about properties of the system as a whole, rather than specific reactions to specific inputs. Can we define a property that should always hold for the entire system?

Here's one: in the constrained world of our tests, our `Handler` contract and `WETH9` are a closed system. ETH is only created in the `Handler` when we `deal` it to ourselves, and can only flow into `WETH9` as a `deposit`, since that's the only function we've exposed so far. So we can test a "conservation of Ether" property:  the `weth.totalSupply()`  plus the handler's Ether balance should always equal the circulating supply of ETH in our closed system.

We gave ourselves 10 Ether when we set up our handler contract, but let's make that a little more realistic. There are currently around 120-and-a-half million ETH in circulation. Let's `deal` all of it to ourselves when we create the handler:

```solidity
contract Handler is CommonBase, StdCheats, StdUtils {
    WETH9 public weth;

    uint256 public constant ETH_SUPPLY = 120_500_000 ether;

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

We'll also add one more condition to our test: we'll `bound` the deposit amount to be less than or equal to the remaining Ether balance in the handler contract, so calls don't revert when they attempt to deposit more ETH than they have available:

```solidity
contract Handler is CommonBase, StdCheats, StdUtils {
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

Switching back and forth between open/constrained tests and bounded/unbounded calls can be a useful technique as we write invariant tests. For now we'll constrain the values as we build up our handler and invariants, but eventually we may want to remove these assumptions and let the fuzzer run wild to shake out any invalid assumptions we've made along the way.

## Adding handler functions

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

Our tests still pass and the invariant holds! Native Ether is now flowing in two directions in our closed system: from `Handler` into `WETH9` on `deposit` and from `WETH9` back to `Handler` on `withdraw`. But our "conservation of ETH" invariant still holds, as we should expect.

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

Let's move on to a second invariant: _solvency_.

## Solvency and ghost variables 

It's pretty important that the WETH contract's native Ether balance is always enough to cover all possible withdrawals from the contract. Since WETH and native Ether are convertible 1:1, the `WETH9` contract's Ether balance should always equal the sum of all deposits. 

We can test this invariant in a couple ways: at a high level, we can look at all deposits minus all withdrawals from the contract. At a lower level, we can sum up the individual balances of each WETH token owner. Let's look at each in turn. Both of these approaches will require a new technique, _ghost variables_.

We can use _ghost variables_ in our handler contract to track state that is not otherwise exposed by the contract under test. For example, keeping track of the sum of all individual deposits into the `WETH9` contract using an accumulator variable.

Let's add a `ghost_depositSum` state variable to our contract, and increase it every time we make a deposit:

```solidity
    uint256 public ghost_depositSum;

    function deposit(uint256 amount) public {
        amount = bound(amount, 0, address(this).balance); 
        weth.deposit{ value: amount }();
        ghost_depositSum += amount;
    }
    
```

I like to prefix these variable names with `ghost_`, but that's just a convention. There's nothing special about these variables besides their purpose. Otherwise, they are standard Solidity state variables in our helper contract. 

While we're at it, let's also add `ghost_withdrawSum` to track all withdrawals. We expect the native Ether balance of the WETH contract to be equal to all the deposits minus all the withdrawals. 

```solidity
    uint256 public ghost_depositSum;
    uint256 public ghost_withdrawSum;

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

We could just as easily decrement `ghost_depositSum` on withdrawals, but I prefer to use separate variables for two reasons. First, it's nice to have these accounting values available as separate properties. Often, building up a good invariant test suite requires defining properties in terms of intermediate values like "all deposits" and "all withdrawals". I find that exposing these explicitly helps me think about the "building blocks" available to test against when defining new invariants.

Second, I think it's good to be wary about any complex or conditional behavior in ghost variables, which makes it easy to introduce invalid assumptions about the system under test. Sometimes this can't be avoided, but if you can use a simple no-behavior accumulator, you usually should.

Let's add our new invariant:

```solidity
    // The WETH contract's Ether balance should always 
    // equal the sum of all the individual deposits 
    // minus all the individual withdrawals
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

It failed—can you see why? Learning to read failed call sequences is part of the art of invariant testing. One important clue is that the _last call in the sequence_ should always be the one that caused the invariant to fail. In this case, it looks like we forgot to account for deposits into the contract through the fallback function. These need to increment our ghost variable, too:

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

Let's move on and test another solvency invariant: the Ether balance of the WETH contract should be equal to the sum of all _balances_, including balances before and after transfers. That is, even if users transfer their WETH tokens around, the sum of all balances should stay the same and remain equal to the contract's Ether balance.

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

So how can we track the sum of individual balances? We _could_ add more complicated ghost variables to our handler, perhaps something like a mapping that tracks each caller's balance, increments on deposits, decrements on withdrawals, and updates the sender and receiver on transfers. But by adding this, we'd basically be replicating the ERC20 logic included in the WETH contract! 

WETH is simple enough that we could probably get away with it this time, but this is a dangerous path: if any of our assumptions are wrong in both the contract under test _and_ in our ghost variable logic that replicates it, we will simply be replicating bugs in the implementation in our tests.

In general, I think it's a good principle to rely on external state from the contract under test whenever possible. And it _is_ possible here: we can tally up the balance of each user by

1. Saving the address of every caller 
2. iterating over each address and retrieving the `weth.balanceOf` the caller
3. adding up all the balances

We'll need to add some helpers to do this calculation.

If you've paid close attention to the design of the handler so far, you may notice one more thing that's a bit out of sync with reality: so far, every call to `WETH9` is originating from the address of our _handler_ contract. That means only one address (the handler contract) ever has a balance in the `WETH9` contract, which is not representative of the real world, where many different callers each have an individual balance.

## Introducing actors

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

However, all these calls will revert if we don't first send the `msg.sender` enough ETH for their deposits. Since our tests are a closed system with a fixed amount of ETH used in our invariant properties, we'll want to actually send "real"  Ether using `<address>.call` rather than using a cheatcode to "print" Ether, which would mess with our circulating ETH invariant.

We'll add a `_pay` helper to make transfers before tests that need them:

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

Finally, we need to make two changes in `withdraw`. First, we need to update the `bound` condition in `withdraw` not to exceed the `msg.sender`'s WETH balance on withdrawals, rather than the handler contract's total balance. (Otherwise many of these calls will revert).

Second, we need to send the withdrawn amount back to the handler using `_pay`, to keep all Ether in our closed two-contract system. (Otherwise, it will remain with `msg.sender`):  

```solidity
    function deposit(uint256 amount) public {
        amount = bound(amount, 0, address(this).balance);
        _pay(msg.sender, amount);

        vm.prank(msg.sender);
        weth.deposit{value: amount}();

        ghost_depositSum += amount;
    }

    function withdraw(uint256 amount) public {
        amount = bound(amount, 0, weth.balanceOf(msg.sender));

        vm.startPrank(msg.sender);
        weth.withdraw(amount);
        _pay(address(this), amount);
        vm.stopPrank();
        
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
[PASS] invariant_conservationOfETH() (runs: 10000, calls: 150000, reverts: 0)
[PASS] invariant_solvencyDeposits() (runs: 10000, calls: 150000, reverts: 0)
Test result: ok. 2 passed; 0 failed; finished in 95.41s
```

So far, so good. Many different addresses are now interacting with the `WETH9` contract under test during our invariant runs, but we need to capture them in our handler in order to reconstruct their balances as part of our test assertion. Ideally, we'd capture a deduplicated list of all the caller addresses we care about.

## Creating an `AddressSet`

If you'll forgive a short detour into Solidity data structures, one clean way to capture this is with a modifier and a simple append-only set. Let's start with an `AddressSet` struct that stores a dynamic `address[]` array and a boolean mapping to track which addresses it contains:

```solidity
struct AddressSet {
    address[] addrs;
    mapping(address => bool) saved;
}
```

We can then define a [library](https://docs.soliditylang.org/en/latest/contracts.html#libraries) that adds some behavior to this data structure. `add(address)` will push an address into the `saved` array only if it has not already been seen. `contains(address)` returns whether an address is in the set, and `count()` returns the total number of addresses in the set:
	
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
contract Handler is CommonBase, StdCheats, StdUtils {
    using LibAddressSet for AddressSet;

    AddressSet internal _actors;

    // Other handler stuff omitted here

    function actors() external returns (address[] memory) {
      return _actors.addrs;
    }	
}
```

Finally, we'll add  a `captureCaller` [modifier](https://docs.soliditylang.org/en/v0.8.18/contracts.html#function-modifiers) that automatically adds `msg.sender` to our `_actors` set on every function where it's applied:

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

## Helper iterators

Can we do better? Iterating over all callers to calculate a ghost variable or make some assertion is a pretty common pattern, and as we write more tests, we'll probably find ourselves repeating it. Let's flex some rarely used Solidity muscles and add one more abstraction.

Did you know you can pass [function types](https://docs.soliditylang.org/en/v0.8.18/types.html#function-types) as arguments in Solidity? We can define `forEach` and `reduce`iterators for `AddressSet` that take functions as args:

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

`forEach` will call the given function for every address in our set, while `reduce` will call a given function (that must return a `uint256`) and add its result to an accumulator value.

(One thing that's kind of fun about writing tests in Solidity is getting the chance to do stuff like this that is usually gas-cost-prohibitive or otherwise ill-advised in production contracts).

To use these iterators from our tests, we can expose them from the handler:

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
        uint256 sumOfBalances = handler.reduceActors(
          0, 
          this.accumulateBalance
        );
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

Cool trick, right? 

There's one more change we need to make in the test contract to make this all work. Now that we've added some external functions to our handler to expose our iterators, we want to exclude them from fuzzing. We need to use the more complex `targetSelector` helper from `forge-std/StdInvariants` to specify the exact selectors we want the fuzzer to target and exclude everything else: 

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

        targetContract(address(handler));
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

## Individual balance invariant

Let's add one more invariant property and make use of our `forEach` iterator. This is kind of an odd one, but we'll check that _no individual token owner's balance_ can exceed the `weth.totalSupply()`. An underflow in token transfer logic might be one way to violate this property:

```solidity
    // No individual account balance can exceed the
    // WETH totalSupply().
    function invariant_depositorBalances() public {
        handler.forEachActor(this.assertAccountBalanceLteTotalSupply);
    }

    function assertAccountBalanceLteTotalSupply(address account) external {
        assertLe(weth.balanceOf(account), weth.totalSupply());
    }
```

```bash
Running 4 tests for test/WETH9.invariants.t.sol:WETH9Invariants
[PASS] invariant_conservationOfETH() (runs: 1000, calls: 15000, reverts: 11)
[PASS] invariant_depositorBalances() (runs: 1000, calls: 15000, reverts: 11)
[PASS] invariant_solvencyBalances() (runs: 1000, calls: 15000, reverts: 11)
[PASS] invariant_solvencyDeposits() (runs: 1000, calls: 15000, reverts: 11)
Test result: ok. 4 passed; 0 failed; finished in 5.80s
```

## Including transfers

We still haven't exposed `approve`, `transfer`, and `transferFrom` from our handler. Let's do that now. 

```solidity
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
```

Note that we need to add the _destination_ addresses (the `to` argument in `transfer` and `transferFrom`) to our `_actors` set in order to keep track of all the known actors that might have balances in the system. We can use `add(address)` to add these addresses to the set.

Don't forget to add these new selectors to our configuration in `setUp`:

```solidity
    function setUp() public {
        weth = new WETH9();
        handler = new Handler(weth);

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = Handler.deposit.selector;
        selectors[1] = Handler.withdraw.selector;
        selectors[2] = Handler.sendFallback.selector;
        selectors[3] = Handler.approve.selector;
        selectors[4] = Handler.transfer.selector;
        selectors[5] = Handler.transferFrom.selector;

        targetSelector(
          FuzzSelector({
            addr: address(handler), 
            selectors: selectors
          }
        ));

        targetContract(address(handler));
    }
```

```bash
Running 4 tests for test/WETH9.invariants.t.sol:WETH9Invariants
[PASS] invariant_conservationOfETH() (runs: 1000, calls: 15000, reverts: 8)
[PASS] invariant_depositorBalances() (runs: 1000, calls: 15000, reverts: 8)
[PASS] invariant_solvencyBalances() (runs: 1000, calls: 15000, reverts: 8)
[PASS] invariant_solvencyDeposits() (runs: 1000, calls: 15000, reverts: 8)
Test result: ok. 4 passed; 0 failed; finished in 5.87s
```

## Testing our tests 

We've changed quite a lot of supporting infrastructure and our tests still pass. But are we sure we can really trust them? Unlike unit tests, where mapping one specific input to one expected output is usually pretty clear, I find that invariant tests can sometimes be tricky and accidentally pass when we've introduced an incorrect assumption about the system or a condition that is vacuously true.

One way to ensure our tests are really working is to _test our tests_ by introducing artificial bugs.  Let's intentionally break `deposit` accounting in `WETH9`, run our tests, and see if they fail. Instead of issuing `msg.sender` an amount of WETH equal to `msg.value`, let's give them just 1 wei instead:

```solidity
    function deposit() public payable {
        balanceOf[msg.sender] += 1;
        emit Deposit(msg.sender, msg.value);
    }
```

If our invariant tests are any good, they should catch the bug we introduced:

```bash
$ forge test
Running 4 tests for test/WETH9.invariants.t.sol:WETH9Invariants
[PASS] invariant_conservationOfETH() (runs: 2000, calls: 29974, reverts: 3)
[FAIL. Reason: Assertion failed.]
        [Sequence]
                sender=0x849a5a123d8d365eef30374417ef4fcbba5a9781
                addr=[test/handlers/Handler.sol:Handler]
                     0x2e234dae75c793f67a35089c9d99245e1c58470b 
                calldata=withdraw(uint256), 
                args=[365161364]
                sender=0xcbac49e135a0340b2fca24685962c08ed3aa81c7 
                addr=[test/handlers/Handler.sol:Handler]
                     0x2e234dae75c793f67a35089c9d99245e1c58470b                           
                calldata=sendFallback(uint256), 
                args=[0]

 invariant_depositorBalances() (runs: 2000, calls: 29974, reverts: 3)
[FAIL. Reason: Assertion failed.]
        [Sequence]
                sender=0x000000000000000000000000000000000000006a 
                addr=[test/handlers/Handler.sol:Handler]
                     0x2e234dae75c793f67a35089c9d99245e1c58470b 
                calldata=approve(address,uint256), 
                args=[0x6D50393ED4ed2f7A64e40bdCA11E430dC276bbf3, 26589664]
                sender=0x0f9be7012c9f187334111c3a4f6811e6132e4815 
                addr=[test/handlers/Handler.sol:Handler]
                    0x2e234dae75c793f67a35089c9d99245e1c58470b
                calldata=sendFallback(uint256), 
                args=[2936]

 invariant_solvencyBalances() (runs: 2000, calls: 29974, reverts: 3)
[PASS] invariant_solvencyDeposits() (runs: 2000, calls: 29974, reverts: 3)
Test result: FAILED. 2 passed; 2 failed; finished in 16.18s
```

Looks like they do: we broke the "depositor balances" and "balance solvency" invariants.

A technique I like to use here is to save a few bugs in the contract under test as git `.patch` files in a `bugs` folder inside our project repo. We can then reapply them from time to time to double check that our test suite still works as expected:

```diff
$ git diff > bugs/bug1.patch
$ cat bugs/bug1.patch
diff --git a/src/WETH9.sol b/src/WETH9.sol
index cd55b98..ccb40cb 100644
--- a/src/WETH9.sol
+++ b/src/WETH9.sol
@@ -33,7 +33,7 @@ contract WETH9 {
     }
 
     function deposit() public payable {
-        balanceOf[msg.sender] += msg.value;
+        balanceOf[msg.sender] += 1;
         emit Deposit(msg.sender, msg.value);
     }
 
```

Let's add a few more bug patches. We'll alter `withdraw` to send back only 1 wei:

```diff
diff --git a/src/WETH9.sol b/src/WETH9.sol
index cd55b98..961f03b 100644
--- a/src/WETH9.sol
+++ b/src/WETH9.sol
@@ -40,7 +40,7 @@ contract WETH9 {
     function withdraw(uint256 wad) public {
         require(balanceOf[msg.sender] >= wad);
         balanceOf[msg.sender] -= wad;
-        payable(msg.sender).transfer(wad);
+        payable(msg.sender).transfer(1);
         emit Withdrawal(msg.sender, wad);
     }
```

Remove the call to `deposit` in the fallback function:

```diff
diff --git a/src/WETH9.sol b/src/WETH9.sol
index cd55b98..6e74bd5 100644
--- a/src/WETH9.sol
+++ b/src/WETH9.sol
@@ -29,7 +29,6 @@ contract WETH9 {
     mapping(address => mapping(address => uint256)) public allowance;
 
     fallback() external payable {
-        deposit();
     }
 
     function deposit() public payable {
```

And remove auth checks and change the balance logic in `transferFrom`:

```diff
diff --git a/src/WETH9.sol b/src/WETH9.sol
index cd55b98..26cec99 100644
--- a/src/WETH9.sol
+++ b/src/WETH9.sol
@@ -59,15 +59,8 @@ contract WETH9 {
     }
 
     function transferFrom(address src, address dst, uint256 wad) public returns (bool) {
-        require(balanceOf[src] >= wad);
-
-        if (src != msg.sender && allowance[src][msg.sender] != type(uint256).max) {
-            require(allowance[src][msg.sender] >= wad);
-            allowance[src][msg.sender] -= wad;
-        }
-
-        balanceOf[src] -= wad;
-        balanceOf[dst] += wad;
+        balanceOf[src] -= wad;
+        balanceOf[dst] += 1;
 
         emit Transfer(src, dst, wad);v
```

If we `git apply` each patch in turn and verify that our tests really do catch each artificial bug, we can be pretty confident that they are working: 

```bash
$ git apply bugs/bug2.patch
$ forge test
Running 4 tests for test/WETH9.invariants.t.sol:WETH9Invariants
[FAIL. Reason: Assertion failed.]
 invariant_conservationOfETH() (runs: 6, calls: 84, reverts: 1)
[FAIL. Reason: Assertion failed.]
 invariant_depositorBalances() (runs: 6, calls: 84, reverts: 1)
[FAIL. Reason: Assertion failed.]
 invariant_solvencyBalances() (runs: 6, calls: 84, reverts: 1)
[FAIL. Reason: Assertion failed.]
 invariant_solvencyDeposits() (runs: 6, calls: 84, reverts: 1)
Test result: FAILED. 0 passed; 4 failed; finished in 212.99ms

Encountered a total of 4 failing tests, 0 tests succeeded
```

We can add a simple Makefile that will apply a given patch and run tests:

```make
check:
	git apply "bugs/$(bug).patch" && forge test

clean:
	git checkout src/WETH9.sol
```

To apply a patch and run tests, run:

```bash
$ make bug=bug1 check
```

To undo changes, run:

```bash
$ make clean
```

## Accounting for `selfdestruct` 

Our tests seem to be pretty comprehensive, but there is one final boss battle before we can call them complete. 

There is one intuitive invariant that famously  _does not hold_ for the WETH contract. It has to do with the way `WETH9` calculates `totalSupply()`:

```solidity
    function totalSupply() public view returns (uint256) {
        return address(this).balance;
    }
```

Rather than storing the total token balance in a separate state variable, the WETH contract uses its total Ether balance as the total token supply. This saves gas, but actually [breaks the invariant](https://www.zellic.io/blog/formal-verification-weth) that `weth.totalSupply()` equals the sum of all balances!

There is one clever way to force `WETH9` to increase `totalSupply()` without creating new WETH tokens: calling `selfdestruct` on a contract to [force push Ether](https://docs.soliditylang.org/en/latest/units-and-global-variables.html#contract-related) to its contract balance.

The Foundry fuzzer can do a lot of things, but it won't do that. We'll need to simulate this scenario in our handler ourselves. Let's add a `ForcePush` contract that will `selfdestruct` and send Ether to the WETH contract:

```solidity
contract ForcePush {
    constructor(address dst) payable {
        selfdestruct(payable(dst));
    }
}
```

This contract will immediately destroy itself at construction time and send any balance to the `dst` address in its constructor.

We'll add a handler function to invoke it:

```solidity
    function forcePush(uint256 amount) public {
        amount = bound(amount, 0, address(this).balance);
        new ForcePush{ value: amount }(address(weth));
    }
```

And finally, register our handler functon's selector with the fuzzer:

```solidity
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

        targetContract(address(weth));
    }
```

Our tests now fail, and it looks like they're failing in the places we should expect:

```bash
Running 4 tests for test/WETH9.invariants.t.sol:WETH9Invariants
[PASS] invariant_conservationOfETH() (runs: 5000, calls: 74986, reverts: 9)
[PASS] invariant_depositorBalances() (runs: 5000, calls: 74986, reverts: 9)
[FAIL. Reason: Assertion failed.]
        [Sequence]
                sender=0x0000000000000000000000000000000000000b69 
                addr=[test/handlers/Handler.sol:Handler]
                     0x2e234dae75c793f67a35089c9d99245e1c58470b 
                calldata=forcePush(uint256), 
                args=[2250]

 invariant_solvencyBalances() (runs: 5000, calls: 74986, reverts: 9)
[FAIL. Reason: Assertion failed.]
        [Sequence]
                sender=0x0000000000000000000000000000000000000b69 
                addr=[test/handlers/Handler.sol:Handler]
                     0x2e234dae75c793f67a35089c9d99245e1c58470b 
                calldata=forcePush(uint256), 
                args=[2250]

 invariant_solvencyDeposits() (runs: 5000, calls: 74986, reverts: 9)
Test result: FAILED. 2 passed; 2 failed; finished in 68.53s
```

"Conservation of ETH" still passes. Since it's a property of `weth.totalSupply()` and the handler balance, it's not affected by the balance inconsistency, as `weth.totalSupply()` accounts for the full `address(weth).balance`. So does our depositor balance invariant, since it's still the case that no depositor's balance can exceed `weth.totalSupply()`.

But our two solvency invariants will need an update. We could simply relax the invariant to check that the WETH contract's Ether balance is _at least as much_ as the individual deposits/balances. This is a reasonable property, and still means the contract is solvent. But we have the ability to account for the amount of force-pushed Ether exactly, so let's do so.

We'll add one more ghost variable to our handler and increment it when we force push Ether:

```solidity
    uint256 public ghost_forcePushSum;
    
    function forcePush(uint256 amount) public {
        amount = bound(amount, 0, address(this).balance);
        new ForcePush{ value: amount }(address(weth));
        ghost_forcePushSum += amount;
    }
```

And update our invariants to account for this extra Ether:

```solidity
    // The WETH contract's Ether balance should always be
    // equal to the sum of all individual deposits
    // minus all individual withrawals, plus any
    // force-pushed Ether in the contract
    function invariant_solvencyDeposits() public {
        assertEq(
            address(weth).balance, 
            handler.ghost_depositSum() + 
            handler.ghost_forcePushSum() - 
            handler.ghost_withdrawSum()
        );
    }

    // The WETH contract's Ether balance should always be
    // equal to the sum of individual balances plus any
    // force-pushed Ether in the contract
    function invariant_solvencyBalances() public {
        uint256 sumOfBalances = handler.reduceActors(0, this.accumulateBalance);
        assertEq(
            address(weth).balance - handler.ghost_forcePushSum(), 
            sumOfBalances
        );
    }

```

Invariant tests are a powerful tool, but this case is an interesting illustration of one of its blind spots. A symbolic execution test that models Ether sends via `selfdestruct` would catch this bug pretty quickly, but we nearly missed it with the fuzzer and had to rely on our own knowledge about the WETH contract to cover it. On the other hand, invariant tests are much faster to run than tests using a prover/constraint solver, and allow us to build up a suite of reasonably high confidence invariant properties that we might want to further verify using even more powerful tools.

However, it's important to remember that all fuzz tests are probabilstic: unlike a symbolic test that explores all possible execution paths, fuzz tests are only as good as the random data they generate. This is still very, very, good most of the time! But as with all smart contract testing, we should do it all when we can: unit tests, fuzz tests, fork tests, invariant tests, and formal verification. 

Let's give our final tests one good, long, run: 25000 runs with a depth of 25 calls:

```bash
Running 4 tests for test/WETH9.invariants.t.sol:WETH9Invariants
[PASS] invariant_conservationOfETH() (runs: 25000, calls: 625000, reverts: 15)
[PASS] invariant_depositorBalances() (runs: 25000, calls: 625000, reverts: 15)
[PASS] invariant_solvencyBalances() (runs: 25000, calls: 625000, reverts: 15)
[PASS] invariant_solvencyDeposits() (runs: 25000, calls: 625000, reverts: 15)
Test result: ok. 4 passed; 0 failed; finished in 6995.00s
```

Success! Next time Crypto Twitter starts spreading FUD about "unbacked WETH," send them this repo and tell them to kick rocks.

## More resources
- [Maple Finance invariant tests repo](https://github.com/maple-labs/maple-core-v2/tree/main/tests/invariants)
- [invariant-examples repo](https://github.com/lucas-manuel/invariant-examples)

_Thanks to [msolomon44](https://twitter.com/msolomon44), [zachobront](https://twitter.com/zachobront), and [lucasmanuel_eth](https://twitter.com/lucasmanuel_eth) for reviewing earlier drafts of this guide._