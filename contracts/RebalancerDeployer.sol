// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "./interfaces/IRebalancerDeployer.sol";
import "./Rebalancer.sol";

contract RebalancerDeployer is IRebalancerDeployer {
    struct Parameters {
        address factory;
        address pool;
    }

    Parameters public override parameters;

    function deploy(address factory, address pool)
        internal
        returns (address rebalancer)
    {
        parameters = Parameters({factory: factory, pool: pool});
        rebalancer = address(
            new Rebalancer{salt: keccak256(abi.encode(pool))}()
        );
        delete parameters;
    }
}
