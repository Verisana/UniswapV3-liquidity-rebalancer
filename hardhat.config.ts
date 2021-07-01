import "@typechain/hardhat";
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-ethers";
import "solidity-coverage";
import "hardhat-gas-reporter";
import "hardhat-abi-exporter";
import "hardhat-tracer";

export default {
    defaultNetwork: "hardhat",
    networks: {
        hardhat: {
            hardfork: "berlin",
            forking: {
                url: "http://127.0.0.1:8545",
                // blockNumber: 12372895,
                enabled: true
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
        tests: "./test",
        cache: "./dist/contracts/cache",
        artifacts: "./dist/contracts/artifacts"
    }
};
