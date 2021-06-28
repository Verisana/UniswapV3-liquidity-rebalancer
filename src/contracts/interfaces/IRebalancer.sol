// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

interface IRebalancer {
    struct Position {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0;
        uint256 amount1;
        int24 tickLower;
        int24 tickUpper;
    }

    struct Totals {
        uint256 amount0;
        uint256 amount1;
    }

    struct UserState {
        Totals fee;
        Totals deposit;
        uint256 share;
        bool participateInStake;
    }

    struct Summarize {
        uint256 lastBlock;
        uint256 lastUser;
        int64 stage;
        uint256 fixedPrice;
        Totals toStake;
        uint256 shareDenominator;
        bool sellToken0;
        Totals distributedFees;
        Totals distributedDeposits;
    }

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
