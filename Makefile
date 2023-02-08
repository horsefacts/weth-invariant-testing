check:
	git apply "bugs/$(bug).patch" && forge test

clean:
	git checkout src/WETH9.sol