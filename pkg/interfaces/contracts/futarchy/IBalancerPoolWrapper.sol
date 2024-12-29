// src/interfaces/IBalancerPoolWrapper.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@balancer-labs/v3-pool-weighted/contracts/WeightedPool8020Factory.sol";
// import "../../../pool-weighted/contracts/WeightedPoolFactory.sol";

interface IBalancerVault is IVault {
    struct JoinPoolRequest {
        address[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

    struct ExitPoolRequest {
        address[] assets;
        uint256[] minAmountsOut;
        bytes userData;
        bool toInternalBalance;
    }

    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest memory request
    ) external payable;

    function exitPool(
        bytes32 poolId,
        address sender,
        address recipient,
        ExitPoolRequest memory request
    ) external;
    
    function createPool(
        bytes32 poolId,
        address[] memory tokens,
        uint256[] memory weights,
        address[] memory assetManagers,
        uint256 swapFeePercentage
    ) external returns (address);
}

interface IBalancerPoolWrapper {
    function createPool(
        address tokenHighWeight,
        address tokenLowWeight,
        uint256 weight
    ) external returns (address pool);

    // WILL BE REMOVED
    function create8020Pool(
        address tokenHighWeight,
        address tokenLowWeight
    ) external returns (address pool);

    function addLiquidity(
        address pool,
        uint256 amountHighWeightToken,
        uint256 amountLowWeightToken
    ) external returns (uint256 lpAmount);

    function removeLiquidity(
        address pool,
        uint256 lpAmount
    ) external returns (uint256 amountA, uint256 amountB);
}

