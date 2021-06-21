// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "./interfaces/IRebalancerFactory.sol";
import "./interfaces/IRebalancer.sol";
import "./RebalancerDeployer.sol";
import "./libraries/NoDelegateCall.sol";

contract RebalancerFactory is
    IRebalancerFactory,
    RebalancerDeployer,
    Ownable,
    NoDelegateCall
{
    RebalancerFee public rebalancerFee = RebalancerFee(0, 0);
    IUniswapV3Factory public immutable override uniswapV3Factory =
        IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

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

    function createRebalancer(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external override onlyOwner noDelegateCall returns (address rebalancer) {
        IUniswapV3Pool pool = IUniswapV3Pool(
            uniswapV3Factory.getPool(tokenA, tokenB, fee)
        );
        require(
            address(pool) != address(0),
            "Provided UniswapV3 pool doesn't exist. Check inputs"
        );
        require(
            getRebalancer[address(pool)] == address(0),
            "Rebalancer for input pool had been created"
        );

        rebalancer = deploy(address(this), address(pool));

        getRebalancer[address(pool)] = address(rebalancer);

        emit RebalancerCreated(
            tokenA,
            tokenB,
            fee,
            address(pool),
            address(rebalancer)
        );
    }

    function emergencyRefund(address[] calldata rebalancers)
        external
        override
        onlyOwner
        noDelegateCall
    {
        for (uint i = 0; i < rebalancers.length; i++) {
            IRebalancer rebalancer = IRebalancer(rebalancers[i]);
            rebalancer.immediateFundsReturn();
        }
    }
}
