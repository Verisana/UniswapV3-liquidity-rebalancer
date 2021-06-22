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

    address public immutable factory;
    IUniswapV3Pool public immutable pool;
    uint256 public immutable shareDenominator = 1000000;
    INonfungiblePositionManager public immutable positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    uint256 public totalGasUsed = 0;
    uint256 public lastBlockSummirized = 0;

    struct Position {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0;
        uint256 amount1;
        int24 tickLower;
        int24 tickUpper;
    }

    struct Funds {
        address[] users;
        uint256 total0Amount;
        uint256 total1Amount;
        mapping(address => uint256) share;
        mapping(address => uint256) token0Amount;
        mapping(address => uint256) token1Amount;
    }

    struct Fees {
        uint256 totalToken0Fee;
        uint256 totalToken1Fee;
    }

    Fees feesIncome = Fees(0, 0);
    Funds public fundsAllocated;
    Funds public fundstoAllocate;
    address[] withdrawals;
    Position public openPosition = Position(0, 0, 0, 0, 0, 0);

    modifier validateSharesCalculation() {
        _;
    }

    modifier saveGasConsumption() {
        uint256 gasStart = gasleft();
        _;
        uint256 gasUsed = gasStart - gasleft();
        totalGasUsed += gasUsed * tx.gasprice;
    }

    constructor() {
        address poolAddress;
        (factory, poolAddress) = IRebalancerDeployer(msg.sender).parameters();
        pool = IUniswapV3Pool(poolAddress);
    }

    function rebalancePriceRange(int24 tickLowerCount, int24 tickUpperCount)
        external
        onlyOwner
    {
        if (openPosition.tokenId == 0) {
            _openNewPosition(tickLowerCount, tickUpperCount);
        } else {
            // collectFees();
            // removeLiquidityStake();
            _openNewPosition(tickLowerCount, tickUpperCount);
        }
    }

    function _openNewPosition(int24 tickLowerCount, int24 tickUpperCount)
        private
    {
        // (
        //     uint256 tokenId,
        //     uint128 liquidity,
        //     uint256 amount0,
        //     uint256 amount1
        // ) = positionManager.mint({
        //     token0: pool.token0(),
        //     token1: pool.token1(),
        //     fee: pool.fee(),
        //     tickLower: 0,
        //     tickUpper: 0,
        //     amount0Desired: 0,
        //     amount1Desired: 0,
        //     amount0Min: 0,
        //     amount1Min: 0,
        //     recipient: address(this),
        //     deadline: 0
        // });
    }

    function addNewFunds(uint256 token0Amount, uint256 token1Amount) external {
        require(
            token0Amount > 0 || token1Amount > 0,
            "Either token0Amount or token1Amount should be greater than 0"
        );

        IERC20 token0 = IERC20(pool.token0());
        require(
            token0.allowance(msg.sender, address(this)) >= token0Amount,
            "Not enough allowance of token0Amount to execute allocating"
        );

        IERC20 token1 = IERC20(pool.token1());
        require(
            token1.allowance(msg.sender, address(this)) >= token1Amount,
            "Not enough allowance of token1Amount to execute allocating"
        );
    }

    function removeLiquidityStake() external {}

    function immediateFundsReturn() external {}

    function collectFees() external {
        // positionManager.collect();
    }

    function divideFees() internal {}

    function sendClaimedFunds() external {}

    function mergeStakes() external {}

    function summarizeTrades() external {}
}
