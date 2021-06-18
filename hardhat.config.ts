import "@typechain/hardhat"
import "@nomiclabs/hardhat-waffle"
import "@nomiclabs/hardhat-ethers"

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
        version: "0.8.4"
    },
    paths: {
        sources: "./contracts",
        tests: "./test",
        cache: "./dist/contracts/cache",
        artifacts: "./dist/contracts/artifacts"
    }
}
