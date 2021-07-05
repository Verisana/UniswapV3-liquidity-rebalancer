// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "./IRebalancerFactory.sol";

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

    struct Fraction {
        uint256 numerator;
        uint256 denominator;
    }

    struct UserState {
        Totals fee;
        Totals deposited;
        uint256 share;
        bool participateInStake;
    }

    struct Summarize {
        uint256 lastBlock;
        uint256 lastUser;
        int64 stage;
        Fraction fixedPrice;
        Totals toStake;
        uint256 shareDenominator;
        bool sellToken0;
        Totals distributedFees;
        Totals distributedDeposits;
    }

    event UserDeposited(
        address sender,
        uint256 deposit0Amount,
        uint256 deposit1Amount,
        UserState userState
    );
    event UserCreated(address sender);
    event UserWithdrawn(
        address sender,
        bool isWithdrawingDeposit,
        Totals withdrawn,
        UserState userState
    );
    event UserChangedStakeParticipation(
        address sender,
        bool newState,
        UserState user
    );
    event PriceRebalanced(
        int24 tickLowerCount,
        int24 tickUpperCount,
        uint256 token0Share,
        uint256 token1Share,
        Totals inStake,
        Totals feesIncome
    );

    event UsersArrayReduced(uint256 oldUsersCount, uint256 newUsersCount);
    event TradeSummarizationStarted(
        address sender,
        int64 status,
        uint256 startBlock
    );
    event StatesSummarizing(
        address sender,
        Summarize summParams,
        uint256 blockNumber
    );
    event BalanceDiffSentToService(Totals realBalance, Totals calcBalance);
    event TokensRationChanged(
        uint256 token0Share,
        uint256 token1Share,
        uint256 toSell,
        Totals inStake
    );
    event TokensSwapped(
        IERC20 sellToken,
        IERC20 buyToken,
        uint256 tokenIn,
        uint256 tokenOut
    );
    event NewPositionOpened(Position openPosition, Totals inStake);
    event PositionClosed(
        uint256 receivedAmount0,
        uint256 receivedAmount1,
        Totals inStake
    );
    event FeesColected(
        uint256 receivedAmount0,
        uint256 receivedAmount1,
        Totals feesIncome
    );
    event SereviceFeeDistributed(
        uint256 serviceFee0,
        uint256 serviceFee1,
        Totals feesIncome
    );
    event DoneAccountingFeesAndStake(
        uint256 loopCost,
        Totals inStake,
        Summarize summParams
    );
    event DoneCreatingNewStakes(
        uint256 loopCost,
        Totals inStake,
        Summarize summParams
    );
    event SettedSummarizationConfigs(Summarize summParams);

    // Properties
    function factory() external view returns (IRebalancerFactory);

    function pool() external view returns (IUniswapV3Pool);

    function token0() external view returns (IERC20);

    function token1() external view returns (IERC20);

    function posNFT() external view returns (IERC721);

    function positionManager()
        external
        view
        returns (INonfungiblePositionManager);

    function swapRouter() external view returns (ISwapRouter);

    function feesIncome()
        external
        view
        returns (uint256 amount0, uint256 amount1);

    function inStake() external view returns (uint256 amount0, uint256 amount1);

    function openPosition()
        external
        view
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1,
            int24 tickLower,
            int24 tickUpper
        );

    function summParams()
        external
        view
        returns (
            uint256 lastBlock,
            uint256 lastUser,
            int64 stage,
            Fraction memory fixedPrice,
            Totals memory toStake,
            uint256 shareDenominator,
            bool sellToken0,
            Totals memory distributedFees,
            Totals memory distributedDeposits
        );

    function users() external view returns (address[] memory);

    function isInUsers(address) external view returns (bool);

    function userStates(address)
        external
        view
        returns (
            Totals memory fee,
            Totals memory deposited,
            uint256 share,
            bool participateInStake
        );

    // Methods
    function deposit(uint256 token0Amount, uint256 token1Amount) external;

    function withdraw(bool withdrawDeposit) external;

    function participate() external;

    function rebalancePriceRange(
        int24 tickLowerCount,
        int24 tickUpperCount,
        uint256 token0Share,
        uint256 token1Share
    ) external;

    function deleteUsersWithoutFunds() external;

    function startSummarizeTrades() external;

    function summarizeUsersStates() external;

    function getDeadline() external view returns (uint256);

    function calcShare(
        uint256 total,
        uint256 numerator,
        uint256 denominator
    ) external pure returns (uint256);

    function isUserWithoutFunds(UserState memory user)
        external
        pure
        returns (bool);
}
