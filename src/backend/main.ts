import { ethers } from "ethers";
import hre from "hardhat";
import * as dotenv from "dotenv";
import { IRebalancer } from "../../dist/contracts/typechain/IRebalancer";
import { IRebalancerFactory } from "../../dist/contracts/typechain/IRebalancerFactory";
import { IUniswapV3Pool } from "../../dist/contracts/typechain/IUniswapV3Pool";
import { ISwapRouter } from "../../dist/contracts/typechain/ISwapRouter";
import { IERC20 } from "../../dist/contracts/typechain/IERC20";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

dotenv.config();

const tokens = {
    WETH: "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
    USDC: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
};

const getProvider = (): ethers.providers.Provider => {
    let provider: ethers.providers.Provider;
    if (process.env.PROVIDER === undefined) throw `PROVIDER is undefined`;

    if (process.env.PROVIDER_TYPE == "ipc") {
        provider = new ethers.providers.IpcProvider(process.env.PROVIDER);
    } else if (process.env.PROVIDER_TYPE == "http") {
        provider = new ethers.providers.JsonRpcProvider(process.env.PROVIDER);
    } else {
        throw `Unrecognized PROVIDER_TYPE == ${process.env.PROVIDER_TYPE}`;
    }
    return provider;
};

const getContracts = async (
    signer: ethers.Signer
): Promise<
    [ethers.Contract, ethers.Contract, ethers.Contract, ethers.Contract]
> => {
    let rebalancerAddress: string;
    let hardhatRebalancerFactory;

    if (process.env.NODE_ENV == "development") {
        const RebalancerFactory = await hre.ethers.getContractFactory(
            "RebalancerFactory",
            signer
        );
        hardhatRebalancerFactory = await RebalancerFactory.deploy();
        let tx = await hardhatRebalancerFactory.createRebalancer(
            tokens.WETH,
            tokens.USDC,
            3000
        );
        await hardhatRebalancerFactory.setBlockFrequencySummarization(
            ethers.BigNumber.from(50)
        );
        tx = await tx.wait();

        rebalancerAddress = tx.events[0].args.rebalancer;
    } else {
        if (process.env.REBALANCER_ADDRESS === undefined)
            throw "In production contract should be deployed. You must set contract address";
        rebalancerAddress = process.env.REBALANCER_ADDRESS;
    }
    const rebalancer = await hre.ethers.getContractAt(
        "Rebalancer",
        rebalancerAddress
    );
    hardhatRebalancerFactory = await hre.ethers.getContractAt(
        "RebalancerFactory",
        await rebalancer.factory()
    );
    const pool = await hre.ethers.getContractAt(
        "IUniswapV3Pool",
        await rebalancer.pool()
    );

    const router = await hre.ethers.getContractAt(
        "ISwapRouter",
        await rebalancer.swapRouter()
    );
    return [rebalancer, hardhatRebalancerFactory, pool, router];
};

async function* getLatestBlock(provider: ethers.providers.Provider) {
    let lastSeenBlockNumber = await provider.getBlockNumber();
    while (true) {
        const latestBlockNumber = await provider.getBlockNumber();
        if (latestBlockNumber > lastSeenBlockNumber) {
            lastSeenBlockNumber = latestBlockNumber;
            yield ethers.BigNumber.from(lastSeenBlockNumber);
        }
    }
}

const needToStartSummarization = async (
    rebalancer: IRebalancer,
    factory: IRebalancerFactory,
    provider: ethers.providers.Provider,
    lastBlock: ethers.BigNumber
): Promise<boolean> => {
    const summParams = await rebalancer.summParams();
    const frequency = await factory.summarizationFrequency();

    // (lastBlock - summParams.lastBlock) >= frequency
    // console.log(
    //     `LastBlock: ${lastBlock}. SavedBlockTime: ${summParams.lastBlock}. ` +
    //         `Freq: ${frequency}`
    // );
    if (process.env.NODE_ENV == "development") {
        // For testing purposes, when we use fork chain, block numbers are messed
        // So, we check inappropriate way
        try {
            await rebalancer.callStatic.startSummarizeTrades();
            return true;
        } catch {
            return false;
        }
    } else {
        return lastBlock.sub(summParams.lastBlock).gte(frequency);
    }
};

const summarizationInProcess = async (
    rebalancer: IRebalancer
): Promise<boolean> => {
    const summParams = await rebalancer.summParams();
    return summParams.stage.gt(0);
};

const priceInPositionRange = async (
    rebalancer: IRebalancer,
    pool: IUniswapV3Pool
): Promise<boolean> => {
    const openPosition = await rebalancer.openPosition();
    const slot0 = await pool.slot0();

    console.log("\nCheck existing positions bounds:")
    console.log(
        `Lower: ${openPosition.tickLower}. ` +
            `Tick: ${slot0.tick}. ` +
            `Upper: ${openPosition.tickUpper}`
    );
    return (
        slot0.tick >= openPosition.tickLower &&
        slot0.tick <= openPosition.tickUpper
    );
};

const calcTickRanges = (): [ethers.BigNumber, ethers.BigNumber] => {
    return [ethers.BigNumber.from(3), ethers.BigNumber.from(3)];
};

