### Compiling Contract With Hardhat

Hardhat is a development environment that allows you to compile, deploy, test, and debug your Ethereum software.

To compile cellars contract with hardhat, follow these steps:

- Install hardhat with `npm` by running the code below in your terminal.

```
npm install --save-dev hardhat
```


- Compile your project by running the command below.

```
npx hardhat compile
```

- Your contract's `abi` can be found in the `artifacts` folder, i.e. `artifacts/CellarPoolShare.sol`


### Compiling Contract With Remix

Remix is an Ethereum IDE, for compiling, debuging and deploying contracts. There's a cloud version of [Remix](https://remix.ethereum.org/) for people who want to compiling, debuging and deploying contracts remotely.

To compile cellars with Remix cloud IDE, follow these steps:

- Create a file under **contracts** and put in the cellar contract in the file you just created.
- Navigate to **Solidity Compiler** in Remix's side navigation bar.
- Click on enable optimization to avoid `CompilerError: Stack too deep when compiling inline assembly: Variable headStart is 1 slot(s) too deep inside the stack.` error.
- Click on **Compile**.
- After compling, click on `CellarPoolShare` under **CONTRACT**
- Click on **Compilation Details** and copy the **Abi** or other details.
