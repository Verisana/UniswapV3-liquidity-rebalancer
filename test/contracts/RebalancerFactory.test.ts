import { ethers } from "hardhat";
import { Signer } from "ethers";
import chai from "chai";
import { solidity } from "ethereum-waffle";
import { RebalancerFactory__factory } from "../../dist/contracts/typechain/factories/RebalancerFactory__factory";
import { RebalancerFactory } from "../../dist/contracts/typechain/RebalancerFactory";

chai.use(solidity);
const expect = chai.expect;

describe("Test RebalancerFactory contract", () => {
    let accounts: Signer[];
    let owner: Signer;
    let rebalancerFactory: RebalancerFactory;

    beforeEach(async () => {
        accounts = await ethers.getSigners();
        owner = accounts[0];

        const RebalancerFactory = (await ethers.getContractFactory(
            "RebalancerFactory"
        )) as RebalancerFactory__factory;
        rebalancerFactory = await RebalancerFactory.deploy();
    });

    it("deployment and properties", async () => {
        expect(await rebalancerFactory.owner()).to.be.equal(
            await owner.getAddress()
        );
        expect(await rebalancerFactory.uniswapV3Factory()).to.be.equal(
            "0x1F98431c8aD98523631AE4a59f267346ea31F984"
        );
        const rebalancerFee = await rebalancerFactory.rebalancerFee();
        expect(rebalancerFee.numerator).to.be.equal(0);
        expect(rebalancerFee.denominator).to.be.equal(0);
        expect(await rebalancerFactory.summarizationFrequency()).to.be.equal(
            5760
        );
    });
    it("setting new owner", async () => {
        const newOwner = accounts[1];
        const notOwner = accounts[2];

        const tryChange = rebalancerFactory.connect(notOwner).setOwner(await notOwner.getAddress())
        expect(tryChange).to.be.revertedWith("Only owner can execute this function");

        await rebalancerFactory.setOwner(await newOwner.getAddress());
        expect(await rebalancerFactory.owner()).to.be.equal(await newOwner.getAddress());
    });
    it("owner restriction operating", async () => {});

    it("setting block frequency", async () => {});
    it("setting block frequency in wrong ranges", async () => {});

    it("setting rebalancer fee", async () => {
        const expectedNumerator = 1;
        const expectedDenominator = 10;
        await rebalancerFactory.setRebalanceFee(
            expectedNumerator,
            expectedDenominator
        );
        const rebalancerFee = await rebalancerFactory.rebalancerFee();
        expect(rebalancerFee.numerator).to.be.equal(expectedNumerator);
        expect(rebalancerFee.denominator).to.be.equal(expectedDenominator);
    });
    it("setting rebalancer fee if denominator > numerator", async () => {
        const expectedNumerator = 10;
        const expectedDenominator = 1;

        const setErrorFee = rebalancerFactory.setRebalanceFee(
            expectedNumerator,
            expectedDenominator
        );
        expect(setErrorFee).to.be.revertedWith(
            "Numerator can not be >= denominator"
        );
    });

    it("creating new Rebalancer", async () => {});
});
