// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./interfaces/IRebalancerDeployer.sol";
import "./interfaces/IRebalancer.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract Rebalancer is IRebalancer {
    address public immutable override factory;
    IUniswapV3Pool public immutable override pool;

    constructor() {
        (factory, pool) = IRebalancerDeployer(msg.sender).parameters();
    }

    function rebalancePriceRange() external override {}

    function removeLiquidityStake() external override {}

    function immediateReturnFunds() external override {}

    function collectAllFees() external override {}

    function sendClaimedFunds() external override {}

    function mergeStakes() external override {}

    function summarizeTrades() external override {}
}
