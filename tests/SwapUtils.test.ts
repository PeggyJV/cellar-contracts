import {ethers} from "hardhat";
import {
    SwapUtils,

} from "../src/types";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import {BigNumber, Contract} from "ethers";
import {expect} from "chai";


describe("SwapUtils", () => {

    let owner: SignerWithAddress;
    let alice: SignerWithAddress;
    let bob: SignerWithAddress;
    let swapUtils: Contract;
    let dai: Contract;
    let usdc: Contract;


    const bigNum = (number: number, decimals: number) => {
        const [characteristic, mantissa] = number.toString().split(".");
        const padding = mantissa ? decimals - mantissa.length : decimals;
        return BigNumber.from(characteristic + (mantissa ?? "") + "0".repeat(padding));
    };

    // Manipulate local balance (value must be bytes32 string)
    const setStorageAt = async (address: string, index: string, value: string) => {
        await ethers.provider.send("hardhat_setStorageAt", [address, index, value]);
        await ethers.provider.send("evm_mine", []); // Just mines to the next block
    };

    const toBytes32 = (bn: BigNumber) => {
        return ethers.utils.hexlify(ethers.utils.zeroPad(bn.toHexString(), 32));
    };


    beforeEach(async () => {

        [owner, alice, bob] = await ethers.getSigners();


        const Token = await ethers.getContractFactory(
            "@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20"
        );
        dai = await Token.attach("0x6B175474E89094C44Da98b954EedeAC495271d0F");
        usdc = await Token.attach("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48");


        const SwapUtils = await ethers.getContractFactory(
            "$SwapUtils"
        );
        swapUtils = await SwapUtils.deploy();

        // Set DAI balance for owner (1000$)
        let index = ethers.utils.solidityKeccak256(
            ["uint256", "uint256"],
            [owner.address, 2] // key, slot
        );
        await setStorageAt(
            dai.address,
            index.toString(),
            toBytes32(bigNum(10000, 18)).toString() // bytes32 string
        );

        // Set USDC balance for owner (1000$)
        index = ethers.utils.solidityKeccak256(
            ["uint256", "uint256"],
            [owner.address, 9] // key, slot
        );

        await setStorageAt(
            usdc.address,
            index.toString(),
            toBytes32(bigNum(10000, 6)).toString() // bytes32 string
        );

    });

    describe("swap", () => {
        it("should successful swap dai to usdc", async () => {
            await dai.transfer(swapUtils.address, bigNum(10000, 18));
            await swapUtils.$swap(bigNum(10000, 18), bigNum(6500, 6),
                [dai.address, usdc.address]);
            await expect(await usdc.balanceOf(swapUtils.address)).to.be.above(bigNum(6500, 6));


        });
        it("should successful swap usdc to dai", async () => {
            await usdc.transfer(swapUtils.address, bigNum(10000, 6));
            await swapUtils.$swap(bigNum(10000, 6), bigNum(9500, 18),
                [usdc.address, dai.address]);
            await expect(await dai.balanceOf(swapUtils.address)).to.be.above(bigNum(9500, 18));

        });
    });

});