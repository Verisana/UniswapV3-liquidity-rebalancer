// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "@uniswap/v3-core/contracts/interfaces/UniswapV3Pool.sol";

// This is the main building block for smart contracts.
interface IRebalancerFactory {


    event ownerChange(address indexed oldOwner, address indexed newOwner);
    event rebalancerCreated(
        address indexed token0,
        address indexed token1,
        uint24 indexed fee,
        int24 tickSpacing,
        address pool
    );
    function owner() external view returns (address);
    function getRebalancer(UniswapV3Pool pool);
}
