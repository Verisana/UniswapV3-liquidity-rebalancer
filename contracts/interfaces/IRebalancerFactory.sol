// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

interface IRebalancerFactory {
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    function owner() external view returns (address);
    function shareDenominator() external view returns(uint);

    function setOwner(address _owner) external;

    event RebalancerCreated(
        address indexed tokenA,
        address indexed tokenB,
        uint24 indexed fee,
        address pool,
        address rebalancer
    );
    event RebalancerFeeChanged(uint256 oldFee, uint256 newFee);
    event BlockFrequencySummarizationChanged(
        uint256 oldSummarizationFrequency,
        uint256 newSummarizationFrequency
    );

    function summarizationFrequency() external view returns (uint256);

    function rebalancerFee()
        external
        view
        returns (uint256 numerator, uint256 denominator);

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
