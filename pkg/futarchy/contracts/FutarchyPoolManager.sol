// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../../interfaces/contracts/futarchy/ICTFAdapter.sol";
import "../../interfaces/contracts/futarchy/IBalancerPoolWrapper.sol";
import "./adapters/GnosisCTFAdapter.sol";
import "./adapters/BalancerPoolWrapper.sol";

contract FutarchyPoolManager {
    using SafeERC20 for IERC20;

    ICTFAdapter public immutable ctfAdapter;
    IBalancerPoolWrapper public immutable balancerWrapper;
    // NB: moneyToken and quoteToken are so named for convenience to read the code.
    // However, the order in which these are populated is dependent on the order that each token
    // was originally registered in the balancer vault. THESE MAY NOT LINE UP!  
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
        address _ctfAdapter,
        address _balancerWrapper,
        address _quoteToken,
        address _moneyToken,            
        bool _useEnhancedSecurity,
        address _admin               
    ) {
        ctfAdapter = ICTFAdapter(_ctfAdapter);
        balancerWrapper = IBalancerPoolWrapper(_balancerWrapper);
        quoteToken = IERC20(_quoteToken);
        moneyToken = IERC20(_moneyToken);
        useEnhancedSecurity = _useEnhancedSecurity;
        admin = _admin;
    }

    struct balancesToVerify{
        uint256 base;
        uint256 yes;
        uint256 no;
    }

    function addAllowedSplit(
        address baseToken,
        address splitToken1,
        address splitToken2
    ) external onlyAdmin {
        allowedSplits[keccak256(abi.encodePacked(baseToken, splitToken1, splitToken2))] = true;
        emit SplitAllowed(baseToken, splitToken1, splitToken2);
    }

    // Use the BalancerPoolWrapper contract to create a token swap ppol in the vault BalancerPoolWrapper was instantiated with.
    // NB currently only using 80/20 weight
    // TODO: Protect against donate attacks - needs to be disabled on pool using PoolConfig.LiquidityManagement.enableDonation = false, 
    // rather than on addLiquidity (which could be bypassed)
    function createBasePool(
        uint256 _weight_currently_ignored,                // NB currently ignored. Calling 80/20 Factory
        uint256 moneyAmount
    ) external returns (address) {
        require (basePool==address(0), "basePool aready set.");

        uint256 weight = 800000;
        uint256 quoteAmount = (moneyAmount * 1000000) / weight - moneyAmount;
        bool success;
        bytes memory data;
        
        // // Delegatecall to createPool on our balancerWrapper contract
        // (success, bytes memory data) = balancerWrapper.delegatecall(
        //     abi.encodeWithSignature("createPool(address,address,uint256)", address(moneyToken), address(quoteToken), weight)
        // );        
        // require(success, "Delegatecall failed in createPool(address,address,uint256) on balancerWrapper");
        // address basePool = abi.decode(data, (address));

        // Delegatecall to create8020Pool on our balancerWrapper contract
        (success, data) = address(balancerWrapper).delegatecall(
            abi.encodeWithSignature("create8020Pool(address,address)", moneyToken, quoteToken)
        );        
        require(success, "Delegatecall failed to create8020Pool(address,address) on balancerWrapper");
        address newPool = abi.decode(data, (address));

        // Delegatecall to addLiquidity on our balancerWrapper contract
        (success, ) = address(balancerWrapper).delegatecall(
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
        if (conditionPools[conditionId].isActive) revert ConditionAlreadyActive();
        // Consider sanity check: is it possible to reach situation where conditionId exists but is not 'active'?

        // NB swapped order so that moneyToken / highWeightToken / 80% comes first
        (uint256 moneyAmount, uint256 quoteAmount) = balancerWrapper.removeLiquidity(basePool, baseAmount);

        // TODO: check these for order; sanity
        // if (useEnhancedSecurity) {
        //     _enforceAllowedSplit(address(quoteToken), outYes, outNo);
        //     _enforceAllowedSplit(address(moneyToken), monYes, monNo);

        //     _verifySplitDimension(
        //         beforeQuoteBase,
        //         quoteToken.balanceOf(address(this)),
        //         IERC20(outYes).balanceOf(address(this)),
        //         IERC20(outNo).balanceOf(address(this))
        //     );

        //     _verifySplitDimension(
        //         beforeMoneyBase,
        //         moneyToken.balanceOf(address(this)),
        //         IERC20(monYes).balanceOf(address(this)),
        //         IERC20(monNo).balanceOf(address(this))
        //     );
        // }
        (address moneyYes, address moneyNo, address quoteYes, address quoteNo ) = _doSplit(conditionId, moneyAmount, quoteAmount);

        // NB general createPool not yet implemented, only create8020Pool
        yesPool = balancerWrapper.create8020Pool(moneyYes, quoteYes);
        noPool = balancerWrapper.create8020Pool(moneyNo, quoteNo);

        // call the storage functiuons here, don't store direct
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

        (balancesToVerify memory beforeMoney, balancesToVerify memory beforeQuote)  = _getBalances(ct);

        (uint256 moneyAmount, uint256 quoteAmount) = 
            balancerWrapper.removeLiquidity(pools.yesPool, type(uint256).max);

        // Redeem
        IERC20(ct.quoteYesToken).approve(address(ctfAdapter), moneyAmount);
        IERC20(ct.moneyYesToken).approve(address(ctfAdapter), quoteAmount);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = moneyAmount; 
        amounts[1] = quoteAmount;
        ctfAdapter.redeemPositions(quoteToken, conditionId, amounts, 2);

        (balancesToVerify memory afterMoney, balancesToVerify memory afterQuote)  = _getBalances(ct);


        // NB: this check is post-effect and therefore susceptibility to gas exhaustion should be assessed.
        if (useEnhancedSecurity) {
            _verifyMergeAllSides(beforeQuote, afterQuote);
            _verifyMergeAllSides(beforeMoney, afterMoney);
        }

        uint256 outR = Math.max(afterQuote.base - beforeQuote.base, 0);
        uint256 monR = Math.max(afterMoney.base - beforeMoney.base, 0);

        quoteToken.approve(address(balancerWrapper), outR);
        moneyToken.approve(address(balancerWrapper), monR);
        balancerWrapper.addLiquidity(basePool, outR, monR);

        delete conditionPools[conditionId];
        delete conditionTokens[conditionId];

        emit MergePerformed(address(quoteToken), ct.quoteYesToken);
        emit MergePerformed(address(moneyToken), ct.moneyYesToken);
    }

    // ------------------ Internal Helper Functions ------------------

    function _doSplit(
        bytes32 conditionId,
        uint256 outAmt,
        uint256 monAmt
    ) internal returns (address outYes, address outNo, address monYes, address monNo) {
        quoteToken.approve(address(ctfAdapter), outAmt);
        moneyToken.approve(address(ctfAdapter), monAmt);

        address[] memory outC = ctfAdapter.splitCollateralTokens(quoteToken, conditionId, outAmt, 2);
        address[] memory monC = ctfAdapter.splitCollateralTokens(moneyToken, conditionId, monAmt, 2);

        outYes = outC[1];
        outNo = outC[0];
        monYes = monC[1];
        monNo = monC[0];
    }

    // NB: sanity checks should take place well before storage
    function _storeConditionPools(bytes32 conditionId, address yesPool, address noPool) internal {
        // TODO: add existence check
        conditionPools[conditionId] = ConditionalPools(yesPool, noPool, true);
    }

    // NB: sanity checks should take place well before storage
    function _storeConditionTokens(
        bytes32 conditionId,
        address moneyYes,
        address moneyNo,
        address quoteYes,
        address quoteNo
    ) internal {
        // checks here
        conditionTokens[conditionId] = ConditionTokens(moneyYes, moneyNo, quoteYes, quoteNo);
    }

    // TODO: check- are 'Yes' and 'No' canonical?
    function _enforceAllowedSplit(address baseTok, address yesTok, address noTok) internal view {
        if (!allowedSplits[keccak256(abi.encodePacked(baseTok, yesTok, noTok))]) revert SplitNotAllowed();
    }

    // Verification functions

    function _getBalances (
        // address selfAddy,
        ConditionTokens memory ct
    ) internal view returns (balancesToVerify memory money, balancesToVerify memory quote)  {
        address selfAddy = address(this);

        quote.base = quoteToken.balanceOf(address(this));
        money.base = moneyToken.balanceOf(address(this));
        quote.yes = IERC20(ct.quoteYesToken).balanceOf(address(this));
        quote.no = IERC20(ct.quoteNoToken).balanceOf(address(this));
        money.yes = IERC20(ct.moneyYesToken).balanceOf(address(this));
        money.no = IERC20(ct.moneyNoToken).balanceOf(address(this));
    }

    // On splitting: baseDelta = yesDelta = noDelta
    function _verifySplitDimension(
       balancesToVerify memory before, balancesToVerify memory afterr
    ) internal pure {
        uint256 baseDelta = Math.max(before.base - afterr.base, 0);
        require (
            (before.base >= afterr.base  
                && afterr.yes == baseDelta 
                && afterr.no == baseDelta
            ), "Exact split integrity check failed"
        );
    }

    // On merging: max(yesSpent, noSpent) = baseGained
    function _verifyMergeAllSides(
        balancesToVerify memory before, balancesToVerify memory afterr) internal pure {
        uint256 maxDelta = Math.max(
            Math.max(before.yes - afterr.yes, 0), 
            Math.max(before.no - afterr.no, 0));
        uint256 baseDelta = Math.max(afterr.base - before.base, 0);

        require (
            maxDelta != baseDelta, 
            "Exact merge all-sides integrity check failed"
        );
    }
}