const calcRebalanceParams = (
    rebalancer: IRebalancer,
    pool: IUniswapV3Pool
): [ethers.BigNumber, ethers.BigNumber, ethers.BigNumber, ethers.BigNumber] => {
    const [tickLowerCount, tickUpperCount] = calcTickRanges();

    return [
        tickLowerCount,
        tickUpperCount,
        ethers.BigNumber.from(50),
        ethers.BigNumber.from(50)
    ];
};

const sendTransaction = async (
    func: Function,
    name: string
): Promise<boolean> => {
    try {
        const tx = await func();
        const receipt = await tx.wait();
        console.log(`Executed ${name}`);
        // console.log(receipt);
        return true;
    } catch (e) {
        console.log(e);
        return false;
    }
};

const summarizeUsersStatesTillTheEnd = async (
    rebalancer: IRebalancer
): Promise<boolean> => {
    let summParams = await rebalancer.summParams();
    do {
        let result = await sendTransaction(
            rebalancer.summarizeUsersStates,
            "summarizeUsersStates"
        );
        if (!result) return false;

        summParams = await rebalancer.summParams();
    } while (!summParams.stage.eq(0));

    return true;
};

const depositFundsToRebalancer = async (
    rebalancer: IRebalancer,
    users: SignerWithAddress[],
    amounts: ethers.BigNumber[]
) => {
    if (users.length != amounts.length)
        throw "Users and deposits must have the same length";

    for (let i = 0; i < users.length; i++) {
        await users[i].sendTransaction({ to: tokens.WETH, value: amounts[i] });
        const weth = (await hre.ethers.getContractAt(
            "IERC20",
            tokens.WETH
        )) as IERC20;
        await weth.connect(users[i]).approve(rebalancer.address, amounts[i]);
        await rebalancer
            .connect(users[i])
            .deposit(ethers.BigNumber.from(0), amounts[i]);
        const state = await rebalancer.userStates(users[i].address);
        console.log(
            `User ${i} deposited WETH: ${state.deposited.amount1.toString()}`
        );
    }
};

const removeAllUsersFromStaking = async (
    rebalancer: IRebalancer,
    users: SignerWithAddress[]
) => {
    for (let i = 0; i < users.length; i++) {
        await rebalancer.connect(users[i]).participate();
        console.log(`User ${i} requested funds withdrawing`);
    }
};

const main = async () => {
    const provider = getProvider();

    // Here we have: owner, userA, userB, userC and others are all considered traders
    const accounts = await hre.ethers.getSigners();
    const [rebalancer, factory, pool] = (await getContracts(accounts[0])) as [
        IRebalancer,
        IRebalancerFactory,
        IUniswapV3Pool
    ];
    console.log("All contracts has been initialized");
    const depositAmounts = [
        ethers.BigNumber.from("200000000000000000000"), // 200 ETH
        ethers.BigNumber.from("74000000000000000000"), // 74 ETH
        ethers.BigNumber.from("1000000000000000000") // 1 ETH
    ];
    depositFundsToRebalancer(rebalancer, accounts.slice(1, 4), depositAmounts);

    for await (const newBlockNumber of getLatestBlock(provider)) {
        console.log(`Received new block ${newBlockNumber}`);
        if (
            (await needToStartSummarization(
                rebalancer,
                factory,
                newBlockNumber
            )) ||
            (await summarizationInProcess(rebalancer))
        ) {
            console.log("Summarization time has come!");
            let summParams = await rebalancer.summParams();
            if (summParams.stage.eq(0)) {
                let result = await sendTransaction(
                    rebalancer.startSummarizeTrades,
                    "startSummarizeTrades"
                );

                // If we get error, we shouldn't continue next stage
                if (!result) continue;
            }
            await summarizeUsersStatesTillTheEnd(rebalancer);
            const inStake = await rebalancer.inStake();
            const userA = await rebalancer.userStates(accounts[1].address);
            const userB = await rebalancer.userStates(accounts[2].address);
            const userC = await rebalancer.userStates(accounts[3].address);
            summParams = await rebalancer.summParams();

            console.log(
                `Total stake. Amount0: ${inStake.amount0.toString()}. Amount1: ${inStake.amount1.toString()}`
            );
            console.log(
                `UserA share: ${userA.share.toString()}. Denominator ${summParams.shareDenominator.toString()}`
            );
            console.log(
                `UserB share: ${userB.share.toString()}. Denominator ${summParams.shareDenominator.toString()}`
            );
            console.log(
                `UserC share: ${userC.share.toString()}. Denominator ${summParams.shareDenominator.toString()}`
            );
        }

        if (await priceInPositionRange(rebalancer, pool)) {
            console.log("Price in position range");
            continue;
        } else {
            const [tickLowerCount, tickUpperCount, token0Share, token1Share] =
                calcRebalanceParams(rebalancer, pool);

            await rebalancer.rebalancePriceRange(
                tickLowerCount,
                tickUpperCount,
                token0Share,
                token1Share
            );
            // await sendTransaction(
            //     rebalancer.rebalancePriceRange.bind(
            //         tickLowerCount,
            //         tickUpperCount,
            //         token0Share,
            //         token1Share
            //     ),
            //     "rebalancePriceRange"
            // );
            const position = await rebalancer.openPosition();
            const inStake = await rebalancer.inStake();

            console.log(
                `New position opened: from ${position.tickLower.toString()} ` +
                    `to ${position.tickUpper.toString()}`
            );
            console.log(
                `Remained inStake is ${inStake.amount0.toString()} ` +
                    `and ${inStake.amount1.toString()}`
            );
        }
    }
};

main().then(() => {});
