import { ethers } from "ethers";
import * as dotenv from "dotenv";

dotenv.config();

let provider: ethers.providers.Provider;
if (process.env.PROVIDER === undefined) throw `PROVIDER is undefined`;

if (process.env.PROVIDER_TYPE == "ipc") {
    provider = new ethers.providers.IpcProvider(process.env.PROVIDER);
} else if (process.env.PROVIDER_TYPE == "http") {
    provider = new ethers.providers.JsonRpcProvider(process.env.PROVIDER);
} else {
    throw `Unrecognized PROVIDER_TYPE == ${process.env.PROVIDER_TYPE}`;
}

async function* getLatestBlock(provider: ethers.providers.Provider) {
    let lastSeenBlockNumber = await provider.getBlockNumber();
    while (true) {
        const latestBlockNumber = await provider.getBlockNumber();
        if (latestBlockNumber > lastSeenBlockNumber) {
            lastSeenBlockNumber = latestBlockNumber;
            yield lastSeenBlockNumber
        }
    }
};
