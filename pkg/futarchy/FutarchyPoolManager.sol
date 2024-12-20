// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ICTFAdapter.sol";
import "./interfaces/IBalancerPoolWrapper.sol";
// import "./interfaces/vault.IBasePool.sol";
import "./interfaces/pool-weighted.IWeightedPool.sol";


contract FutarchyPoolManager {
    using SafeERC20 for IERC20;

    IVault public vault;
    IWeightedPool public basePool;             // TODO: can use non-weighted pools?
    IERC20 public moneyToken;
    IERC20 public quoteToken; 
    // TODO: moneyToken and quoteToken are so named for convenience to read the code.
    // However, the order in which these are populated is dependent on the order that each token
    // was originally registered in the balancer vault. THESE MAY NOT LINE UP!    
    uint256[] public weights; // TODO: decide if better as struct. Remember ordering!


constructor(
    //
    // address _balancerWrapper, 
    address _vault,
    address _pool // Address of the weighted pool (is IWeightedPool)
    //
    //
    ) {
        vault = IVault(_vault);
        basePool = IWeightedPool(_pool);

        IERC20[] tokens = vault.getPoolTokens(pool);
        require (tokens.length==2, "Only pools of two tokens are currently supported");
        moneyToken = tokens[0];
        quoteToken = tokens[1];


        uint256[] fetchedWeights = new uint256[](2);
        WeightedPoolDynamicData _ ;
        // Is the pool we are accessing IWeightedPool ?
        // success should be true iff getNormalizedWeights() is callable (ie is present on pool)
        (bool success, bytes memory data) = _pool.staticcall(
            abi.encodeWithSignature("getNormalizedWeights()")
        );

        if (success) {
            weights = abi.decode(data, (uint256[]));
            fetchedWeights[0] = weights[0];
            fetchedWeights[1] = weights[1];
            _ = pool.getWeightedPoolDynamicData();
            // TODO: use _
        } else {
            fetchedWeights[0] = 500000;         // TODO: check default weights
            fetchedWeights[1] = 500000;
        }
        weights = fetchedWeights;



    }


// struct WeightedPoolDynamicData {
//     uint256[] balancesLiveScaled18;
//     uint256[] tokenRates;
//     uint256 staticSwapFeePercentage;
//     uint256 totalSupply;
//     bool isPoolInitialized;
//     bool isPoolPaused;
//     bool isPoolInRecoveryMode;





}