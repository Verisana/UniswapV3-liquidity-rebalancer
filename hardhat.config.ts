import "@typechain/hardhat";
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-ethers";
import "solidity-coverage";
import "hardhat-gas-reporter";
import "hardhat-tracer";

export default {
    defaultNetwork: "hardhat",
    networks: {
        hardhat: {
            port: 8565,
            forking: {
                url: "http://127.0.0.1:8545",
                enabled: true
            },
            mining: {
                auto: true,
                interval: 5000
            }
        }
    },
    solidity: {
        compilers: [
            {
                version: "0.8.4",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 100
                    }
                }
            }
        ]
    },
    paths: {
        sources: "./src/contracts",
        tests: "./test/contracts",
        cache: "./dist/contracts/cache",
        artifacts: "./dist/contracts/artifacts"
    },
    typechain: {
        outDir: "./dist/contracts/typechain"
    }
};
