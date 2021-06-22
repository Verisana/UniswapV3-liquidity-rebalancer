// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

interface IRebalancerFactory {
    struct RebalancerFee {
        uint256 numerator;
        uint256 denominator;
    }

    event RebalancerCreated(
        address indexed tokenA,
        address indexed tokenB,
        uint24 indexed fee,
        address pool,
        address rebalancer
    );
    event RebalancerFeeChanged(RebalancerFee oldFee, RebalancerFee newFee);
    event BlockFrequencySummarizationChanged(
        uint256 oldSummarizationFrequency,
        uint256 newSummarizationFrequency
    );

    function summarizationFrequency() external view returns (uint256);

    function uniswapV3Factory() external view returns (IUniswapV3Factory);

    function getRebalancer(address pool)
        external
        view
        returns (address rebalancer);

    function setRebalanceFee(RebalancerFee calldata _rebalancerFee) external;

    function setBlockFrequencySummarization(uint256 _summarizationFrequency)
        external;

    function createRebalancer(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external returns (address rebalancer);

    function emergencyRefund(address[] calldata rebalancers) external;
}
