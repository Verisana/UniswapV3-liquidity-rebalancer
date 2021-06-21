// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/finance/PaymentSplitter.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "./interfaces/IRebalancerDeployer.sol";
import "./interfaces/IRebalancer.sol";
import "./NoDelegateCall.sol";

contract Rebalancer is Ownable, NoDelegateCall {
    using SafeERC20 for IERC20;

    address public immutable override factory;
    IUniswapV3Pool public immutable override pool;
    uint256 public immutable override shareDenominator = 1000000;
    INonfungiblePositionManager public immutable override positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    uint public override totalGasUsed = 0;

    struct NFTPosition {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0;
        uint256 amount1;
        int24 tickLower;
        int24 tickUpper;
    }

    struct FundsAllocated {
        mapping(address => uint256) share;
        address[] users;
    }

    struct FundsToAllocate {
        mapping(address => uint256) token0Amount;
        mapping(address => uint256) token1Amount;
        uint256 total0Amount;
        uint256 total1Amount;
        address[] users;
    }

    struct FundsToRefund {
        address[] users;
    }

    struct AccountedFees {
        uint256 totalToken0Fee;
        uint256 totalToken1Fee;
    }

    AccountedFees accountedFees = AccountedFees(0, 0);
    NFTPosition public override position = NFTPosition(0, 0, 0, 0, 0, 0);

    modifier validateSharesCalculation() {
        _;
    }

    modifier saveGasConsumption() {
        uint gasStart = gasleft();
        _;
        uint gasUsed = gasStart - gasleft();
        totalGasUsed += gasUsed * tx.gasprice;
    }

    constructor() {
        address poolAddress;
        (factory, poolAddress) = IRebalancerDeployer(msg.sender).parameters();
        pool = IUniswapV3Pool(poolAddress);
    }

    function rebalancePriceRange(int24 tickLowerCount, int24 tickUpperCount)
        external
        override
        onlyOwner
    {
        if (position.tokenId == 0) {
            openNewPosition(tickLowerCount, tickUpperCount);
        } else {
            collectFees();
            removeLiquidityStake();
            openNewPosition(tickLowerCount, tickUpperCount);
        }
    }

    function allocateNewFunds(uint256 token0Amount, uint256 token1Amount)
        external
        override
    {
        require(
            token0Amount > 0 || token1Amount > 0,
            "Either token0Amount or token1Amount should be greater than 0"
        );

        IERC20 token0 = IERC20(pool.token0);
        require(
            token0.allowance(msg.sender, address(this)) >= token0Amount,
            "Not enough allowance of token0Amount to execute allocating"
        );

        IERC20 token1 = IERC20(pool.token1);
        require(
            token1.allowance(msg.sender, address(this)) >= token1Amount,
            "Not enough allowance of token1Amount to execute allocating"
        );
    }

    function removeLiquidityStake() external override {}

    function immediateFundsReturn() external override {}

    function collectFees() external override {
        positionManager.collect();
    }

    function divideFees() internal override {}

    function sendClaimedFunds() external override {}

    function mergeStakes() external override {}

    function summarizeTrades() external override {}
}
