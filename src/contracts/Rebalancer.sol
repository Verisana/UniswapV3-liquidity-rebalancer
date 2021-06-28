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

    // They both should be immutable but compiler gives an error
    bytes public path01;
    bytes public path10;

    INonfungiblePositionManager public immutable positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    ISwapRouter public immutable swapRouter =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    Totals public feesIncome = Totals({amount0: 0, amount1: 0});
    Totals public inStake = Totals({amount0: 0, amount1: 0});
    Position public openPosition =
        Position({
            tokenId: 0,
            liquidity: 0,
            amount0: 0,
            amount1: 0,
            tickLower: 0,
            tickUpper: 0
        });

    // summParams = SummarizationParams
    Summarize public summParams =
        Summarize({
            lastBlock: 0,
            lastUser: 0,
            stage: 0,
            fixedPrice: 0,
            toStake: Totals(0, 0),
            shareDenominator: 0,
            sellToken0: false,
            distributedFees: Totals(0, 0),
            distributedDeposits: Totals(0, 0)
        });

    address[] public users;
    mapping(address => bool) isInUsers;
    mapping(address => UserState) public userStates;

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

    modifier restrictIfSummStarted() {
        require(
            summParams.stage == 0,
            "Method is not allowed if summarization has been started. Wait next blocks"
        );
        _;
    }

    // Methods only for users
    function newDeposit(uint256 token0Amount, uint256 token1Amount)
        external
        restrictIfSummStarted
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

        token0.safeTransfer(address(this), token0Amount);
        token1.safeTransfer(address(this), token1Amount);

        userStates[msg.sender].deposit.amount0 += token0Amount;
        userStates[msg.sender].deposit.amount1 += token1Amount;

        if (!isInUsers[msg.sender]) {
            isInUsers[msg.sender] = true;
            users.push(msg.sender);
        }
    }

    function withdraw(bool withdrawDeposit) external restrictIfSummStarted {
        require(
            isInUsers[msg.sender],
            "You don't have deposits or never ever deposited"
        );
        UserState storage user = userStates[msg.sender];
        Totals memory transferAmount = Totals(
            user.fee.amount0,
            user.fee.amount1
        );

        user.fee.amount0 = 0;
        user.fee.amount1 = 0;

        if (withdrawDeposit) {
            transferAmount.amount0 += user.deposit.amount0;
            transferAmount.amount1 += user.deposit.amount1;
            user.deposit.amount0 = 0;
            user.deposit.amount1 = 0;
        }

        token0.safeTransfer(msg.sender, transferAmount.amount0);
        token1.safeTransfer(msg.sender, transferAmount.amount1);
    }

    function participateInStake() external restrictIfSummStarted {
        require(
            isInUsers[msg.sender],
            "You don't have deposits or never ever deposited"
        );
        userStates[msg.sender].participateInStake = !userStates[msg.sender]
        .participateInStake;
    }

    // Methods only for factory Owner
    function rebalancePriceRange(
        int24 tickLowerCount,
        int24 tickUpperCount,
        bool sellToken0,
        uint256 tokenIn,
        uint256 tokenOutMin
    ) external onlyOwner restrictIfSummStarted {
        if (openPosition.tokenId == 0) {
            _openNewPosition(
                tickLowerCount,
                tickUpperCount,
                sellToken0,
                tokenIn,
                tokenOutMin
            );
        } else {
            _collectFees();
            _removeLiquidityPosition();
            _openNewPosition(
                tickLowerCount,
                tickUpperCount,
                sellToken0,
                tokenIn,
                tokenOutMin
            );
        }
    }

    // Here we also add functionality of sending rounding errors to
    // the service owner. We expect this to be very small amounts.
    // If not, there are bugs in contract
    function deleteUsersWithoutFunds() external restrictIfSummStarted {
        // We don't know beforehand array size, so we calculate it
        uint256 counter = 0;

        

        for (uint256 i = 0; i < users.length; i++) {
            if (isUserWithoutFunds(userStates[users[i]])) {
                isInUsers[users[i]] = false;
            } else {
                counter++;
                isInUsers[users[i]] = true;
            }
        }

        // Here we populate new array. It would be better to push() in array
        // but that is not allowed oin Solidity
        address[] memory usersWithFunds = new address[](counter);

        counter = 0;
        for (uint256 i = 0; i < users.length; i++) {
            if (isInUsers[users[i]]) {
                usersWithFunds[counter] = users[i];
                counter++;
            }
        }

        users = usersWithFunds;
    }

    // Methods for everyone
    function startSummarizeTrades() external restrictIfSummStarted {
        require(
            block.number - summParams.lastBlock >=
                factory.summarizationFrequency(),
            "Wait more blocks to start summarization proccess"
        );
        summParams.stage++;
        _collectFees();
        _removeLiquidityPosition();
        _distributeServiceFees();
    }

    function summarizeUsersStates() external {
        require(
            summParams.stage == 1 || summParams.stage == 2,
            "First start summarization proccess"
        );
        if (summParams.stage == 1) {
            bool success = _accountFeesAndStake();
            if (success) {
                summParams.stage++;
                summParams.lastUser = 0;
            }
        } else if (summParams.stage == 2) {
            if (summParams.lastUser == 0) {
                _setConfigsForSecondStage();
            }

            bool success = _createNewStake();
            if (success) {
                summParams.stage = 0;
                summParams.lastUser = 0;
                summParams.lastBlock = block.number;

                // Here we supposed to get some very small rounding error amounts
                _sendRoundingErrorsToService();
            }
        }
    }

    // Internal helper methods
    function _sendRoundingErrorsToService() private {
        Totals memory balance = Totals({
            amount0: token0.balanceOf(address(this)),
            amount1: token1.balanceOf(address(this))
        });


    }

    function _swapTokens(
        bool sellToken0,
        uint256 tokenIn,
        uint256 tokenOutMin
    ) private {
        if (sellToken0) {
            inStake.amount0 -= tokenIn;
            token0.safeApprove(address(swapRouter), tokenIn);
            inStake.amount1 += swapRouter.exactInput(
                ISwapRouter.ExactInputParams({
                    path: path01,
                    recipient: address(this),
                    deadline: getDeadline(),
                    amountIn: tokenIn,
                    amountOutMinimum: tokenOutMin
                })
            );
        } else {
            inStake.amount1 -= tokenIn;
            token1.safeApprove(address(swapRouter), tokenIn);
            inStake.amount0 += swapRouter.exactInput(
                ISwapRouter.ExactInputParams({
                    path: path10,
                    recipient: address(this),
                    deadline: getDeadline(),
                    amountIn: tokenIn,
                    amountOutMinimum: tokenOutMin
                })
            );
        }
    }

    function _openNewPosition(
        int24 tickLowerCount,
        int24 tickUpperCount,
        bool sellToken0,
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

        _swapTokens(sellToken0, tokenIn, tokenOutMin);

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
                amount0Desired: inStake.amount0,
                amount1Desired: inStake.amount1,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: getDeadline()
            })
        );

        inStake.amount0 -= amount0;
        inStake.amount1 -= amount1;

        openPosition = Position({
            tokenId: tokenId,
            liquidity: liquidity,
            amount0: amount0,
            amount1: amount1,
            tickLower: tickLower,
            tickUpper: tickUpper
        });
    }

    function _removeLiquidityPosition() private {
        if (openPosition.tokenId != 0) {
            (uint256 amount0, uint256 amount1) = positionManager.decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: openPosition.tokenId,
                    liquidity: 0,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: getDeadline()
                })
            );

            inStake.amount0 += amount0;
            inStake.amount1 += amount1;

            positionManager.burn(openPosition.tokenId);

            openPosition = Position(0, 0, 0, 0, 0, 0);
        }
    }

    function _collectFees() private {
        if (openPosition.tokenId != 0) {
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
    }

    function _distributeServiceFees() private {
        (uint256 numerator, uint256 denominator) = factory.rebalancerFee();

        uint256 serviceFee = calcShare(
            feesIncome.amount0,
            numerator,
            denominator
        );

        if (serviceFee != 0) {
            token0.safeApprove(factory.owner(), serviceFee);
            token0.safeTransfer(factory.owner(), serviceFee);
            feesIncome.amount0 -= serviceFee;
        }

        serviceFee = calcShare(feesIncome.amount1, numerator, denominator);
        if (serviceFee != 0) {
            token1.safeApprove(factory.owner(), serviceFee);
            token1.safeTransfer(factory.owner(), serviceFee);
            feesIncome.amount1 -= serviceFee;
        }
    }

    function _accountFeesAndStake() private returns (bool) {
        uint256 i = summParams.lastUser;
        uint256 initGas = gasleft();
        uint256 loopCost = 0;

        for (i; i < users.length; i++) {
            if (gasleft() < loopCost) {
                summParams.lastUser = i;
                return false;
            }
            UserState storage user = userStates[users[i]];

            user.fee.amount0 += calcShare(
                feesIncome.amount0,
                user.share,
                summParams.shareDenominator
            );
            user.fee.amount1 += calcShare(
                feesIncome.amount1,
                user.share,
                summParams.shareDenominator
            );

            user.deposit.amount0 += calcShare(
                inStake.amount0,
                user.share,
                summParams.shareDenominator
            );

            user.deposit.amount1 += calcShare(
                inStake.amount1,
                user.share,
                summParams.shareDenominator
            );

            user.share = 0;

            if (user.participateInStake) {
                summParams.toStake.amount0 += user.deposit.amount0;
                summParams.toStake.amount1 += user.deposit.amount1;
            }

            if (loopCost == 0) {
                loopCost = initGas - gasleft();
            }
        }

        feesIncome.amount0 = 0;
        feesIncome.amount1 = 0;

        inStake.amount0 = summParams.toStake.amount0;
        inStake.amount1 = summParams.toStake.amount1;

        summParams.toStake.amount0 = 0;
        summParams.toStake.amount1 = 0;

        return true;
    }

    function _createNewStake() private returns (bool) {
        uint256 i = summParams.lastUser;
        uint256 initGas = gasleft();
        uint256 loopCost = 0;

        for (i; i < users.length; i++) {
            if (gasleft() < loopCost) {
                summParams.lastUser = i;
                return false;
            }

            UserState memory user = userStates[users[i]];

            // If user requested withdrawal, there stake will be set to
            // zero by default
            uint256 converted = summParams.sellToken0
                ? user.deposit.amount0 * summParams.fixedPrice
                : user.deposit.amount1 * summParams.fixedPrice;

            user.share = summParams.sellToken0
                ? user.deposit.amount1 + converted
                : user.deposit.amount0 + converted;

            user.deposit.amount0 = 0;
            user.deposit.amount1 = 0;

            if (loopCost == 0) {
                loopCost = initGas - gasleft();
            }
        }

        return true;
    }

    // Here we:
    // 1. Swap all tokens into one asset.
    // 2. Calculate exchange price and set it into fixedPrice
    // 3. Set sellToken0 property
    // 4. Set shareDenominator property
    function _setConfigsForSecondStage() private {
        uint256 initAmount0 = inStake.amount0;
        uint256 initAmount1 = inStake.amount1;
        bool sellToken0;

        // We swap all tokens into one asset and do it to the side of
        // smaller amount in order to counter-balance price movement
        if (inStake.amount0 > inStake.amount1) {
            sellToken0 = true;
            _swapTokens(sellToken0, inStake.amount0, 0);
            summParams.fixedPrice =
                (inStake.amount1 - initAmount1) /
                initAmount0;
            summParams.shareDenominator = inStake.amount1;
        } else {
            sellToken0 = false;
            _swapTokens(sellToken0, inStake.amount1, 0);
            summParams.fixedPrice =
                (inStake.amount0 - initAmount0) /
                initAmount1;
            summParams.shareDenominator = inStake.amount0;
        }

        summParams.sellToken0 = sellToken0;
        summParams.shareDenominator = sellToken0
            ? inStake.amount1
            : inStake.amount0;
    }

    // Helper view methods for everyone
    function getDeadline() private view returns (uint256) {
        return block.timestamp + 60;
    }

    function calcShare(
        uint256 total,
        uint256 numerator,
        uint256 denominator
    ) public pure returns (uint256) {
        return FullMath.mulDiv(total, numerator, denominator);
    }

    function isUserWithoutFunds(UserState memory user)
        public
        pure
        returns (bool)
    {
        return
            user.share == 0 &&
            user.deposit.amount0 == 0 &&
            user.deposit.amount1 == 0 &&
            user.fee.amount1 == 0 &&
            user.fee.amount1 == 0;
    }
}
