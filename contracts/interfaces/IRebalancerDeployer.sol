// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

interface IRebalancerDeployer {
    function parameters() external view returns (
        address factory,
        IUniswapV3Pool pool
    );
}