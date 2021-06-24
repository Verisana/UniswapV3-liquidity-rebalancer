// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/finance/PaymentSplitter.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./interfaces/IRebalancerDeployer.sol";
import "./interfaces/IRebalancerFactory.sol";
import "./interfaces/IRebalancer.sol";
import "./NoDelegateCall.sol";

contract Rebalancer is IRebalancer, Ownable, NoDelegateCall {
    using SafeERC20 for IERC20;

    IRebalancerFactory public immutable factory;
    IUniswapV3Pool public immutable pool;
    IERC20 public immutable token0;
    IERC20 public immutable token1;
    bytes path01;
    bytes path10;

    INonfungiblePositionManager public immutable positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    ISwapRouter public immutable swapRouter =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    uint256 public totalGasUsed = 0;
    uint256 public lastBlockSummirized = 0;
    bool public summarizeInProccess = false;

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

    struct UserInfo {
        Totals fees;
        Totals withdrawing;
        Totals funding;
        uint256 shareInStake;
        bool withdrawRequested;
    }

    Totals public feesIncome = Totals(0, 0);
    Totals public fundsInStake;

    uint256 public lastProccessedUser = 0;
    address[] public users;
    mapping(address => UserInfo) public userInfo;
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
        address factoryAddress;
        address poolAddress;
        (factoryAddress, poolAddress) = IRebalancerDeployer(msg.sender)
        .parameters();
        factory = IRebalancerFactory(factoryAddress);

        // We are not allowed to use immutable storage variables in constructor
        IUniswapV3Pool pool_ = IUniswapV3Pool(poolAddress);
        IERC20 token0_ = IERC20(pool_.token0());
        IERC20 token1_ = IERC20(pool_.token1());

        path01 = abi.encodePacked([address(token0_), address(token1_)]);
        path10 = abi.encodePacked([address(token1_), address(token0_)]);

        pool = pool_;
        token0 = token0_;
        token1 = token1_;
    }

    function rebalancePriceRange(
        int24 tickLowerCount,
        int24 tickUpperCount,
        bool isToken1,
        uint256 tokenIn,
        uint256 tokenOutMin
    ) external onlyOwner {
        require(summarizeInProccess == false, "End summarize trades");

        if (openPosition.tokenId == 0) {
            _openNewPosition(
                tickLowerCount,
                tickUpperCount,
                isToken1,
                tokenIn,
                tokenOutMin
            );
        } else {
            _collectFees();
            _removeLiquidityStake();
            _openNewPosition(
                tickLowerCount,
                tickUpperCount,
                isToken1,
                tokenIn,
                tokenOutMin
            );
        }
    }

    function _getDeadline() private view returns (uint256) {
        return block.timestamp + 60;
    }

    function _swapTokens(
        bool isToken1,
        uint256 tokenIn,
        uint256 tokenOutMin
    ) private {
        if (isToken1) {
            fundsInStake.amount1 -= tokenIn;
            token1.safeApprove(address(swapRouter), tokenIn);
            fundsInStake.amount0 += swapRouter.exactInput(
                ISwapRouter.ExactInputParams({
                    path: path10,
                    recipient: address(this),
                    deadline: _getDeadline(),
                    amountIn: tokenIn,
                    amountOutMinimum: tokenOutMin
                })
            );
        } else {
            fundsInStake.amount0 -= tokenIn;
            token0.safeApprove(address(swapRouter), tokenIn);
            fundsInStake.amount1 += swapRouter.exactInput(
                ISwapRouter.ExactInputParams({
                    path: path01,
                    recipient: address(this),
                    deadline: _getDeadline(),
                    amountIn: tokenIn,
                    amountOutMinimum: tokenOutMin
                })
            );
        }
    }

    function _openNewPosition(
        int24 tickLowerCount,
        int24 tickUpperCount,
        bool isToken1,
        uint256 tokenIn,
        uint256 tokenOutMin
    ) private {
        (, int24 tick, , , , , ) = pool.slot0();
        int24 fulTick = tick + (tick % pool.tickSpacing());

        // Here we get lower and upper bounds for current price
        int24 tickLower = fulTick - pool.tickSpacing();
        int24 tickUpper = fulTick + pool.tickSpacing();

        tickLower -= tickLowerCount * pool.tickSpacing();
        tickUpper += tickUpperCount * pool.tickSpacing();

        _swapTokens(isToken1, tokenIn, tokenOutMin);

        (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        ) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: pool.token0(),
                token1: pool.token1(),
                fee: pool.fee(),
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: fundsInStake.amount0,
                amount1Desired: fundsInStake.amount1,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: _getDeadline()
            })
        );

        fundsInStake.amount0 -= amount0;
        fundsInStake.amount1 -= amount1;

        openPosition = Position({
            tokenId: tokenId,
            liquidity: liquidity,
            amount0: amount0,
            amount1: amount1,
            tickLower: tickLower,
            tickUpper: tickUpper
        });
    }

    function addNewFunds(uint256 token0Amount, uint256 token1Amount)
        external
        view
    {
        require(
            token0Amount > 0 || token1Amount > 0,
            "Either token0Amount or token1Amount should be greater than 0"
        );
        require(
            token0.allowance(msg.sender, address(this)) >= token0Amount,
            "Not enough allowance of token0Amount to execute allocating"
        );
        require(
            token1.allowance(msg.sender, address(this)) >= token1Amount,
            "Not enough allowance of token1Amount to execute allocating"
        );
    }

    function _removeLiquidityStake() internal {
        (uint256 amount0, uint256 amount1) = positionManager.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: openPosition.tokenId,
                liquidity: 0,
                amount0Min: 0,
                amount1Min: 0,
                deadline: _getDeadline()
            })
        );

        fundsInStake.amount0 += amount0;
        fundsInStake.amount1 += amount1;

        positionManager.burn(openPosition.tokenId);

        openPosition = Position(0, 0, 0, 0, 0, 0);
    }

    function immediateFundsReturn() external override {}

    function _collectFees() private {
        (uint256 feeAmount0, uint256 feeAmount1) = positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: openPosition.tokenId,
                recipient: address(this),
                amount0Max: 0,
                amount1Max: 0
            })
        );

        feesIncome.amount0 += feeAmount0;
        feesIncome.amount1 += feeAmount1;
    }

    function _calcShare(uint256 total, uint256 numerator)
        public
        pure
        returns (uint256)
    {
        return FullMath.mulDiv(total, numerator, factory.shareDenominator());
    }

    function _distributeServiceFees() private returns (uint256) {
        uint256 serviceFee = _calcShare(
            feesIncome.amount0,
            factory.rebalancerFee()
        );

        if (serviceFee != 0) {
            token0.safeApprove(factory.owner(), serviceFee);
            token0.safeTransfer(factory.owner(), serviceFee);
            feesIncome.amount0 -= serviceFee;
        }

        serviceFee = _calcShare(feesIncome.amount1, factory.rebalancerFee());
        if (serviceFee != 0) {
            token1.safeApprove(factory.owner(), serviceFee);
            token1.safeTransfer(factory.owner(), serviceFee);
            feesIncome.amount1 -= serviceFee;
        }
    }

    function _distributeFees() private {}

    function withdrawStake() external {}

    function startSummarizeTrades() external {
        require(
            summarizeInProccess == false,
            "Call next methods and end summarization proccess"
        );
        summarizeInProccess = true;
        _collectFees();
        _removeLiquidityStake();
        _distributeServiceFees();
    }

    function summarizeUsersStates() external {
        uint256 i = lastProccessedUser;
        uint256 initGas = gasleft();
        uint256 loopCost = 0;
        for (i; i < users.length; i++) {
            if (gasleft() < loopCost) {
                lastProccessedUser = i - 1;
                break;
            }
            address newUser = users[i];
            UserInfo memory user = userInfo[newUser];

            user.fees.amount0 += _calcShare(
                feeIncome.amount0,
                user.shareInStake
            );
            user.fees.amount1 += _calcShare(
                feeIncome.amount1,
                user.shareInStake
            );

            

            if (loopCost == 0) {
                loopCost = initGas - gasleft();
            }
        }
        lastProccessedUser = users.length - 1;
    }

    function mergeStakes() external {}

    function summarizeTrades() external {}
}
