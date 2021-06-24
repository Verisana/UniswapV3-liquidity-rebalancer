// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "./interfaces/IRebalancerFactory.sol";
import "./interfaces/IRebalancer.sol";
import "./RebalancerDeployer.sol";
import "./NoDelegateCall.sol";

contract RebalancerFactory is
    IRebalancerFactory,
    RebalancerDeployer,
    NoDelegateCall
{
    IUniswapV3Factory public immutable override uniswapV3Factory =
        IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    uint256 public immutable override shareDenominator = 1000000;

    RebalancerFee public override rebalancerFee = RebalancerFee(0, 0);
    mapping(address => address) public override getRebalancer;


    // Once in every 24 hours
    uint256 public override summarizationFrequency = 5760;

    address public override owner;

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function setOwner(address _owner) external override {
        require(msg.sender == owner);
        emit OwnerChanged(owner, _owner);
        owner = _owner;
    }

    constructor() {
        owner = msg.sender;
        emit OwnerChanged(address(0), msg.sender);
    }

    function setBlockFrequencySummarization(uint256 _summarizationFrequency)
        external
        override
        onlyOwner
    {
        emit BlockFrequencySummarizationChanged(
            summarizationFrequency,
            _summarizationFrequency
        );

        // Even owner can not set more than ~48 hours. This measure prevents misbehavior from owner
        require(
            _summarizationFrequency < 11601,
            "Unreasonably big summarizationFrequency. Set it less than 11601"
        );
        summarizationFrequency = _summarizationFrequency;
    }

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
        for (uint256 i = 0; i < rebalancers.length; i++) {
            IRebalancer rebalancer = IRebalancer(rebalancers[i]);
            rebalancer.immediateFundsReturn();
        }
    }
}
