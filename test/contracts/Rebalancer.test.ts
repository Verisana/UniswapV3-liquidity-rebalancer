import expect from "chai";
import { ethers } from "hardhat";
import { IRebalancer } from "../../dist/contracts/typechain/IRebalancer";
import { tokens } from "../fixtures";

describe("Test Rebalancer contract", () => {
    it("sandbox for fast checking", async () => {
        const [owner] = await ethers.getSigners();

        const RebalancerFactory = await ethers.getContractFactory(
            "RebalancerFactory"
        );

        let hardhatRebalancerFactory = await RebalancerFactory.deploy();
        hardhatRebalancerFactory = hardhatRebalancerFactory.connect(owner);
        // let tx = await hardhatRebalancerFactory.createRebalancer(tokens.WETH, tokens.USDC, 3000);
        let tx = await hardhatRebalancerFactory.createRebalancer(
            tokens.WETH,
            tokens.USDT,
            3000
        );
        tx = await tx.wait();
        const rebalancerAddress = tx.events[0].args.rebalancer;
        const rebalancer = (await ethers.getContractAt(
            "Rebalancer",
            rebalancerAddress
        )) as IRebalancer;

        const poolAddress = await rebalancer.pool();
        const pool = await ethers.getContractAt("IUniswapV3Pool", poolAddress);
        const tickSpacing = await pool.tickSpacing();
        const liquidity = await pool.liquidity();

        const slot0 = await pool.slot0();
        const token0 = await pool.token0();
        const token1 = await pool.token1();
        const tick = await pool.ticks(slot0.tick);
        const tickbm = await pool.ticks(slot0.tick - slot0.tick + 1);

        const reserve0 = liquidity / (slot0.sqrtPriceX96 / 2 ** 96);
        const reserve1 = liquidity * (slot0.sqrtPriceX96 / 2 ** 96);
    });
});
