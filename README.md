# cellars
Sommelier Ethereum Cellars Work in Progress

## Testing and Development on testnet

### Dependencies
* [nodejs](https://nodejs.org/en/download/) - >=v8, tested with version v14.15.4
* [python3](https://www.python.org/downloads/release/python-368/) from version 3.6 to 3.8, python3-dev
* [brownie](https://github.com/iamdefinitelyahuman/brownie) - tested with version [1.14.6](https://github.com/eth-brownie/brownie/releases/tag/v1.14.6)

The contracts are compiled using [Vyper](https://github.com/vyperlang/vyper), however, installation of the required Vyper versions is handled by Brownie.

### Compiling Contract With Hardhat

Hardhat is a development environment that allows you to compile, deploy, test, and debug your Ethereum software.

To compile cellars with Remix, follow these steps:

- Install hardhat with `npm` by running the code below in your terminal.

```
npm install --save-dev hardhat
```

After installation, run the command below in your terminal to create a new project:

```
npx hardhat
```

Follow the guide to create a sample project. Navigate to the project you created `Greeter.sol` and put the cellar contract in `Greatersol`.

- Install the following dependencies:

```
npm install --save-dev @nomiclabs/hardhat-waffle ethereum-waffle chai @nomiclabs/hardhat-ethers ethers
```

- Compile your project by running the command below.

```
npx hardhat compile
```

- Your contract's `abi` can be found in the `artifacts` folder, i.e. `artifacts/Greeter.json`


### Compiling Contract With Remix

Remix is an Ethereum IDE, for compiling, debuging and deploying contracts. There's a cloud version of [Remix](https://remix.ethereum.org/) for people who want to compiling, debuging and deploying contracts remotely.

To compile cellars with Remix cloud IDE, follow these steps:

- Create a file under **contracts** and put in the cellar contract in the file you just created.
- Navigate to **Solidity Compiler** in Remix's side navigation bar.
- Click on enable optimization to avoid `CompilerError: Stack too deep when compiling inline assembly: Variable headStart is 1 slot(s) too deep inside the stack.` error.
- Click on **Compile**.
- After compling, click on `CellarPoolShare` under **CONTRACT**
- Click on **Compilation Details** and copy the **Abi** or other details.

### Running the Tests

```bash
brownie test
```
