// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

interface IRebalancerFactory {
    struct RebalancerFee {
        uint256 numerator;
        uint256 denominator;
    }

    event OwnerChanged(address indexed oldOwner, address indexed newOwner);
    event RebalancerCreated(
        address indexed tokenA,
        address indexed tokenB,
        uint24 indexed fee,
        address pool,
        address rebalancer
    );
    event RebalancerFeeChanged(
        RebalancerFee oldFee,
        uint256 numeratorNew,
        uint256 denominatorNew
    );
    event BlockFrequencySummarizationChanged(
        uint256 oldSummarizationFrequency,
        uint256 newSummarizationFrequency
    );

    function uniswapV3Factory() external view returns (IUniswapV3Factory);
    function owner() external view returns (address);
    function summarizationFrequency() external view returns (uint256);
    function rebalancerFee()
        external
        view
        returns (uint256 numerator, uint256 denominator);

    function getRebalancer(address pool)
        external
        view
        returns (address rebalancer);

    function setOwner(address _owner) external;
    function setRebalanceFee(uint256 numerator, uint256 denominator) external;
    function setBlockFrequencySummarization(uint256 _summarizationFrequency)
        external;

    function createRebalancer(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external returns (address rebalancer);

    function emergencyRefund(address[] calldata rebalancers) external;
}
