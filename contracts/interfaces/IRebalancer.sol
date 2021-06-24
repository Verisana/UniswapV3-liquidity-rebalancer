// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

interface IRebalancer {
    // function factory() external view returns (address);
    // function pool() external view returns (IUniswapV3Pool);
    // function positionManager() external view returns (INonfungiblePositionManager);
    // function rebalancePriceRange() external;
    // function removeLiquidityStake() external;
    function immediateFundsReturn() external;
    // function collectAllFees() external;
    // function sendClaimedFunds() external;
    // function mergeStakes() external;
    // function summarizeTrades() external;
}
