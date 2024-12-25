// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../../interfaces/contracts/futarchy/IBalancerPoolWrapper.sol";
// import "../../../interfaces/contracts/vault/IVault.sol";
import "../../../pool-weighted/contracts/WeightedPool8020Factory.sol";
import "../../../pool-weighted/contracts/WeightedPoolFactory.sol";

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
        // zeroes
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

        revert("THIS FUNCTION IS ONT IMPLEMENTED!");
        
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
        // TODO: we should use minBptAmountOut, at least as a sanity check, even if we don't care about large slippage.

        // you can also accept and pass through userData if you want this function composable (create a shadowed function with the extra input param userData)
        // bytes calldata userData
    ) external returns (uint256 lpAmount) {
        bytes userData;
        AddLiquidityKind kind = AddLiquidityKind.PROPORTIONAL // NB: will we also allow UNBALANCED and SINGLE_TOKEN_EXACT_OUT ?

        // Get poolId from pool address (NB- kelvin's noote - this is no longer necessary, right?)
        
        address[] memory assets = new address[](2);
        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = _moneyAmount;
        maxAmountsIn[1] = _quoteAmount;

        // TODO: check maxAmountsIn/ minBptAmountOut params are what you expect, ie _moneyAmount, _quoteAmount
        //  * @param maxAmountsIn Maximum amounts of input tokens
        //  * @param minBptAmountOut Minimum amount of output pool tokens
        AddLiquidityParams memory params = AddLiquidityParams(
            _pool, msg.sender, _moneyAmount,  _quoteAmount, kind, userData
        );

        // TODO: Assess security implications of approve to vault (see @dev notice)

        (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData) = AddLiquidityParams(params);
        return bptAmountOut;

                // FROM IVaultMain : 
                //     * @param params Parameters for the add liquidity (see above for struct definition)
                //     * @return amountsIn Actual amounts of input tokens
                //     * @return bptAmountOut Output pool token amount
                //     * @return returnData Arbitrary (optional) data with an encoded response from the pool
                //     */
                // function addLiquidity(
                //         AddLiquidityParams memory params
                //     ) external returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData);

                // OLD:
                // // Join pool with exact amounts
                // vault.joinPool(
                //     poolId,
                //     address(this),
                //     msg.sender,
                //     IBalancerVault.JoinPoolRequest({
                //         assets: assets,
                //         maxAmountsIn: maxAmountsIn,
                        /// HUH??? Why are moneyAmount, quoteAmount in userData?
                //         userData: abi.encode(moneyAmount, quoteAmount),
                //         fromInternalBalance: false
                //     })
                // );

    }

    function removeLiquidity(
        address pool,
        uint256 lpAmount
    ) external returns (uint256 moneyAmount, uint256 quoteAmount) {
        // Get poolId from pool address
        bytes32 poolId; // Need to implement getting poolId from pool address

        address[] memory assets = new address[](2);
        uint256[] memory minAmountsOut = new uint256[](2);

        // Exit pool with exact LP amount
        vault.exitPool(
            poolId,
            address(this),
            msg.sender,
            IBalancerVault.ExitPoolRequest({
                assets: assets,
                minAmountsOut: minAmountsOut,
                userData: abi.encode(lpAmount),
                toInternalBalance: false
            })
        );

        // moneyAmount = 
        // quoteAmount = 
    }
}