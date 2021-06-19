// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "./interfaces/IRebalancerFactory.sol";
import "./libraries/NoDelegateCall.sol";

contract RebalancerFactory is IRebalancerFactory, Ownable, NoDelegateCall {
    RebalancerFee public rebalancerFee = RebalancerFee(0, 0);

    mapping(address => address) public override getRebalancer;

    function setRebalanceFee(RebalancerFee calldata _rebalancerFee)
        external
        override
        onlyOwner
    {
        emit RebalancerFeeChanged(rebalancerFee, _rebalancerFee);
        require(
            _rebalancerFee.numerator < _rebalancerFee.denominator,
            "New RebalancerFee's denomiator > numerator. Check inputs"
        );
        rebalancerFee = _rebalancerFee;
    }

    function createRebalancer(IUniswapV3Pool pool)
        external
        view
        override
        onlyOwner
        noDelegateCall
        returns (address rebalancer)
    {}

    function getRebalancer(IUniswapV3Pool pool)
        external
        view
        override
        returns (address rebalancer)
    {}

    function returnFunds(address[] calldata rebalancers)
        external
        override
        onlyOwner
    {}
}
