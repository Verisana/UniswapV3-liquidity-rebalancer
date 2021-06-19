// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

interface IRebalancerFactory {
    struct RebalancerFee {
        uint256 numerator;
        uint256 denominator;
    }

    event RebalancerCreated(
        address indexed token0,
        address indexed token1,
        uint24 indexed fee,
        int24 tickSpacing,
        address pool,
        address rebalancer
    );
    event RebalancerFeeChanged(RebalancerFee oldFee, RebalancerFee newFee);

    function setRebalanceFee(RebalancerFee calldata _rebalancerFee) external;

    function createRebalancer(address pool)
        external
        view
        returns (address rebalancer);

    function getRebalancer(address pool)
        external
        view
        returns (address rebalancer);

    function returnFunds(address[] calldata rebalancers) external;
}
