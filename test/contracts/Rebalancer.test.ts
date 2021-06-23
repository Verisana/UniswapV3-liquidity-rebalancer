import expect from "chai";
import { ethers } from "hardhat";

export const tokens = {
    WETH: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    USDC: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
    USDT: "0xdAC17F958D2ee523a2206206994597C13D831ec7"
}

describe("Test Rebalancer contract", () => {
    it("deployment and properties", async () => {
        const [owner] = await ethers.getSigners();

        const RebalancerFactory = await ethers.getContractFactory("RebalancerFactory");

        let hardhatRebalancerFactory = await RebalancerFactory.deploy();
        hardhatRebalancerFactory = hardhatRebalancerFactory.connect(owner);
        // let tx = await hardhatRebalancerFactory.createRebalancer(tokens.WETH, tokens.USDC, 3000);
        let tx = await hardhatRebalancerFactory.createRebalancer(tokens.WETH, tokens.USDT, 3000);
        tx = await tx.wait();
        const rebalancerAddress = tx.events[1].args.rebalancer;
        const rebalancer = await ethers.getContractAt("Rebalancer", rebalancerAddress);
        const poolAddress = await rebalancer.pool();
        const pool = await ethers.getContractAt("IUniswapV3Pool", poolAddress)
        const tickSpacing = await pool.tickSpacing()
        const liquidity = await pool.liquidity()

        const slot0 = await pool.slot0();
        const token0 = await pool.token0();
        const token1 = await pool.token1();
        const tick = await pool.ticks(slot0.tick);
        const tickbm = await pool.ticks(slot0.tick-slot0.tick+1);

        const reserve0 = liquidity / (slot0.sqrtPriceX96 / (2 ** 96))
        const reserve1 = liquidity * (slot0.sqrtPriceX96 / (2 ** 96))

        console.log(1);
    });
});
