// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../interfaces/ICTFAdapter.sol";
import {  } from "../adapters/CTFAdapter.sol";
import "../interfaces/IBalancerPoolWrapper.sol";
import {  } from "../adapters/BalancerPoolWrapper.sol";

contract FutarchyPoolManager {
    using SafeERC20 for IERC20;

    ICTFAdapter public immutable ctfAdapter;
    IBalancerPoolWrapper public immutable balancerWrapper;
    IERC20 public immutable moneyToken;
    IERC20 public immutable quoteToken;

    bool public useEnhancedSecurity;
    address public admin;
    address public basePool;

    struct ConditionalPools {
        address yesPool;
        address noPool;
        bool isActive;
    }

    struct ConditionTokens {
        address moneyYesToken;
        address moneyNoToken;
        address quoteYesToken;
        address quoteNoToken;
    }

    mapping(bytes32 => ConditionalPools) public conditionPools;
    mapping(bytes32 => ConditionTokens) public conditionTokens;
    mapping(bytes32 => bool) public allowedSplits;

    // Errors
    error ConditionAlreadyActive();
    error ConditionNotActive();
    error Unauthorized();
    error SplitNotAllowed();

    // Events
    event SplitAllowed(address baseToken, address splitToken1, address splitToken2);
    event SplitPerformed(address baseToken, address yesToken, address noToken);
    event MergePerformed(address baseToken, address winningOutcomeToken);

    modifier onlyAdmin() {
        if (msg.sender != admin) revert Unauthorized();
        _;
    }

    constructor(
        address _ctfAdapter,            // ???  where does this get called?
        address _balancerWrapper,       // ???  is wrapper unique? what's it for?
        address _outcomeToken,
        address _moneyToken,            
        bool _useEnhancedSecurity,
        address _admin                  // ???  why need admin?
    ) {
        ctfAdapter = ICTFAdapter(_ctfAdapter);
        balancerWrapper = IBalancerPoolWrapper(_balancerWrapper);
        outcomeToken = IERC20(_outcomeToken);
        moneyToken = IERC20(_moneyToken);
        useEnhancedSecurity = _useEnhancedSecurity;
        admin = _admin;
    }

    function addAllowedSplit(
        address baseToken,
        address splitToken1,
        address splitToken2
    ) external onlyAdmin {
        allowedSplits[keccak256(abi.encodePacked(baseToken, splitToken1, splitToken2))] = true;
        emit SplitAllowed(baseToken, splitToken1, splitToken2);
    }

    // Use the BalancerPoolWrapper contract to create a  token swap ppol in the vault BalancerPoolWrapper was instantiated with.
    // NB currently only using 80/20 weight
    function createBasePool(                    
        uint256 moneyToken,
        uint256 quoteToken,
        uint256 weight                          // NB currently ignored. Calling 80/20 Factory
    ) external returns (address) {
        require (basePool==address(0), "basePool aready set.");

        bool success;
        // // Delegatecall to createPool on our balancerWrapper contract
        // (success, bytes memory data) = balancerWrapper.delegatecall(
        //     abi.encodeWithSignature("createPool(address,address,uint256)", address(moneyToken), address(quoteToken), weight)
        // );        
        // require(success, "Delegatecall failed in createPool(address,address,uint256) on balancerWrapper");
        // address basePool = abi.decode(data, (address));

        // Delegatecall to create8020Pool on our balancerWrapper contract
        (success, bytes memory data) = balancerWrapper.delegatecall(
            abi.encodeWithSignature("create8020Pool(address,address)", address(moneyToken), address(quoteToken))
        );        
        require(success, "Delegatecall failed to create8020Pool(address,address) on balancerWrapper");
        address newPool = abi.decode(data, (address));

        // Delegatecall to addLiquidity on our balancerWrapper contract
        (success) = balancerWrapper.delegatecall(
            abi.encodeWithSignature("addLiquidity(address,uint256,uint256)", newPool, moneyAmount, quoteAmount)
        );
        require(success, "Delegatecall failed to addLiquidity(address,uint256,uint256) on balancerWrapper");

        basePool = newPool;
        return basePool;
    }

    function splitOnCondition(
        bytes32 conditionId,
        uint256 baseAmount
    ) external returns (address yesPool, address noPool) {
        // ???
        if (conditionPools[conditionId].isActive) revert ConditionAlreadyActive();
        //TODO: what to do if conditionId exists but is not 'active'?

        uint256 beforeMoneyBal = moneyToken.balanceOf(address(this));
        uint256 beforeQuoteBal = quoteToken.balanceOf(address(this));

        // NB swapped order so that moneyToken / highWeightToken / 80% comes first
        (uint256 moneyAmount, uint256 quoteAmount) = balancerWrapper.removeLiquidity(basePool, baseAmount);

        // TODO: check these for order; sanity
        // if (useEnhancedSecurity) {
        //     _enforceAllowedSplit(address(outcomeToken), outYes, outNo);
        //     _enforceAllowedSplit(address(moneyToken), monYes, monNo);

        //     _verifySplitDimension(
        //         beforeOutBase,
        //         outcomeToken.balanceOf(address(this)),
        //         IERC20(outYes).balanceOf(address(this)),
        //         IERC20(outNo).balanceOf(address(this))
        //     );

        //     _verifySplitDimension(
        //         beforeMonBase,
        //         moneyToken.balanceOf(address(this)),
        //         IERC20(monYes).balanceOf(address(this)),
        //         IERC20(monNo).balanceOf(address(this))
        //     );
        // }
        (address moneyYes, address moneyNo, address quoteYes, address quoteNo, ) = _doSplit(conditionId, moneyAmount, quoteAmount);

        // NB general createPool not yet implemented, only create8020Pool
        yesPool = balancerWrapper.createPool(outYes, monYes, 500000);
        noPool = balancerWrapper.createPool(outNo, monNo, 500000);

        conditionPools[conditionId] = ConditionalPools(yesPool, noPool, true);
        conditionTokens[conditionId] = ConditionTokens(moneyYes, moneyNo, quoteYes, quoteNo);

        emit SplitPerformed(address(moneyToken), moneyYes, moneyNo);
        emit SplitPerformed(address(quoteToken), quoteYes, quoteNo);

        return (yesPool, noPool);
    }

    function mergeAfterSettlement(bytes32 conditionId) external {
        ConditionalPools memory pools = conditionPools[conditionId];
        if (!pools.isActive) revert ConditionNotActive();

        ConditionTokens memory ct = conditionTokens[conditionId];

        uint256 beforeOutBase = outcomeToken.balanceOf(address(this));
        uint256 beforeMonBase = moneyToken.balanceOf(address(this));
        uint256 beforeOutYes = IERC20(ct.outcomeYesToken).balanceOf(address(this));
        uint256 beforeOutNo = IERC20(ct.outcomeNoToken).balanceOf(address(this));
        uint256 beforeMonYes = IERC20(ct.moneyYesToken).balanceOf(address(this));
        uint256 beforeMonNo = IERC20(ct.moneyNoToken).balanceOf(address(this));

        (uint256 outAmt, uint256 monAmt) = balancerWrapper.removeLiquidity(pools.yesPool, type(uint256).max);

        // Redeem
        IERC20(ct.outcomeYesToken).approve(address(ctfAdapter), outAmt);
        IERC20(ct.moneyYesToken).approve(address(ctfAdapter), monAmt);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0; 
        amounts[1] = outAmt;
        ctfAdapter.redeemPositions(outcomeToken, conditionId, amounts, 2);

        amounts[1] = monAmt;
        ctfAdapter.redeemPositions(moneyToken, conditionId, amounts, 2);

        uint256 afterOutBase = outcomeToken.balanceOf(address(this));
        uint256 afterMonBase = moneyToken.balanceOf(address(this));
        uint256 afterOutYes = IERC20(ct.outcomeYesToken).balanceOf(address(this));
        uint256 afterOutNo = IERC20(ct.outcomeNoToken).balanceOf(address(this));
        uint256 afterMonYes = IERC20(ct.moneyYesToken).balanceOf(address(this));
        uint256 afterMonNo = IERC20(ct.moneyNoToken).balanceOf(address(this));

        if (useEnhancedSecurity) {
            _verifyMergeAllSides(beforeOutYes, afterOutYes, beforeOutNo, afterOutNo, beforeOutBase, afterOutBase);
            _verifyMergeAllSides(beforeMonYes, afterMonYes, beforeMonNo, afterMonNo, beforeMonBase, afterMonBase);
        }

        uint256 outR = afterOutBase > beforeOutBase ? (afterOutBase - beforeOutBase) : 0;
        uint256 monR = afterMonBase > beforeMonBase ? (afterMonBase - beforeMonBase) : 0;

        outcomeToken.approve(address(balancerWrapper), outR);
        moneyToken.approve(address(balancerWrapper), monR);
        balancerWrapper.addLiquidity(basePool, outR, monR);

        delete conditionPools[conditionId];
        delete conditionTokens[conditionId];

        emit MergePerformed(address(outcomeToken), ct.outcomeYesToken);
        emit MergePerformed(address(moneyToken), ct.moneyYesToken);
    }

    // ------------------ Internal Helper Functions ------------------

    function _doSplit(
        bytes32 conditionId,
        uint256 outAmt,
        uint256 monAmt
    ) internal returns (address outYes, address outNo, address monYes, address monNo) {
        outcomeToken.approve(address(ctfAdapter), outAmt);
        moneyToken.approve(address(ctfAdapter), monAmt);

        address[] memory outC = ctfAdapter.splitCollateralTokens(outcomeToken, conditionId, outAmt, 2);
        address[] memory monC = ctfAdapter.splitCollateralTokens(moneyToken, conditionId, monAmt, 2);

        outYes = outC[1];
        outNo = outC[0];
        monYes = monC[1];
        monNo = monC[0];
    }

    // kinda unnecessary - any sanity checks should take place well before storage
    function _storeConditionPools(bytes32 conditionId, address yesPool, address noPool) internal {
        // TODO: add existence check
        conditionPools[conditionId] = ConditionalPools(yesPool, noPool, true);
    }

    // kinda unnecessary - any sanity checks should take place well before storage
    function _storeConditionTokens(
        bytes32 conditionId,
        address moneyYes,
        address moneyNo,
        address quoteYes,
        address quoteNo,
    ) internal {
        conditionTokens[conditionId] = ConditionTokens(moneyYes, moneyNo, quoteYes, quoteNo);
    }

    // TODO: check- are 'Yes' and 'No' canonical?
    // ??? How do we know yes/ no as tokens if they are not split yet?
    function _enforceAllowedSplit(address baseTok, address yesTok, address noTok) internal view {
        if (!allowedSplits[keccak256(abi.encodePacked(baseTok, yesTok, noTok))]) revert SplitNotAllowed();
    }

    // Verification functions

    // On splitting: baseDelta = yesDelta = noDelta
    function _verifySplitDimension(
        uint256 baseBefore,
        uint256 baseAfter,
        uint256 yesAfter,
        uint256 noAfter
    ) internal pure {
        uint256 baseDelta = Math.max(baseBefore - baseAfter, 0);
        require (
            (baseBefore>=baseAfter 
                && yesAfter == baseDelta 
                && noAfter == baseDelta
            ), "Exact split integrity check failed"
        );
    }

    // On merging: max(yesSpent, noSpent) = baseGained
    function _verifyMergeAllSides(
        uint256 yesBefore,
        uint256 yesAfter,
        uint256 noBefore,
        uint256 noAfter,
        uint256 baseBefore,
        uint256 baseAfter
    ) internal pure {

        uint256 maxDelta = Math.max(
            Math.max(yesBefore - yesAfter, 0), 
            Math.max(noBefore - noAfter, 0));
        uint256 baseDelta = Math.max(baseAfter - baseBefore, 0);

        require (
            maxDelta != baseDelta, 
            "Exact merge all-sides integrity check failed"
        );
    }
}
