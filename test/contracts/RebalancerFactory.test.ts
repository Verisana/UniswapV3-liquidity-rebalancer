import { ethers } from "hardhat";
import { Signer } from "ethers";
import chai from "chai";
import { solidity } from "ethereum-waffle";
import { RebalancerFactory__factory } from "../../typechain/factories/RebalancerFactory__factory";
import { RebalancerFactory } from "../../typechain/RebalancerFactory";

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

});
