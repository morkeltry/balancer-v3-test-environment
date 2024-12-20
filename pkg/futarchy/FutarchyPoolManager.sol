// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/contracts/futarchy/IERC20Extended.sol";
import "./ERC20Extended.sol";
import "../interfaces/contracts/futarchy/ICTFAdapter.sol";
import "../interfaces/contracts/futarchy/IBalancerPoolWrapper.sol";
// import "../interfaces/vault.IBasePool.sol";
import "../interfaces/contracts/pool-weighted/IWeightedPool.sol";


contract FutarchyPoolManager {
    using SafeERC20 for IERC20;

    IVault public vault;
    IWeightedPool public basePool;             // TODO: can use non-weighted pools?
    IERC20Extended public moneyToken;
    IERC20Extended public quoteToken; 
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


function getTwoPoolTokens(address _pool) public view returns (IERC20Extended, IERC20Extended) {
    // reverts if PoolNotRegistered     
    IERC20[] tokens = vault.getPoolTokens(_pool);
    require (tokens.length==2, "Only pools of two tokens are currently supported");
    return (tokens[0], tokens[1]);
}



function _deployYesNoConditionalTokens() internal returns (address, address, address, address) {
    // Deploy four ERC20 tokens.
    ERC20Extended token1 = new ERC20Extended("Token1", "TK1");
    ERC20Extended token2 = new ERC20Extended("Token2", "TK2");
    ERC20Extended token3 = new ERC20Extended("Token3", "TK3");
    ERC20Extended token4 = new ERC20Extended("Token4", "TK4");

    // Return the deployed token addresses.
    return (address(token1), address(token2), address(token3), address(token4));
}

function splitFromBasePoolOnCondition(address _pool) public {   //TODO: Access modifier
    (IERC20Extended money, IERC20Extended quote) = getTwoPoolTokens(_pool);
    // TODO: Check vault does not already have a split 



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