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

describe("Test Factory contract", () => {
    it("deployment and properties", async () => {});
});
