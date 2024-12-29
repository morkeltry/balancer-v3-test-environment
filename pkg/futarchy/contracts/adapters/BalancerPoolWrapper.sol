// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../../interfaces/contracts/futarchy/IBalancerPoolWrapper.sol";
// import "../../../interfaces/contracts/vault/IVault.sol";


// TODO: review visibility - is there any reason the functions should not be external?

// contract has no storage - suitable for delegatecall if authed functions are safe.
// delegatecall does not introduce vulns if:
// . this contract does not further delegate calls
// . calling contract intends to delegate its context to the code here
contract BalancerPoolWrapper {
    using SafeERC20 for IERC20;

    IBalancerVault public immutable vault;

    string public factoryVersion = "";
    string public poolVersion = "";

    constructor(address _vault) {
        vault = IBalancerVault(_vault);        
    }

    // may be called using delegatecall - be careful of authed calls / msg.sender as caller may use this code in its own context.
    function create8020Pool(
        address tokenHighWeight,
        address tokenLowWeight
    ) external returns (address pool) {

        uint256 swapFee = 3000000000000000; // 0.3% swap fee
        uint32 pauseWindowDuration = 0;
        PoolRoleAccounts memory adminRoleAccounts = PoolRoleAccounts(address(0), address(0), address(0));

        // zeroes except for token address
        TokenConfig memory tkConfHigh = TokenConfig(IERC20(tokenHighWeight), TokenType.STANDARD, IRateProvider(address(0)), false);
        TokenConfig memory tkConfLow = TokenConfig(IERC20(tokenLowWeight), TokenType.STANDARD, IRateProvider(address(0)), false);

        WeightedPool8020Factory pool8020Factory = new WeightedPool8020Factory(
            IVault(vault), pauseWindowDuration, factoryVersion, poolVersion
        );

        // Create pool through Balancer
        pool8020Factory.create(tkConfHigh, tkConfLow, adminRoleAccounts, swapFee);
        
        // No assetManagers 
        // https://github.com/balancer/docs-developers/blob/main/references/valuing-balancer-lp-tokens/asset-managers.md
        
        return pool;
    }

    // may be called using delegatecall - be careful of authed calls / msg.sender as caller may use this code in its own context.
    function createPool(
        address tokenA,
        address tokenB,
        uint256 weight
    ) external returns (address pool) {
        require(weight <= 1000000, "Weight must be <= 100%"); // 1000000 = 100%

        revert("THIS FUNCTION IS NOT IMPLEMENTED!");
        
        // Setup pool parameters
        address[] memory tokens = new address[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenB;

        uint256[] memory weights = new uint256[](2);
        weights[0] = weight;
        weights[1] = 1000000 - weight;

        address[] memory assetManagers = new address[](2);
        assetManagers[0] = address(0);
        assetManagers[1] = address(0);

        // Create unique poolId
        bytes32 poolId = keccak256(abi.encodePacked(
            block.timestamp,
            tokenA,
            tokenB,
            msg.sender
        ));

        // Create pool through Balancer
        pool = vault.createPool(
            poolId,
            tokens,
            weights,
            assetManagers,
            3000000000000000 // 0.3% swap fee
        );
        
        return pool;
    }

    // may be called using delegatecall - be careful of authed calls / msg.sender as caller may use this code in its own context.
    function addLiquidity(
        address _pool,
        uint256 _moneyAmount, 
        uint256 _quoteAmount

        // you can also accept and pass through userData if you want this function composable 
        // (create a shadowed function with the extra input param  bytes calldata userData)
    ) external returns (uint256 lpAmount) {
        bytes memory userData;
        // NB: will we also allow UNBALANCED and SINGLE_TOKEN_EXACT_OUT ?
        AddLiquidityKind kind = AddLiquidityKind.PROPORTIONAL;
        uint256 minBptAmountOut = 1;   // Temporary; Consider using minBptAmountOut as a proper sanity check, even if we don't care about large slippage.        
        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = _moneyAmount;
        maxAmountsIn[1] = _quoteAmount;

        AddLiquidityParams memory params = AddLiquidityParams(
            _pool, msg.sender, maxAmountsIn, minBptAmountOut, kind, userData
        );

        // NB: approve to vault has security implications  (see @dev notice). Consider these.

        (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData) = vault.addLiquidity(params);
        return bptAmountOut;
        // NB: amountsIn and returnData are unused and if not returned from this function, should not be set       
    }

    function removeLiquidity(
        address _pool,
        uint256 _maxBptAmountIn
        // consider setting minAmountsOut[] as a sanity check - this feels sensible, even if less important than the minBptAmountOut on addLiquidity

    ) external returns (uint256 moneyAmount, uint256 quoteAmount) {
        bytes32 poolId;
        bytes memory userData;
        uint256[] memory minAmountsOut = new uint256[](2);              // zeroes
        // NB: will we also allow SINGLE_TOKEN_EXACT_IN and SINGLE_TOKEN_EXACT_OUT ?
        RemoveLiquidityKind kind = RemoveLiquidityKind.PROPORTIONAL;

        RemoveLiquidityParams memory params = RemoveLiquidityParams(
            _pool, msg.sender, _maxBptAmountIn, minAmountsOut, kind, userData
        );

        (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData) = vault.removeLiquidity(params);
        // NB: bptAmountIn and returnData are unused and if not returned from this function, should not be set.

        return (amountsOut[0], amountsOut[1]);
    }
}