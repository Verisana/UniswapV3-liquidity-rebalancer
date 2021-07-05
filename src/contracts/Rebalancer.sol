// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/finance/PaymentSplitter.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./interfaces/IRebalancerDeployer.sol";
import "./interfaces/IRebalancerFactory.sol";
import "./interfaces/IRebalancer.sol";

import "hardhat/console.sol";

contract Rebalancer is IRebalancer, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IRebalancerFactory public immutable override factory;
    IUniswapV3Pool public immutable override pool;
    IERC20 public immutable override token0;
    IERC20 public immutable override token1;

    INonfungiblePositionManager public immutable override positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    ISwapRouter public immutable override swapRouter =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    Totals public override feesIncome = Totals({amount0: 0, amount1: 0});
    Totals public override inStake = Totals({amount0: 0, amount1: 0});
    Position public override openPosition =
        Position({
            tokenId: 0,
            liquidity: 0,
            amount0: 0,
            amount1: 0,
            tickLower: 0,
            tickUpper: 0
        });

    // summParams = SummarizationParams
    Summarize public override summParams =
        Summarize({
            lastBlock: 0,
            lastUser: 0,
            stage: 0,
            fixedPrice: Fraction(0, 0),
            toStake: Totals(0, 0),
            shareDenominator: 0,
            sellToken0: false,
            distributedFees: Totals(0, 0),
            distributedDeposits: Totals(0, 0)
        });

    address[] public _users;
    mapping(address => bool) public override isInUsers;
    mapping(address => UserState) public override userStates;

    constructor() {
        address factoryAddress;
        address poolAddress;
        (factoryAddress, poolAddress) = IRebalancerDeployer(msg.sender)
        .parameters();
        factory = IRebalancerFactory(factoryAddress);

        // We are not allowed to use immutable storage variables in constructor
        IUniswapV3Pool pool_ = IUniswapV3Pool(poolAddress);
        pool = pool_;

        token0 = IERC20(pool_.token0());
        token1 = IERC20(pool_.token1());
    }

    modifier restrictIfSummStarted() {
        require(
            summParams.stage == 0,
            "Restricted while Summirizing in process"
        );
        _;
    }

    modifier onlyFactoryOwner() {
        require(msg.sender == factory.owner());
        _;
    }

    // Methods only for users
    function deposit(uint256 token0Amount, uint256 token1Amount)
        external
        override
        nonReentrant
        restrictIfSummStarted
    {
        require(
            token0Amount > 0 || token1Amount > 0,
            "Either of token amounts must be > 0"
        );
        require(
            token0.allowance(msg.sender, address(this)) >= token0Amount,
            "token0 allowance < token0Amount"
        );
        require(
            token1.allowance(msg.sender, address(this)) >= token1Amount,
            "token1 allowance < token1Amount"
        );

        if (token0Amount > 0)
            token0.safeTransferFrom(msg.sender, address(this), token0Amount);
        if (token1Amount > 0)
            token1.safeTransferFrom(msg.sender, address(this), token1Amount);

        userStates[msg.sender].deposited.amount0 += token0Amount;
        userStates[msg.sender].deposited.amount1 += token1Amount;
        userStates[msg.sender].participateInStake = true;

        emit UserDeposited(
            msg.sender,
            token0Amount,
            token1Amount,
            userStates[msg.sender]
        );

        if (!isInUsers[msg.sender]) {
            isInUsers[msg.sender] = true;
            _users.push(msg.sender);
            emit UserCreated(msg.sender);
        }
    }

    function withdraw(bool withdrawDeposit)
        external
        override
        nonReentrant
        restrictIfSummStarted
    {
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
            transferAmount.amount0 += user.deposited.amount0;
            transferAmount.amount1 += user.deposited.amount1;
            user.deposited.amount0 = 0;
            user.deposited.amount1 = 0;
        }

        if (transferAmount.amount0 > 0)
            token0.safeTransfer(msg.sender, transferAmount.amount0);
        if (transferAmount.amount1 > 0)
            token1.safeTransfer(msg.sender, transferAmount.amount1);

        emit UserWithdrawn(msg.sender, withdrawDeposit, transferAmount, user);
    }

    function participate()
        external
        override
        nonReentrant
        restrictIfSummStarted
    {
        require(
            isInUsers[msg.sender],
            "You don't have deposits or never ever deposited"
        );
        userStates[msg.sender].participateInStake = !userStates[msg.sender]
        .participateInStake;
        emit UserChangedStakeParticipation(
            msg.sender,
            userStates[msg.sender].participateInStake,
            userStates[msg.sender]
        );
    }

    // Methods only for factory Owner (backend)
    function rebalancePriceRange(
        int24 tickLowerCount,
        int24 tickUpperCount,
        uint256 token0Share,
        uint256 token1Share
    ) external override onlyFactoryOwner nonReentrant restrictIfSummStarted {
        require(
            inStake.amount0 > 0 || inStake.amount1 > 0,
            "Stake is empty. No users want to participate in staking"
        );

        if (openPosition.tokenId == 0) {
            _openNewPosition(
                tickLowerCount,
                tickUpperCount,
                token0Share,
                token1Share
            );
        } else {
            _collectFees();
            _removeLiquidityPosition();
            _openNewPosition(
                tickLowerCount,
                tickUpperCount,
                token0Share,
                token1Share
            );
        }
        emit PriceRebalanced(
            tickLowerCount,
            tickUpperCount,
            token0Share,
            token1Share,
            inStake,
            feesIncome
        );
    }

    // Here we also add functionality of sending unaccounted tokens to
    // the service owners. This helps to receive stuck funds, if ever appear.
    // I know, this is not good to have sideffects, but array iterating is very expensive
    // on Ethereum, so I decided to unite both operations here
    function deleteUsersWithoutFunds()
        external
        override
        onlyFactoryOwner
        nonReentrant
        restrictIfSummStarted
    {
        // We don't know beforehand array size, so we calculate it
        uint256 counter = 0;

        require(openPosition.tokenId != 0, "Position must be opened");

        Totals memory realBalance = Totals({
            amount0: token0.balanceOf(address(this)),
            amount1: token1.balanceOf(address(this))
        });

        Totals memory calcBalance = Totals(
            inStake.amount0 + feesIncome.amount0,
            inStake.amount1 + feesIncome.amount1
        );

        for (uint256 i = 0; i < _users.length; i++) {
            calcBalance.amount0 +=
                userStates[_users[i]].fee.amount0 +
                userStates[_users[i]].deposited.amount0;
            calcBalance.amount1 +=
                userStates[_users[i]].fee.amount1 +
                userStates[_users[i]].deposited.amount1;

            if (isUserWithoutFunds(userStates[_users[i]])) {
                isInUsers[_users[i]] = false;
            } else {
                counter++;
                isInUsers[_users[i]] = true;
            }
        }

        require(
            calcBalance.amount0 == realBalance.amount0 &&
                calcBalance.amount1 == realBalance.amount1,
            "You haven't accounted some funds movements"
        );

        _sendDiffToService(calcBalance, realBalance);

        // Here we populate new array. It would be better to push() in array
        // but that is not allowed in Solidity
        address[] memory usersWithFunds = new address[](counter);

        counter = 0;
        for (uint256 i = 0; i < _users.length; i++) {
            if (isInUsers[_users[i]]) {
                usersWithFunds[counter] = _users[i];
                counter++;
            }
        }

        emit UsersArrayReduced(_users.length, usersWithFunds.length);
        _users = usersWithFunds;
    }

    // Methods for everyone
    function startSummarizeTrades()
        external
        override
        nonReentrant
        restrictIfSummStarted
    {
        require(
            block.number - summParams.lastBlock >=
                factory.summarizationFrequency(),
            "Wait more to start summarization"
        );
        summParams.stage++;
        _collectFees();
        _removeLiquidityPosition();
        _distributeServiceFees();
        emit TradeSummarizationStarted(
            msg.sender,
            summParams.stage,
            block.number
        );
    }

    function summarizeUsersStates() external override nonReentrant {
        require(
            summParams.stage == 1 || summParams.stage == 2,
            "First start summarization"
        );
        emit StatesSummarizing(msg.sender, summParams, block.number);
        if (summParams.stage == 1) {
            bool success = _accountFeesAndStake();

            if (success) {
                summParams.stage++;
                summParams.lastUser = 0;
            }
        }
        if (summParams.stage == 2) {
            if (summParams.lastUser == 0) {
                _setConfigsForSecondStage();
            }
            bool success = _createNewStake();

            if (success) {
                summParams.stage = 0;
                summParams.lastUser = 0;
                summParams.lastBlock = inStake.amount0 > 0 ||
                    inStake.amount0 > 0
                    ? block.number
                    : 0;
            }
        }
    }

    // Helper view methods for everyone
    function users() external view override returns (address[] memory) {
        return _users;
    }

    function getDeadline() public view override returns (uint256) {
        return block.timestamp + 60;
    }

    function calcShare(
        uint256 total,
        uint256 numerator,
        uint256 denominator
    ) public pure override returns (uint256) {
        return
            denominator == 0
                ? 0
                : FullMath.mulDiv(total, numerator, denominator);
    }

    function isUserWithoutFunds(UserState memory user)
        public
        pure
        override
        returns (bool)
    {
        return
            user.share == 0 &&
            user.deposited.amount0 == 0 &&
            user.deposited.amount1 == 0 &&
            user.fee.amount1 == 0 &&
            user.fee.amount1 == 0;
    }

    // Internal helper methods
    function _sendDiffToService(
        Totals memory calcBalance,
        Totals memory realBalance
    ) private {
        require(
            realBalance.amount0 >= calcBalance.amount0 &&
                realBalance.amount1 >= calcBalance.amount1,
            "You must never owe more tokens, than you have"
        );

        emit BalanceDiffSentToService(realBalance, calcBalance);

        if (realBalance.amount0 - calcBalance.amount0 > 0)
            token0.safeTransfer(
                factory.owner(),
                realBalance.amount0 - calcBalance.amount0
            );
        if (realBalance.amount1 - calcBalance.amount1 > 0)
            token1.safeTransfer(
                factory.owner(),
                realBalance.amount1 - calcBalance.amount1
            );
    }

    // This approach is really awfull. Not gas efficient at all.
    // But it works and should be optimized when deploy to production
    function _changeTokensRatio(uint256 token0Share, uint256 token1Share)
        private
    {
        require(token0Share + token1Share == 100, "tokenShare sum != 100");

        // First, we make sure, that all funds located in one sided token
        // It should be guaranteed by the fact, that we rebalance only when
        // the price fall of our range. But in other cases, we still need
        // to do this
        uint256 toSell;
        if (inStake.amount0 > inStake.amount1) {
            inStake.amount0 += _swapTokens(token1, token0, inStake.amount1);
            inStake.amount1 = 0;

            toSell = calcShare(inStake.amount0, token1Share, 100);
            inStake.amount1 += _swapTokens(token0, token1, toSell);
            inStake.amount0 -= toSell;
        } else {
            inStake.amount1 += _swapTokens(token0, token1, inStake.amount0);
            inStake.amount0 = 0;

            toSell = calcShare(inStake.amount1, token0Share, 100);
            inStake.amount0 += _swapTokens(token1, token0, toSell);
            inStake.amount1 -= toSell;
        }
        emit TokensRationChanged(token0Share, token1Share, toSell, inStake);
    }

    function _swapTokens(
        IERC20 sellToken,
        IERC20 buyToken,
        uint256 tokenInAmount
    ) private returns (uint256 tokenOutAmount) {
        if (tokenInAmount == 0) return 0;

        sellToken.safeApprove(address(swapRouter), tokenInAmount);

        tokenOutAmount = swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(sellToken),
                tokenOut: address(buyToken),
                fee: pool.fee(),
                recipient: address(this),
                deadline: getDeadline(),
                amountIn: tokenInAmount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        emit TokensSwapped(sellToken, buyToken, tokenInAmount, tokenOutAmount);
    }

    function _openNewPosition(
        int24 tickLowerCount,
        int24 tickUpperCount,
        uint256 token0Share,
        uint256 token1Share
    ) private {
        (, int24 tick, , , , , ) = pool.slot0();
        int24 fullTick = tick - (tick % pool.tickSpacing());

        // Here we get lower and upper bounds for current price
        int24 tickLower = fullTick - pool.tickSpacing();
        int24 tickUpper = fullTick + pool.tickSpacing();

        tickLower -= tickLowerCount * pool.tickSpacing();
        tickUpper += tickUpperCount * pool.tickSpacing();

        console.logInt(pool.tickSpacing());
        console.logInt(tickLower);
        console.logInt(tickUpper);

        _changeTokensRatio(token0Share, token1Share);

        console.log("Before minting");
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
        console.log("After minting");

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
        emit NewPositionOpened(openPosition, inStake);
    }

    function _removeLiquidityPosition() private {
        if (openPosition.tokenId != 0) {
            (uint256 amount0, uint256 amount1) = positionManager
            .decreaseLiquidity(
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
            emit PositionClosed(amount0, amount1, inStake);
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

            emit FeesColected(feeAmount0, feeAmount1, feesIncome);
        }
    }

    function _distributeServiceFees() private {
        (uint256 numerator, uint256 denominator) = factory.rebalancerFee();
        uint256 serviceFee0;
        uint256 serviceFee1;

        serviceFee0 = calcShare(feesIncome.amount0, numerator, denominator);
        if (serviceFee0 != 0) {
            token0.safeTransfer(factory.owner(), serviceFee0);
            feesIncome.amount0 -= serviceFee0;
        }

        serviceFee1 = calcShare(feesIncome.amount1, numerator, denominator);
        if (serviceFee1 != 0) {
            token1.safeTransfer(factory.owner(), serviceFee1);
            feesIncome.amount1 -= serviceFee1;
        }
        emit SereviceFeeDistributed(serviceFee0, serviceFee1, feesIncome);
    }

    function _accountFeesAndStake() private returns (bool) {
        uint256 i = summParams.lastUser;
        uint256 initGas = gasleft();
        uint256 loopCost = 0;

        for (i; i < _users.length; i++) {
            if (gasleft() < loopCost) {
                summParams.lastUser = i;
                return false;
            }
            UserState storage user = userStates[_users[i]];

            Totals memory userFee = Totals(0, 0);
            Totals memory userDeposit = Totals(0, 0);

            userFee.amount0 += calcShare(
                feesIncome.amount0,
                user.share,
                summParams.shareDenominator
            );
            userFee.amount1 += calcShare(
                feesIncome.amount1,
                user.share,
                summParams.shareDenominator
            );

            userDeposit.amount0 += calcShare(
                inStake.amount0,
                user.share,
                summParams.shareDenominator
            );

            userDeposit.amount1 += calcShare(
                inStake.amount1,
                user.share,
                summParams.shareDenominator
            );

            user.fee.amount0 += userFee.amount0;
            user.fee.amount1 += userFee.amount1;
            user.deposited.amount0 += userDeposit.amount0;
            user.deposited.amount1 += userDeposit.amount1;

            summParams.distributedFees.amount0 += userFee.amount0;
            summParams.distributedFees.amount1 += userFee.amount1;
            summParams.distributedDeposits.amount0 += userDeposit.amount0;
            summParams.distributedDeposits.amount1 += userDeposit.amount1;

            user.share = 0;

            if (user.participateInStake) {
                summParams.toStake.amount0 += user.deposited.amount0;
                summParams.toStake.amount1 += user.deposited.amount1;
            }

            if (loopCost == 0) {
                loopCost = initGas - gasleft();
            }
        }

        feesIncome.amount0 -= summParams.distributedFees.amount0;
        feesIncome.amount1 -= summParams.distributedFees.amount1;
        inStake.amount0 -= summParams.distributedDeposits.amount0;
        inStake.amount1 -= summParams.distributedDeposits.amount1;

        // Expect very small amounts, occuring because of rounding errors
        Totals memory remains = Totals(
            feesIncome.amount0 + inStake.amount0,
            feesIncome.amount1 + inStake.amount1
        );

        if (remains.amount0 > 0)
            token0.safeTransfer(factory.owner(), remains.amount0);
        if (remains.amount1 > 0)
            token1.safeTransfer(factory.owner(), remains.amount1);

        feesIncome.amount0 = 0;
        feesIncome.amount1 = 0;

        inStake.amount0 = summParams.toStake.amount0;
        inStake.amount1 = summParams.toStake.amount1;

        summParams.toStake.amount0 = 0;
        summParams.toStake.amount1 = 0;

        emit DoneAccountingFeesAndStake(loopCost, inStake, summParams);

        summParams.distributedFees.amount0 = 0;
        summParams.distributedFees.amount1 = 0;
        summParams.distributedDeposits.amount0 = 0;
        summParams.distributedDeposits.amount1 = 0;

        return true;
    }

    function _createNewStake() private returns (bool) {
        uint256 i = summParams.lastUser;
        uint256 initGas = gasleft();
        uint256 loopCost = 0;

        for (i; i < _users.length; i++) {
            if (gasleft() < loopCost) {
                summParams.lastUser = i;
                return false;
            }

            UserState storage user = userStates[_users[i]];
            if (user.participateInStake) {
                uint256 converted = summParams.sellToken0
                    ? calcShare(
                        user.deposited.amount0,
                        summParams.fixedPrice.numerator,
                        summParams.fixedPrice.denominator
                    )
                    : calcShare(
                        user.deposited.amount1,
                        summParams.fixedPrice.numerator,
                        summParams.fixedPrice.denominator
                    );

                user.share = summParams.sellToken0
                    ? user.deposited.amount1 + converted
                    : user.deposited.amount0 + converted;

                user.deposited.amount0 = 0;
                user.deposited.amount1 = 0;
            }

            if (loopCost == 0) {
                loopCost = initGas - gasleft();
            }
        }
        emit DoneCreatingNewStakes(loopCost, inStake, summParams);
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

        // We swap all tokens into one asset and do it to the side of
        // smaller amount in order to counter-balance price movement
        if (inStake.amount0 > inStake.amount1) {
            summParams.sellToken0 = true;
            if (inStake.amount0 > 0) {
                _changeTokensRatio(0, 100);
            }

            if (initAmount0 > 0) {
                summParams.fixedPrice = Fraction(
                    inStake.amount1 - initAmount1,
                    initAmount0
                );
                summParams.shareDenominator = inStake.amount1;
            }
        } else {
            summParams.sellToken0 = false;
            if (inStake.amount1 > 0) {
                _changeTokensRatio(100, 0);
            }

            if (initAmount1 > 0) {
                summParams.fixedPrice = Fraction(
                    inStake.amount0 - initAmount0,
                    initAmount1
                );
                summParams.shareDenominator = inStake.amount0;
            }
        }
        emit SettedSummarizationConfigs(summParams);
    }
}
