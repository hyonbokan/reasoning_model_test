CRITIC_ENRICH_FINDINGS = """
You are an expert smart contract security auditor tasked with summarizing additional insights for security findings. Your job is to create a detailed summary of key insights from the mitigation analysis, counter-argument, and expert justification for each finding.

## **Task:**
For each security finding, create a focused summary that incorporates the most important insights from the available information (the mitigation analysis, counter-argument, and expert justification). Also, reassess the severity based on this comprehensive analysis.

## **Instructions for Summary Creation:**
Create a concise but detailed summary that:
 - Highlights the most significant insights from mitigation analysis, counter-arguments, and justifications
 - Focuses on information that adds value beyond the original finding
 - Provides additional context that helps understand the true impact and likelihood
 - Can be appended to the existing description without redundancy

## **Instructions for Severity Assessment:**
Reassess the severity based on:
 - The complete analysis of the issue
 - Insights from mitigation analysis
 - Strength of counter-argument and its rebuttal
 - The real-world impact and likelihood of exploitation
 - Use the severity matrix below to guide your assessment

**Severity Matrix:**
Use this severity matrix to determine the appropriate severity level based on both impact and likelihood and the new insights:

| Impact/Likelihood | High Impact | Medium Impact | Low Impact |
|-------------------|-------------|---------------|------------|
| High Likelihood   | High        | Medium        | Medium     |
| Medium Likelihood | High        | Medium        | Low        |
| Low Likelihood    | Medium      | Low           | Low        |

- First evaluate the potential impact (what could happen if exploited)
- Then assess the likelihood (how probable is it that the vulnerability will be exploited)
- Use the matrix above to determine the final severity rating
- When in doubt between two severity levels, always pick the lower one
- It is always better to be conservative in the severity assessment
- Use only the exact severity levels: "High", "Medium", "Low", "Info", or "Best Practices"

## **Additional considerations:**
- Don't explicitly reference "mitigation analysis", "counter-argument", or "justification"
- Maintain a neutral, expert tone throughout
- Focus on new insights rather than repeating information already in the finding

## **Output Format:**
Return the output in the following JSON format, without any additional text, comments, explanations or chain of thought:
```json
{
    "enriched_findings": [
        {
            "index": 0,
            "insight_summary": "A detailed summary of key insights from analysis...",
            "updated_severity": "Medium"
        },
        {
            "index": 1,
            "insight_summary": "A detailed summary of key insights from analysis...",
            "updated_severity": "High"
        }
    ]
}
```

## **Findings to enhance:**
```json
[{"Issue": "Unchecked subtraction on fee redistribution can under\u2011flow and mint 2^256\u2011sized amounts of stable tokens", "Severity": "Medium", "Contracts": ["Trading.sol"], "Description": "Both `_handleOpenFees` and `_handleCloseFees` perform several subtractions inside an `unchecked{}` block after the fees have been re\u2011scaled by `asset.feeMultiplier`.\n\n```solidity\n// _handleOpenFees \u2013 relevant fragment\nunchecked {\n    _fees.daoFees = _fees.daoFees * asset.feeMultiplier / DIVISION_CONSTANT;\n    _fees.burnFees = _fees.burnFees * asset.feeMultiplier / DIVISION_CONSTANT;\n    _fees.referralFees = _fees.referralFees * asset.feeMultiplier / DIVISION_CONSTANT;\n    _fees.botFees = _fees.botFees * asset.feeMultiplier / DIVISION_CONSTANT;\n}\n...\n// daoFees is reduced after the optional referral / bot payout\n_fees.daoFees = _fees.daoFees - _fees.referralFees*2;   // <\u2011\u2011 unchecked subtraction\n```\n\n`setFees()` enforces the invariant `daoFees >= botFees + referralFees*2` **before** the per\u2011asset multiplier is applied, but no invariant is checked after the multiplication.  A malicious (or mis\u2011configured) asset can set `feeMultiplier` to any value > 1e10 (for example 2e10 = 200\u00a0%) which makes\n`_fees.daoFees * multiplier / 1e10  <  referralFees*2` and the subtraction under\u2011flows.\n\nBecause the code is inside an `unchecked` block, the under\u2011flow wraps around to a huge unsigned integer close to 2\u00b2\u2075\u2076, so\n\n```solidity\nuint _daoFeesPaid = _positionSize * _fees.daoFees / DIVISION_CONSTANT;\n```\n\nbecomes an astronomically large number.  `IStable(_tigAsset).mintFor(address(this), _daoFeesPaid)` is then executed, giving the contract effectively **infinite minting power over the protocol\u2019s stable\u2011coin** (and later distributed to the DAO/Gov NFT holders).\n\nThe same pattern (and impact) exists in `_handleCloseFees`:\n\n```solidity\nuint _daoFeesPaid = (\n      _positionSize*_fees.daoFees/ DIVISION_CONSTANT\n  )*asset.feeMultiplier/DIVISION_CONSTANT;\n...\n_daoFeesPaid = _daoFeesPaid - _referralFeesPaid*2; // unchecked\n```\n\nConsequences:\n\u2022 unlimited inflation of the stable token;\n\u2022 protocol insolvency as vaults are drained when the inflated tokens are redeemed;\n\u2022 traders\u2019 PnL/withdrawals revert once vault liquidity is exhausted.\n", "Recommendation": "", "Detector": "context_scan_default_o3-2025-04-16_0", "Mitigation": "This is a valid issue. The unchecked subtraction can underflow and wrap around to a huge value, but since it's in Solidity 0.8+ and inside an explicit unchecked block, this is intentionally bypassing the compiler's safety checks. Downgraded from High to Medium as it requires a misconfiguration of feeMultiplier.", "CounterArgument": null, "Justification": null, "index": 0}, {"Issue": "Fee calculations rely on unchecked subtraction that can revert due to under\u2011flow and block trading", "Severity": "Medium", "Contracts": ["Trading.sol"], "Description": "The same unchecked subtractions (`_fees.daoFees - _fees.botFees`, `_fees.daoFees - _fees.referralFees*2`) that can wrap around (see High finding) will *revert* instead of wrapping if Solidity\u2019s default checked arithmetic is used elsewhere in the function.  While the dangerous wrap happens only inside the `unchecked{}` scope, the resulting wrapped value (`_fees.daoFees`) is later used **outside** the `unchecked` block:\n\n```solidity\nuint _daoFeesPaid = _positionSize * _fees.daoFees / DIVISION_CONSTANT; // <- checked context\n```\n\nIf `_fees.daoFees` wrapped to a value larger than `type(uint256).max / _positionSize`, the subsequent multiplication is performed **with checks enabled** and the transaction reverts.  A single mis\u2011configured pair (`feeMultiplier` too high) therefore bricks:\n\u2022 market order opening (reverts inside `_handleOpenFees`)\n\u2022 limit order execution (same path)\n\u2022 closing positions ( `_handleCloseFees` )\n\u2022 liquidations ( `_handleCloseFees` )\nEffectively the whole market for that asset freezes and all traders are unable to interact with their positions until governance fixes the parameter.\n", "Recommendation": "", "Detector": "context_scan_default_o3-2025-04-16_0", "Mitigation": "This is a valid issue related to the previous one. The unchecked subtraction can lead to reverts when the wrapped value is used in checked context.", "CounterArgument": null, "Justification": null, "index": 1}, {"Issue": "ERC20 return values are ignored \u2013 tokens that do not revert on failure can break accounting", "Severity": "Low", "Contracts": ["Trading.sol", "StableVault.sol"], "Description": "Throughout the code base the protocol relies on `transfer` / `transferFrom` succeeding but never checks the boolean return value:\n\n```solidity\n// Trading._handleDeposit\nIERC20(_marginAsset).transferFrom(_trader, address(this), _margin/_marginDecMultiplier);\n...\n// StableVault.deposit\nIERC20(_token).transferFrom(_msgSender(), address(this), _amount);\n```\n\nFor ERC\u201120 tokens such as USDT, TUSD, or any token that returns `false` instead of reverting, these calls silently fail, leaving the vault without the expected assets while the protocol continues as if the transfer succeeded (balances, fees, position sizes, etc.).  Subsequent state changes then rely on non\u2011existent funds and can be exploited to mint positions out of thin air or withdraw more than deposited.\n", "Recommendation": "", "Detector": "context_scan_default_o3-2025-04-16_0", "Mitigation": "This is a valid issue. Some ERC20 tokens return false instead of reverting on failure, which could lead to accounting issues.", "CounterArgument": null, "Justification": null, "index": 2}, {"Issue": "Unchecked subtraction in fee calculation can lead to underflow", "Severity": "Medium", "Contracts": ["Trading.sol"], "Description": "In the `_handleOpenFees` function, there are unchecked subtractions that could underflow if certain conditions are met. When a trader has a referrer, the contract subtracts twice the referral fee from the DAO fee, and similarly when a bot executes the function, the bot fee is subtracted from DAO fee.\n\n```solidity\nif (_referrer != address(0)) {\n    unchecked {\n        IStable(_tigAsset).mintFor(\n            _referrer,\n            _positionSize\n            * _fees.referralFees // get referral fee%\n            / DIVISION_CONSTANT // divide by 100%\n        );\n    }\n    _fees.daoFees = _fees.daoFees - _fees.referralFees*2;\n}\nif (_isBot) {\n    unchecked {\n        IStable(_tigAsset).mintFor(\n            _msgSender(),\n            _positionSize\n            * _fees.botFees // get bot fee%\n            / DIVISION_CONSTANT // divide by 100%\n        );\n    }\n    _fees.daoFees = _fees.daoFees - _fees.botFees;\n}\n```\n\nIf `_fees.referralFees*2` exceeds `_fees.daoFees` or if `_fees.botFees` exceeds the remaining DAO fees after referral fee deduction, an integer underflow will occur, resulting in an extremely large DAO fee. The only check present is `require(_daoFees >= _botFees+_referralFees*2)` in the `setFees` function, but this doesn't guard against potential issues when applying the fee multiplier from the asset.\n\nNotice that just before these subtractions, each fee is multiplied by `asset.feeMultiplier`:\n\n```solidity\nunchecked {\n    _fees.daoFees = _fees.daoFees * asset.feeMultiplier / DIVISION_CONSTANT;\n    _fees.burnFees = _fees.burnFees * asset.feeMultiplier / DIVISION_CONSTANT;\n    _fees.referralFees = _fees.referralFees * asset.feeMultiplier / DIVISION_CONSTANT;\n    _fees.botFees = _fees.botFees * asset.feeMultiplier / DIVISION_CONSTANT;\n}\n```\n\nIf `asset.feeMultiplier` causes `_fees.referralFees*2` or `_fees.botFees` to grow disproportionately compared to `_fees.daoFees`, an underflow can occur. This would lead to excessively high DAO fees being charged, potentially draining users' funds or reverting transactions unexpectedly.", "Recommendation": "", "Detector": "context_scan_default_claude-3-7-sonnet-20250219_1", "Mitigation": "Downgraded from High to Medium as this is a duplicate of issue #0 and #1, describing the same unchecked subtraction vulnerability.", "CounterArgument": null, "Justification": null, "index": 3}, {"Issue": "Oracle price manipulation vulnerability", "Severity": "High", "Contracts": ["Trading.sol", "TradingLibrary.sol"], "Description": "The protocol relies heavily on off-chain price data signed by authorized nodes. This design exposes the protocol to potential price manipulation if these nodes are compromised. While there is a secondary check against Chainlink oracle prices, this verification is optional and only enforced if `chainlinkEnabled` is true and a Chainlink feed exists for the asset.\n\n```solidity\nfunction verifyPrice(\n    uint256 _validSignatureTimer,\n    uint256 _asset,\n    bool _chainlinkEnabled,\n    address _chainlinkFeed,\n    PriceData calldata _priceData,\n    bytes calldata _signature,\n    mapping(address => bool) storage _isNode\n)\n    external view\n{\n    address _provider = (\n        keccak256(abi.encode(_priceData))\n    ).toEthSignedMessageHash().recover(_signature);\n    require(_provider == _priceData.provider, \"BadSig\");\n    require(_isNode[_provider], \"!Node\");\n    // ... other checks ... \n    if (_chainlinkEnabled && _chainlinkFeed != address(0)) {\n        int256 assetChainlinkPriceInt = IPrice(_chainlinkFeed).latestAnswer();\n        if (assetChainlinkPriceInt != 0) {\n            uint256 assetChainlinkPrice = uint256(assetChainlinkPriceInt) * 10**(18 - IPrice(_chainlinkFeed).decimals());\n            require(\n                _priceData.price < assetChainlinkPrice+assetChainlinkPrice*2/100 &&\n                _priceData.price > assetChainlinkPrice-assetChainlinkPrice*2/100, \"!chainlinkPrice\"\n            );\n        }\n    }\n}\n```\n\nEven when Chainlink verification is enabled, the price is allowed to deviate by up to 2% from the Chainlink price. This deviation could be exploited by malicious oracles to manipulate prices within the allowed range, enabling profitable trading or unfair liquidations.\n\nAdditionally, every operation that relies on price data (opening/closing positions, liquidations, limit orders) is vulnerable to this manipulation. As a decentralized perpetual trading platform with leverage, price manipulation could lead to significant financial losses for users.", "Recommendation": "", "Detector": "context_scan_default_claude-3-7-sonnet-20250219_1", "Mitigation": "This is a valid issue. The price oracle design allows for potential manipulation within the allowed deviation range.", "CounterArgument": null, "Justification": null, "index": 4}, {"Issue": "Missing validation in _handleOpenFees calculation", "Severity": "Medium", "Contracts": ["Trading.sol"], "Description": "In the `initiateMarketOrder` function, the contract calculates `_marginAfterFees` by subtracting fees from the original margin, but doesn't verify that the fees are less than or equal to the margin amount. This can lead to underflow in Solidity 0.8+ which would cause the transaction to revert, but more importantly, could result in unexpected behavior if the check is bypassed in future updates.\n\n```solidity\nfunction initiateMarketOrder(\n    TradeInfo calldata _tradeInfo,\n    PriceData calldata _priceData,\n    bytes calldata _signature,\n    ERC20PermitData calldata _permitData,\n    address _trader\n)\n    external\n{\n    // ... input validation ... \n    uint256 _marginAfterFees = _tradeInfo.margin - _handleOpenFees(_tradeInfo.asset, _tradeInfo.margin*_tradeInfo.leverage/1e18, _trader, _tigAsset, false);\n    uint256 _positionSize = _marginAfterFees * _tradeInfo.leverage / 1e18;\n    _handleDeposit(_tigAsset, _tradeInfo.marginAsset, _tradeInfo.margin, _tradeInfo.stableVault, _permitData, _trader);\n    // ... continue with position creation ...\n}\n```\n\nFurthermore, the original margin amount is used in `_handleDeposit` rather than the margin after fees, which means the trader pays the full margin but only receives a position sized based on the margin after fees. This behavior is inconsistent and could be confusing to users.\n\nIf the fee calculation in `_handleOpenFees` ever returns an amount greater than or equal to the margin amount, the user would pay the full margin but receive a position with zero or negative effective margin, likely resulting in immediate liquidation.", "Recommendation": "", "Detector": "context_scan_default_claude-3-7-sonnet-20250219_1", "Mitigation": "This is a valid issue. The lack of validation could lead to unexpected behavior if fees exceed margin.", "CounterArgument": null, "Justification": null, "index": 5}, {"Issue": "Unchecked `unchecked` block in liquidatePosition", "Severity": "Low", "Contracts": ["Trading.sol"], "Description": "The entire `liquidatePosition` function is wrapped in an `unchecked` block, which disables Solidity 0.8+'s automatic overflow and underflow checks. This is particularly concerning for a critical function that handles liquidations and affects user funds.\n\n```solidity\nfunction liquidatePosition(\n    uint _id,\n    PriceData calldata _priceData,\n    bytes calldata _signature\n)\n    external\n{\n    unchecked {\n        tradingExtension._checkGas();\n        IPosition.Trade memory _trade = position.trades(_id);\n        if (_trade.orderType != 0) revert(\"4\"); //IsLimit\n\n        (uint256 _price,) = tradingExtension.getVerifiedPrice(_trade.asset, _priceData, _signature, 0);\n        (uint256 _positionSizeAfterPrice, int256 _payout) = TradingLibrary.pnl(_trade.direction, _price, _trade.price, _trade.margin, _trade.leverage, _trade.accInterest);\n        uint256 _positionSize = _trade.margin*_trade.leverage/1e18;\n        if (_payout > int256(_trade.margin*(DIVISION_CONSTANT-liqPercent)/DIVISION_CONSTANT)) revert NotLiquidatable();\n        if (_trade.direction) {\n            tradingExtension.modifyLongOi(_trade.asset, _trade.tigAsset, false, _positionSize);\n        } else {\n            tradingExtension.modifyShortOi(_trade.asset, _trade.tigAsset, false, _positionSize);\n        }\n        _updateFunding(_trade.asset, _trade.tigAsset);\n        _handleCloseFees(_trade.asset, type(uint).max, _trade.tigAsset, _positionSizeAfterPrice, _trade.trader, true);\n        position.burn(_id);\n        emit PositionLiquidated(_id, _trade.trader, _msgSender());\n    }\n}\n```\n\nWithin this function, several critical arithmetic operations are performed:\n\n1. Calculation of position size: `_trade.margin*_trade.leverage/1e18`\n2. Calculation of liquidation threshold: `_trade.margin*(DIVISION_CONSTANT-liqPercent)/DIVISION_CONSTANT`\n3. Various calculations within the called functions\n\nAny overflow or underflow in these calculations would silently produce incorrect results rather than reverting, potentially leading to:\n\n1. Wrong liquidation decisions\n2. Incorrect fee calculations\n3. Improper position size adjustments in the open interest\n\nThis could result in financial losses for both traders and the protocol itself.", "Recommendation": "", "Detector": "context_scan_default_claude-3-7-sonnet-20250219_1", "Mitigation": "Downgraded from Medium to Low as this is in Solidity 0.8+ and the unchecked block is intentional for gas optimization. The risk is present but requires specific conditions to be exploitable.", "CounterArgument": null, "Justification": null, "index": 6}, {"Issue": "Unlimited token approvals", "Severity": "Low", "Contracts": ["Trading.sol"], "Description": "In the `_handleDeposit` function, the contract approves an unlimited amount (`type(uint).max`) of the token to be spent by the StableVault contract. This is a risky pattern that grants unlimited access to the contract's token balance.\n\n```solidity\nfunction _handleDeposit(address _tigAsset, address _marginAsset, uint256 _margin, address _stableVault, ERC20PermitData calldata _permitData, address _trader) internal {\n    IStable tigAsset = IStable(_tigAsset);\n    if (_tigAsset != _marginAsset) {\n        if (_permitData.usePermit) {\n            ERC20Permit(_marginAsset).permit(_trader, address(this), _permitData.amount, _permitData.deadline, _permitData.v, _permitData.r, _permitData.s);\n        }\n        uint256 _balBefore = tigAsset.balanceOf(address(this));\n        uint _marginDecMultiplier = 10**(18-ExtendedIERC20(_marginAsset).decimals());\n        IERC20(_marginAsset).transferFrom(_trader, address(this), _margin/_marginDecMultiplier);\n        IERC20(_marginAsset).approve(_stableVault, type(uint).max);\n        IStableVault(_stableVault).deposit(_marginAsset, _margin/_marginDecMultiplier);\n        if (tigAsset.balanceOf(address(this)) != _balBefore + _margin) revert BadDeposit();\n        tigAsset.burnFrom(address(this), tigAsset.balanceOf(address(this)));\n    } else {\n        tigAsset.burnFrom(_trader, _margin);\n    }        \n}\n```\n\nIf the StableVault contract is compromised or has vulnerabilities, an attacker could drain all approved tokens from the Trading contract. While the Trading contract should not hold tokens for extended periods (they should be immediately deposited or burnt), there is a window of vulnerability.\n\nA better approach would be to approve only the exact amount needed for the current operation (`_margin/_marginDecMultiplier`) instead of an unlimited amount.", "Recommendation": "", "Detector": "context_scan_default_claude-3-7-sonnet-20250219_1", "Mitigation": "This is a valid issue. Unlimited token approvals create unnecessary security risks.", "CounterArgument": null, "Justification": null, "index": 7}, {"Issue": "Insufficient proxy approval validation", "Severity": "Low", "Contracts": ["Trading.sol"], "Description": "The `approveProxy` function allows a user to designate another address as their proxy for trading operations, but lacks important validations for the proxy address and expiration timestamp.\n\n```solidity\nfunction approveProxy(address _proxy, uint256 _timestamp) external payable {\n    proxyApprovals[_msgSender()] = Proxy(\n        _proxy,\n        _timestamp\n    );\n    payable(_proxy).transfer(msg.value);\n}\n```\n\nThere are several issues with this implementation:\n\n1. No validation that `_proxy` is not the zero address\n2. No validation that `_timestamp` is in the future\n3. No upper bound on how far in the future `_timestamp` can be set\n4. No way to revoke proxy approval before the timestamp expires\n\nAdditionally, the function transfers any ETH sent with the transaction to the proxy address without any validation or maximum limit. This could lead to unintended asset transfers if a user accidentally sends ETH when approving a proxy.\n\nThese issues could lead to permanent or long-lasting proxy relationships that can't be revoked, potentially compromising user funds if a proxy address is compromised.", "Recommendation": "", "Detector": "context_scan_default_claude-3-7-sonnet-20250219_1", "Mitigation": "This is a valid issue. The inconsistent error handling makes the code harder to maintain and debug.", "CounterArgument": null, "Justification": null, "index": 8}, {"Issue": "Inconsistent error handling", "Severity": "Info", "Contracts": ["Trading.sol"], "Description": "The Trading contract uses a mix of different error handling approaches, which can make integration and debugging more difficult. In some places, it uses custom error types, in others it uses require statements with string messages, and in yet others it uses numeric error codes with comments.\n\n```solidity\n// Custom error types\nerror LimitNotSet(); //7\nerror NotLiquidatable();\nerror TradingPaused();\n\n// Later in the code, using require with string messages\nrequire(_proxy.proxy == _msgSender() && _proxy.time >= block.timestamp, \"Proxy not approved\");\n\n// Using numeric error codes\nif (_trade.orderType != 0) revert(\"4\"); //IsLimit\n```\n\nThis inconsistent approach to error handling has several drawbacks:\n\n1. Makes it harder for developers to handle errors consistently\n2. Increases gas costs in some cases (string error messages are more expensive than custom errors)\n3. Reduces code readability and maintainability\n4. Makes it difficult to document and understand all possible error conditions\n\nNumeric error codes like `revert(\"4\")` are particularly problematic as they require developers to have knowledge of what each code means, which is only documented in inline comments. If these comments are not kept in sync with the code, it becomes very difficult to understand error conditions.", "Recommendation": "", "Detector": "context_scan_default_claude-3-7-sonnet-20250219_1", "Mitigation": "This is a valid informational issue. Lack of slippage protection can lead to unexpected trade execution prices.", "CounterArgument": null, "Justification": null, "index": 9}, {"Issue": "Lack of slippage protection", "Severity": "Best Practices", "Contracts": ["Trading.sol"], "Description": "The trading functions in the contract, such as `initiateMarketOrder` and `initiateCloseOrder`, do not include any slippage protection mechanisms. This means users have no way to specify a maximum acceptable price slippage when executing trades.\n\n```solidity\nfunction initiateMarketOrder(\n    TradeInfo calldata _tradeInfo,\n    PriceData calldata _priceData,\n    bytes calldata _signature,\n    ERC20PermitData calldata _permitData,\n    address _trader\n)\n    external\n{\n    // ... validation and setup ...\n    uint256 _isLong = _tradeInfo.direction ? 1 : 2;\n    (uint256 _price,) = tradingExtension.getVerifiedPrice(_tradeInfo.asset, _priceData, _signature, _isLong);\n    // ... position creation ...\n}\n```\n\nIn this function, the price is obtained from the oracle and used directly without giving the user any control over the acceptable price range. This presents several risks:\n\n1. Front-running: Malicious actors could observe pending transactions and execute trades ahead of users if price movements would make it profitable.\n\n2. Unexpected price impact: During high volatility, prices can change rapidly between when a transaction is submitted and when it's executed.\n\n3. MEV attacks: The lack of slippage protection increases the attack surface for MEX (Maximal Extractable Value) exploitation.\n\nWithout slippage protection, users are exposed to potentially executing trades at prices much worse than expected, leading to financial losses.", "Recommendation": "", "Detector": "context_scan_default_claude-3-7-sonnet-20250219_1", "Mitigation": "This is a valid best practices issue. Excessive use of unchecked blocks increases the risk of silent arithmetic errors.", "CounterArgument": null, "Justification": null, "index": 10}, {"Issue": "Excessive unchecked blocks", "Severity": "Medium", "Contracts": ["Trading.sol", "Position.sol", "BondNFT.sol"], "Description": "The contracts make extensive use of `unchecked` blocks, which disable Solidity 0.8+'s built-in overflow and underflow checks. While this can save gas in certain scenarios, excessive use increases the risk of silent arithmetic errors.\n\nFor example, in Position.sol:\n\n```solidity\nfunction createLock(\n    address _asset,\n    uint _amount,\n    uint _period,\n    address _owner\n) external onlyManager() returns(uint id) {\n    require(allowedAsset[_asset], \"!Asset\");\n    unchecked {\n        uint shares = _amount * _period / 365;\n        uint expireEpoch = epoch[_asset] + _period;\n        id = ++totalBonds;\n        totalShares[_asset] += shares;\n        Bond memory _bond = Bond(\n            id,             // id\n            address(0),     // owner\n            _asset,         // tigAsset token\n            _amount,        // tigAsset amount\n            epoch[_asset],  // mint epoch\n            block.timestamp,// mint timestamp\n            expireEpoch,    // expire epoch\n            0,              // pending\n            shares,         // linearly scaling share of rewards\n            _period,        // lock period\n            false           // is expired boolean\n        );\n        _idToBond[id] = _bond;\n        _mint(_owner, _bond);\n    }\n    emit Lock(_asset, _amount, _period, _owner, id);\n}\n```\n\nIn this function, all arithmetic operations are within an `unchecked` block, including:\n- Multiplication and division for share calculation\n- Incrementing the total bonds counter\n- Adding shares to the total shares mapping\n\nWhile some of these operations may be safe from overflow given the expected ranges of inputs, wrapping entire function bodies in `unchecked` blocks is risky and makes the code more vulnerable to subtle bugs. Best practice would be to use `unchecked` blocks only around specific operations that have been proven safe from overflow/underflow.", "Recommendation": "", "Detector": "context_scan_default_claude-3-7-sonnet-20250219_1", "Mitigation": "This is a valid issue. The contract makes external calls without reentrancy protection, which could lead to vulnerabilities.", "CounterArgument": null, "Justification": null, "index": 11}]
```

---

## **Contract Code:**
```solidity
// File: PairsContract.sol
//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IPairsContract.sol";
import "./interfaces/IPosition.sol";

contract PairsContract is Ownable, IPairsContract {

    address public protocol;

    mapping(uint256 => bool) public allowedAsset;

    uint256 private maxBaseFundingRate = 1e10;

    mapping(uint256 => Asset) private _idToAsset;
    function idToAsset(uint256 _asset) public view returns (Asset memory) {
        return _idToAsset[_asset];
    }

    mapping(uint256 => mapping(address => OpenInterest)) private _idToOi;
    function idToOi(uint256 _asset, address _tigAsset) public view returns (OpenInterest memory) {
        return _idToOi[_asset][_tigAsset];
    }

    // OWNER

    /**
     * @dev Update the Chainlink price feed of an asset
     * @param _asset index of the requested asset
     * @param _feed contract address of the Chainlink price feed
     */
    function setAssetChainlinkFeed(uint256 _asset, address _feed) external onlyOwner {
        bytes memory _name  = bytes(_idToAsset[_asset].name);
        require(_name.length > 0, "!Asset");
        _idToAsset[_asset].chainlinkFeed = _feed;
    }

    /**
     * @dev Add an allowed asset to fetch prices for
     * @param _asset index of the requested asset
     * @param _name name of the asset
     * @param _chainlinkFeed optional address of the respective Chainlink price feed
     * @param _maxLeverage maximimum allowed leverage
     * @param _maxLeverage minimum allowed leverage
     * @param _feeMultiplier percent value that the opening/closing fee is multiplied by in BP
     */
    function addAsset(uint256 _asset, string memory _name, address _chainlinkFeed, uint256 _minLeverage, uint256 _maxLeverage, uint256 _feeMultiplier, uint256 _baseFundingRate) external onlyOwner {
        bytes memory _assetName  = bytes(_idToAsset[_asset].name);
        require(_assetName.length == 0, "Already exists");
        require(bytes(_name).length > 0, "No name");
        require(_maxLeverage >= _minLeverage && _minLeverage > 0, "Wrong leverage values");

        allowedAsset[_asset] = true;
        _idToAsset[_asset].name = _name;

        _idToAsset[_asset].chainlinkFeed = _chainlinkFeed;

        _idToAsset[_asset].minLeverage = _minLeverage;
        _idToAsset[_asset].maxLeverage = _maxLeverage;
        _idToAsset[_asset].feeMultiplier = _feeMultiplier;
        _idToAsset[_asset].baseFundingRate = _baseFundingRate;

        emit AssetAdded(_asset, _name);
    }

    /**
     * @dev Update the leverage allowed per asset
     * @param _asset index of the asset
     * @param _minLeverage minimum leverage allowed
     * @param _maxLeverage Maximum leverage allowed
     */
    function updateAssetLeverage(uint256 _asset, uint256 _minLeverage, uint256 _maxLeverage) external onlyOwner {
        bytes memory _name  = bytes(_idToAsset[_asset].name);
        require(_name.length > 0, "!Asset");

        if (_maxLeverage > 0) {
            _idToAsset[_asset].maxLeverage = _maxLeverage;
        }
        if (_minLeverage > 0) {
            _idToAsset[_asset].minLeverage = _minLeverage;
        }
        
        require(_idToAsset[_asset].maxLeverage >= _idToAsset[_asset].minLeverage, "Wrong leverage values");
    }

    /**
     * @notice update the base rate for funding fees per asset
     * @param _asset index of the asset
     * @param _baseFundingRate the rate to set
     */
    function setAssetBaseFundingRate(uint256 _asset, uint256 _baseFundingRate) external onlyOwner {
        bytes memory _name  = bytes(_idToAsset[_asset].name);
        require(_name.length > 0, "!Asset");
        require(_baseFundingRate <= maxBaseFundingRate, "baseFundingRate too high");
        _idToAsset[_asset].baseFundingRate = _baseFundingRate;
    }

    /**
     * @notice update the fee multiplier per asset
     * @param _asset index of the asset
     * @param _feeMultiplier the fee multiplier
     */
    function updateAssetFeeMultiplier(uint256 _asset, uint256 _feeMultiplier) external onlyOwner {
        bytes memory _name  = bytes(_idToAsset[_asset].name);
        require(_name.length > 0, "!Asset");
        _idToAsset[_asset].feeMultiplier = _feeMultiplier;
    }

     /**
     * @notice pause an asset from being traded
     * @param _asset index of the asset
     * @param _isPaused paused if true
     */
    function pauseAsset(uint256 _asset, bool _isPaused) external onlyOwner {
        bytes memory _name  = bytes(_idToAsset[_asset].name);
        require(_name.length > 0, "!Asset");
        allowedAsset[_asset] = !_isPaused;
    }

    /**
     * @notice sets the max rate for funding fees
     * @param _maxBaseFundingRate max base funding rate
     */
    function setMaxBaseFundingRate(uint256 _maxBaseFundingRate) external onlyOwner {
        maxBaseFundingRate = _maxBaseFundingRate;
    }

    function setProtocol(address _protocol) external onlyOwner {
        protocol = _protocol;
    }

    /**
     * @dev Update max open interest limits
     * @param _asset index of the asset
     * @param _tigAsset contract address of the tigAsset
     * @param _maxOi Maximum open interest value per side
     */
    function setMaxOi(uint256 _asset, address _tigAsset, uint256 _maxOi) external onlyOwner {
        bytes memory _name  = bytes(_idToAsset[_asset].name);
        require(_name.length > 0, "!Asset");
        _idToOi[_asset][_tigAsset].maxOi = _maxOi;
    }

    // Protocol-only

    /**
     * @dev edits the current open interest for long
     * @param _asset index of the asset
     * @param _tigAsset contract address of the tigAsset
     * @param _onOpen true if adding to open interesr
     * @param _amount amount to be added/removed from open interest
     */
    function modifyLongOi(uint256 _asset, address _tigAsset, bool _onOpen, uint256 _amount) external onlyProtocol {
        if (_onOpen) {
            _idToOi[_asset][_tigAsset].longOi += _amount;
            require(_idToOi[_asset][_tigAsset].longOi <= _idToOi[_asset][_tigAsset].maxOi || _idToOi[_asset][_tigAsset].maxOi == 0, "MaxLongOi");
        }
        else {
            _idToOi[_asset][_tigAsset].longOi -= _amount;
            if (_idToOi[_asset][_tigAsset].longOi < 1e9) {
                _idToOi[_asset][_tigAsset].longOi = 0;
            }
        }
    }

     /**
     * @dev edits the current open interest for short
     * @param _asset index of the asset
     * @param _tigAsset contract address of the tigAsset
     * @param _onOpen true if adding to open interesr
     * @param _amount amount to be added/removed from open interest
     */
    function modifyShortOi(uint256 _asset, address _tigAsset, bool _onOpen, uint256 _amount) external onlyProtocol {
        if (_onOpen) {
            _idToOi[_asset][_tigAsset].shortOi += _amount;
            require(_idToOi[_asset][_tigAsset].shortOi <= _idToOi[_asset][_tigAsset].maxOi || _idToOi[_asset][_tigAsset].maxOi == 0, "MaxShortOi");
            }
        else {
            _idToOi[_asset][_tigAsset].shortOi -= _amount;
            if (_idToOi[_asset][_tigAsset].shortOi < 1e9) {
                _idToOi[_asset][_tigAsset].shortOi = 0;
            }
        }
    }

    // Modifiers

    modifier onlyProtocol() {
        require(_msgSender() == address(protocol), "!Protocol");
        _;
    }

    // EVENTS

    event AssetAdded(
        uint _asset,
        string _name
    );

}

// File: Position.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./utils/MetaContext.sol";
import "./interfaces/IPosition.sol";

contract Position is ERC721Enumerable, MetaContext, IPosition {

    function ownerOf(uint _id) public view override(ERC721, IERC721, IPosition) returns (address) {
        return ERC721.ownerOf(_id);
    }

    using Counters for Counters.Counter;
    uint constant public DIVISION_CONSTANT = 1e10; // 100%

    mapping(uint => mapping(address => uint)) public vaultFundingPercent;

    mapping(address => bool) private _isMinter; // Trading contract should be minter
    mapping(uint256 => Trade) private _trades; // NFT id to Trade

    uint256[] private _openPositions;
    mapping(uint256 => uint256) private _openPositionsIndexes;

    mapping(uint256 => uint256[]) private _assetOpenPositions;
    mapping(uint256 => mapping(uint256 => uint256)) private _assetOpenPositionsIndexes;

    mapping(uint256 => uint256[]) private _limitOrders; // List of limit order nft ids per asset
    mapping(uint256 => mapping(uint256 => uint256)) private _limitOrderIndexes; // Keeps track of asset -> id -> array index

    // Funding
    mapping(uint256 => mapping(address => int256)) public fundingDeltaPerSec;
    mapping(uint256 => mapping(address => mapping(bool => int256))) private accInterestPerOi;
    mapping(uint256 => mapping(address => uint256)) private lastUpdate;
    mapping(uint256 => int256) private initId;
    mapping(uint256 => mapping(address => uint256)) private longOi;
    mapping(uint256 => mapping(address => uint256)) private shortOi;

    function isMinter(address _address) public view returns (bool) { return _isMinter[_address]; }
    function trades(uint _id) public view returns (Trade memory) {
        Trade memory _trade = _trades[_id];
        _trade.trader = ownerOf(_id);
        if (_trade.orderType > 0) return _trade;
        
        int256 _pendingFunding;
        if (_trade.direction && longOi[_trade.asset][_trade.tigAsset] > 0) {
            _pendingFunding = (int256(block.timestamp-lastUpdate[_trade.asset][_trade.tigAsset])*fundingDeltaPerSec[_trade.asset][_trade.tigAsset])*1e18/int256(longOi[_trade.asset][_trade.tigAsset]);
            if (longOi[_trade.asset][_trade.tigAsset] > shortOi[_trade.asset][_trade.tigAsset]) {
                _pendingFunding = -_pendingFunding;
            } else {
                _pendingFunding = _pendingFunding*int256(1e10-vaultFundingPercent[_trade.asset][_trade.tigAsset])/1e10;
            }
        } else if (shortOi[_trade.asset][_trade.tigAsset] > 0) {
            _pendingFunding = (int256(block.timestamp-lastUpdate[_trade.asset][_trade.tigAsset])*fundingDeltaPerSec[_trade.asset][_trade.tigAsset])*1e18/int256(shortOi[_trade.asset][_trade.tigAsset]);
            if (shortOi[_trade.asset][_trade.tigAsset] > longOi[_trade.asset][_trade.tigAsset]) {
                _pendingFunding = -_pendingFunding;
            } else {
                _pendingFunding = _pendingFunding*int256(1e10-vaultFundingPercent[_trade.asset][_trade.tigAsset])/1e10;
            }
        }
        _trade.accInterest += (int256(_trade.margin*_trade.leverage/1e18)*(accInterestPerOi[_trade.asset][_trade.tigAsset][_trade.direction]+_pendingFunding)/1e18)-initId[_id];
        
        return _trade;
    }
    function openPositions() public view returns (uint256[] memory) { return _openPositions; }
    function openPositionsIndexes(uint _id) public view returns (uint256) { return _openPositionsIndexes[_id]; }
    function assetOpenPositions(uint _asset) public view returns (uint256[] memory) { return _assetOpenPositions[_asset]; }
    function assetOpenPositionsIndexes(uint _asset, uint _id) public view returns (uint256) { return _assetOpenPositionsIndexes[_asset][_id]; }
    function limitOrders(uint _asset) public view returns (uint256[] memory) { return _limitOrders[_asset]; }
    function limitOrderIndexes(uint _asset, uint _id) public view returns (uint256) { return _limitOrderIndexes[_asset][_id]; }

    Counters.Counter private _tokenIds;
    string public baseURI;

    constructor(string memory _setBaseURI, string memory _name, string memory _symbol) ERC721(_name, _symbol) {
        baseURI = _setBaseURI;
        _tokenIds.increment();
    }

    function _baseURI() internal override view returns (string memory) {
        return baseURI;
    }

    function setBaseURI(string memory _newBaseURI) external onlyOwner {
        baseURI = _newBaseURI;
    }

    /**
    * @notice Update funding rate after open interest change
    * @dev only callable by minter
    * @param _asset pair id
    * @param _tigAsset tigAsset token address
    * @param _longOi long open interest
    * @param _shortOi short open interest
    * @param _baseFundingRate base funding rate of a pair
    * @param _vaultFundingPercent percent of earned funding going to the stablevault
    */
    function updateFunding(uint256 _asset, address _tigAsset, uint256 _longOi, uint256 _shortOi, uint256 _baseFundingRate, uint _vaultFundingPercent) external onlyMinter {
        if(longOi[_asset][_tigAsset] < shortOi[_asset][_tigAsset]) {
            if (longOi[_asset][_tigAsset] > 0) {
                accInterestPerOi[_asset][_tigAsset][true] += ((int256(block.timestamp-lastUpdate[_asset][_tigAsset])*fundingDeltaPerSec[_asset][_tigAsset])*1e18/int256(longOi[_asset][_tigAsset]))*int256(1e10-vaultFundingPercent[_asset][_tigAsset])/1e10;
            }
            accInterestPerOi[_asset][_tigAsset][false] -= (int256(block.timestamp-lastUpdate[_asset][_tigAsset])*fundingDeltaPerSec[_asset][_tigAsset])*1e18/int256(shortOi[_asset][_tigAsset]);

        } else if(longOi[_asset][_tigAsset] > shortOi[_asset][_tigAsset]) {
            accInterestPerOi[_asset][_tigAsset][true] -= (int256(block.timestamp-lastUpdate[_asset][_tigAsset])*fundingDeltaPerSec[_asset][_tigAsset])*1e18/int256(longOi[_asset][_tigAsset]);
            if (shortOi[_asset][_tigAsset] > 0) {
                accInterestPerOi[_asset][_tigAsset][false] += ((int256(block.timestamp-lastUpdate[_asset][_tigAsset])*fundingDeltaPerSec[_asset][_tigAsset])*1e18/int256(shortOi[_asset][_tigAsset]))*int256(1e10-vaultFundingPercent[_asset][_tigAsset])/1e10;
            }
        }
        lastUpdate[_asset][_tigAsset] = block.timestamp;
        int256 _oiDelta;
        if (_longOi > _shortOi) {
            _oiDelta = int256(_longOi)-int256(_shortOi);
        } else {
            _oiDelta = int256(_shortOi)-int256(_longOi);
        }
        
        fundingDeltaPerSec[_asset][_tigAsset] = (_oiDelta*int256(_baseFundingRate)/int256(DIVISION_CONSTANT))/31536000;
        longOi[_asset][_tigAsset] = _longOi;
        shortOi[_asset][_tigAsset] = _shortOi;
        vaultFundingPercent[_asset][_tigAsset] = _vaultFundingPercent;
    }

    /**
    * @notice mint a new position nft
    * @dev only callable by minter
    * @param _mintTrade New trade params in struct
    */
    function mint(
        MintTrade memory _mintTrade
    ) external onlyMinter {
        uint newTokenID = _tokenIds.current();

        Trade storage newTrade = _trades[newTokenID];
        newTrade.margin = _mintTrade.margin;
        newTrade.leverage = _mintTrade.leverage;
        newTrade.asset = _mintTrade.asset;
        newTrade.direction = _mintTrade.direction;
        newTrade.price = _mintTrade.price;
        newTrade.tpPrice = _mintTrade.tp;
        newTrade.slPrice = _mintTrade.sl;
        newTrade.orderType = _mintTrade.orderType;
        newTrade.id = newTokenID;
        newTrade.tigAsset = _mintTrade.tigAsset;

        _safeMint(_mintTrade.account, newTokenID);
        if (_mintTrade.orderType > 0) {
            _limitOrders[_mintTrade.asset].push(newTokenID);
            _limitOrderIndexes[_mintTrade.asset][newTokenID] = _limitOrders[_mintTrade.asset].length-1;
        } else {
            initId[newTokenID] = accInterestPerOi[_mintTrade.asset][_mintTrade.tigAsset][_mintTrade.direction]*int256(_mintTrade.margin*_mintTrade.leverage/1e18)/1e18;
            _openPositions.push(newTokenID);
            _openPositionsIndexes[newTokenID] = _openPositions.length-1;

            _assetOpenPositions[_mintTrade.asset].push(newTokenID);
            _assetOpenPositionsIndexes[_mintTrade.asset][newTokenID] = _assetOpenPositions[_mintTrade.asset].length-1;
        }
        _tokenIds.increment();
    }

    /**
     * @param _id id of the position NFT
     * @param _price price used for execution
     * @param _newMargin margin after fees
     */
    function executeLimitOrder(uint256 _id, uint256 _price, uint256 _newMargin) external onlyMinter {
        Trade storage _trade = _trades[_id];
        if (_trade.orderType == 0) {
            return;
        }
        _trade.orderType = 0;
        _trade.price = _price;
        _trade.margin = _newMargin;
        uint _asset = _trade.asset;
        _limitOrderIndexes[_asset][_limitOrders[_asset][_limitOrders[_asset].length-1]] = _limitOrderIndexes[_asset][_id];
        _limitOrders[_asset][_limitOrderIndexes[_asset][_id]] = _limitOrders[_asset][_limitOrders[_asset].length-1];
        delete _limitOrderIndexes[_asset][_id];
        _limitOrders[_asset].pop();

        _openPositions.push(_id);
        _openPositionsIndexes[_id] = _openPositions.length-1;
        _assetOpenPositions[_asset].push(_id);
        _assetOpenPositionsIndexes[_asset][_id] = _assetOpenPositions[_asset].length-1;

        initId[_id] = accInterestPerOi[_trade.asset][_trade.tigAsset][_trade.direction]*int256(_trade.margin*_trade.leverage/1e18)/1e18;
    }

    /**
    * @notice modifies margin and leverage
    * @dev only callable by minter
    * @param _id position id
    * @param _newMargin new margin amount
    * @param _newLeverage new leverage amount
    */
    function modifyMargin(uint256 _id, uint256 _newMargin, uint256 _newLeverage) external onlyMinter {
        _trades[_id].margin = _newMargin;
        _trades[_id].leverage = _newLeverage;
    }

    /**
    * @notice modifies margin and entry price
    * @dev only callable by minter
    * @param _id position id
    * @param _newMargin new margin amount
    * @param _newPrice new entry price
    */
    function addToPosition(uint256 _id, uint256 _newMargin, uint256 _newPrice) external onlyMinter {
        _trades[_id].margin = _newMargin;
        _trades[_id].price = _newPrice;
        initId[_id] = accInterestPerOi[_trades[_id].asset][_trades[_id].tigAsset][_trades[_id].direction]*int256(_newMargin*_trades[_id].leverage/1e18)/1e18;
    }

    /**
    * @notice Called before updateFunding for reducing position or adding to position, to store accumulated funding
    * @dev only callable by minter
    * @param _id position id
    */
    function setAccInterest(uint256 _id) external onlyMinter {
        _trades[_id].accInterest = trades(_id).accInterest;
    }

    /**
    * @notice Reduces position size by %
    * @dev only callable by minter
    * @param _id position id
    * @param _percent percent of a position being closed
    */
    function reducePosition(uint256 _id, uint256 _percent) external onlyMinter {
        _trades[_id].accInterest -= _trades[_id].accInterest*int256(_percent)/int256(DIVISION_CONSTANT);
        _trades[_id].margin -= _trades[_id].margin*_percent/DIVISION_CONSTANT;
        initId[_id] = accInterestPerOi[_trades[_id].asset][_trades[_id].tigAsset][_trades[_id].direction]*int256(_trades[_id].margin*_trades[_id].leverage/1e18)/1e18;
    }

    /**
    * @notice change a position tp price
    * @dev only callable by minter
    * @param _id position id
    * @param _tpPrice tp price
    */
    function modifyTp(uint _id, uint _tpPrice) external onlyMinter {
        _trades[_id].tpPrice = _tpPrice;
    }

    /**
    * @notice change a position sl price
    * @dev only callable by minter
    * @param _id position id
    * @param _slPrice sl price
    */
    function modifySl(uint _id, uint _slPrice) external onlyMinter {
        _trades[_id].slPrice = _slPrice;
    }

    /**
    * @dev Burns an NFT and it's data
    * @param _id ID of the trade
    */
    function burn(uint _id) external onlyMinter {
        _burn(_id);
        uint _asset = _trades[_id].asset;
        if (_trades[_id].orderType > 0) {
            _limitOrderIndexes[_asset][_limitOrders[_asset][_limitOrders[_asset].length-1]] = _limitOrderIndexes[_asset][_id];
            _limitOrders[_asset][_limitOrderIndexes[_asset][_id]] = _limitOrders[_asset][_limitOrders[_asset].length-1];
            delete _limitOrderIndexes[_asset][_id];
            _limitOrders[_asset].pop();            
        } else {
            _assetOpenPositionsIndexes[_asset][_assetOpenPositions[_asset][_assetOpenPositions[_asset].length-1]] = _assetOpenPositionsIndexes[_asset][_id];
            _assetOpenPositions[_asset][_assetOpenPositionsIndexes[_asset][_id]] = _assetOpenPositions[_asset][_assetOpenPositions[_asset].length-1];
            delete _assetOpenPositionsIndexes[_asset][_id];
            _assetOpenPositions[_asset].pop();  

            _openPositionsIndexes[_openPositions[_openPositions.length-1]] = _openPositionsIndexes[_id];
            _openPositions[_openPositionsIndexes[_id]] = _openPositions[_openPositions.length-1];
            delete _openPositionsIndexes[_id];
            _openPositions.pop();              
        }
        delete _trades[_id];
    }

    function assetOpenPositionsLength(uint _asset) external view returns (uint256) {
        return _assetOpenPositions[_asset].length;
    }

    function limitOrdersLength(uint _asset) external view returns (uint256) {
        return _limitOrders[_asset].length;
    }

    function getCount() external view returns (uint) {
        return _tokenIds.current();
    }

    function userTrades(address _user) external view returns (uint[] memory) {
        uint[] memory _ids = new uint[](balanceOf(_user));
        for (uint i=0; i<_ids.length; i++) {
            _ids[i] = tokenOfOwnerByIndex(_user, i);
        }
        return _ids;
    }

    function openPositionsSelection(uint _from, uint _to) external view returns (uint[] memory) {
        uint[] memory _ids = new uint[](_to-_from);
        for (uint i=0; i<_ids.length; i++) {
            _ids[i] = _openPositions[i+_from];
        }
        return _ids;
    }

    function setMinter(address _minter, bool _bool) external onlyOwner {
        _isMinter[_minter] = _bool;
    }    

    modifier onlyMinter() {
        require(_isMinter[_msgSender()], "!Minter");
        _;
    }

    // META-TX
    function _msgSender() internal view override(Context, MetaContext) returns (address sender) {
        return MetaContext._msgSender();
    }
    function _msgData() internal view override(Context, MetaContext) returns (bytes calldata) {
        return MetaContext._msgData();
    }
}

// File: Trading.sol
//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./utils/MetaContext.sol";
import "./interfaces/ITrading.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IPairsContract.sol";
import "./interfaces/IReferrals.sol";
import "./interfaces/IPosition.sol";
import "./interfaces/IGovNFT.sol";
import "./interfaces/IStableVault.sol";
import "./utils/TradingLibrary.sol";

interface ITradingExtension {
    function getVerifiedPrice(
        uint _asset,
        PriceData calldata _priceData,
        bytes calldata _signature,
        uint _withSpreadIsLong
    ) external returns(uint256 _price, uint256 _spread);
    function getRef(
        address _trader
    ) external pure returns(address);
    function _setReferral(
        bytes32 _referral,
        address _trader
    ) external;
    function validateTrade(uint _asset, address _tigAsset, uint _margin, uint _leverage) external view;
    function isPaused() external view returns(bool);
    function minPos(address) external view returns(uint);
    function modifyLongOi(
        uint _asset,
        address _tigAsset,
        bool _onOpen,
        uint _size
    ) external;
    function modifyShortOi(
        uint _asset,
        address _tigAsset,
        bool _onOpen,
        uint _size
    ) external;
    function paused() external returns(bool);
    function _limitClose(
        uint _id,
        bool _tp,
        PriceData calldata _priceData,
        bytes calldata _signature
    ) external returns(uint _limitPrice, address _tigAsset);
    function _checkGas() external view;
    function _closePosition(
        uint _id,
        uint _price,
        uint _percent
    ) external returns (IPosition.Trade memory _trade, uint256 _positionSize, int256 _payout);
}

interface IStable is IERC20 {
    function burnFrom(address account, uint amount) external;
    function mintFor(address account, uint amount) external;
}

interface ExtendedIERC20 is IERC20 {
    function decimals() external view returns (uint);
}

interface ERC20Permit is IERC20 {
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

contract Trading is MetaContext, ITrading {

    error LimitNotSet(); //7
    error NotLiquidatable();
    error TradingPaused();
    error BadDeposit();
    error BadWithdraw();
    error ValueNotEqualToMargin();
    error BadLeverage();
    error NotMargin();
    error NotAllowedPair();
    error BelowMinPositionSize();
    error BadClosePercent();
    error NoPrice();
    error LiqThreshold();

    uint constant private DIVISION_CONSTANT = 1e10; // 100%
    uint private constant liqPercent = 9e9; // 90%

    struct Fees {
        uint daoFees;
        uint burnFees;
        uint referralFees;
        uint botFees;
    }
    Fees public openFees = Fees(
        0,
        0,
        0,
        0
    );
    Fees public closeFees = Fees(
        0,
        0,
        0,
        0
    );
    uint public limitOrderPriceRange = 1e8; // 1%

    uint public maxWinPercent;
    uint public vaultFundingPercent;

    IPairsContract private pairsContract;
    IPosition private position;
    IGovNFT private gov;
    ITradingExtension private tradingExtension;

    struct Delay {
        uint delay; // Block number where delay ends
        bool actionType; // True for open, False for close
    }
    mapping(uint => Delay) public blockDelayPassed; // id => Delay
    uint public blockDelay;
    mapping(uint => uint) public limitDelay; // id => block.timestamp

    mapping(address => bool) public allowedVault;

    struct Proxy {
        address proxy;
        uint256 time;
    }

    mapping(address => Proxy) public proxyApprovals;

    constructor(
        address _position,
        address _gov,
        address _pairsContract
    )
    {
        position = IPosition(_position);
        gov = IGovNFT(_gov);
        pairsContract = IPairsContract(_pairsContract);
    }

    // ===== END-USER FUNCTIONS =====

    /**
     * @param _tradeInfo Trade info
     * @param _priceData verifiable off-chain price data
     * @param _signature node signature
     * @param _permitData data and signature needed for token approval
     * @param _trader address the trade is initiated for
     */
    function initiateMarketOrder(
        TradeInfo calldata _tradeInfo,
        PriceData calldata _priceData,
        bytes calldata _signature,
        ERC20PermitData calldata _permitData,
        address _trader
    )
        external
    {
        _validateProxy(_trader);
        _checkDelay(position.getCount(), true);
        _checkVault(_tradeInfo.stableVault, _tradeInfo.marginAsset);
        address _tigAsset = IStableVault(_tradeInfo.stableVault).stable();
        tradingExtension.validateTrade(_tradeInfo.asset, _tigAsset, _tradeInfo.margin, _tradeInfo.leverage);
        tradingExtension._setReferral(_tradeInfo.referral, _trader);
        uint256 _marginAfterFees = _tradeInfo.margin - _handleOpenFees(_tradeInfo.asset, _tradeInfo.margin*_tradeInfo.leverage/1e18, _trader, _tigAsset, false);
        uint256 _positionSize = _marginAfterFees * _tradeInfo.leverage / 1e18;
        _handleDeposit(_tigAsset, _tradeInfo.marginAsset, _tradeInfo.margin, _tradeInfo.stableVault, _permitData, _trader);
        uint256 _isLong = _tradeInfo.direction ? 1 : 2;
        (uint256 _price,) = tradingExtension.getVerifiedPrice(_tradeInfo.asset, _priceData, _signature, _isLong);
        IPosition.MintTrade memory _mintTrade = IPosition.MintTrade(
            _trader,
            _marginAfterFees,
            _tradeInfo.leverage,
            _tradeInfo.asset,
            _tradeInfo.direction,
            _price,
            _tradeInfo.tpPrice,
            _tradeInfo.slPrice,
            0,
            _tigAsset
        );
        _checkSl(_tradeInfo.slPrice, _tradeInfo.direction, _price);
        unchecked {
            if (_tradeInfo.direction) {
                tradingExtension.modifyLongOi(_tradeInfo.asset, _tigAsset, true, _positionSize);
            } else {
                tradingExtension.modifyShortOi(_tradeInfo.asset, _tigAsset, true, _positionSize);
            }
        }
        _updateFunding(_tradeInfo.asset, _tigAsset);
        position.mint(
            _mintTrade
        );
        unchecked {
            emit PositionOpened(_tradeInfo, 0, _price, position.getCount()-1, _trader, _marginAfterFees);
        }   
    }

    /**
     * @dev initiate closing position
     * @param _id id of the position NFT
     * @param _percent percent of the position being closed in BP
     * @param _priceData verifiable off-chain price data
     * @param _signature node signature
     * @param _stableVault StableVault address
     * @param _outputToken Token received upon closing trade
     * @param _trader address the trade is initiated for
     */
    function initiateCloseOrder(
        uint _id,
        uint _percent,
        PriceData calldata _priceData,
        bytes calldata _signature,
        address _stableVault,
        address _outputToken,
        address _trader
    )
        external
    {
        _validateProxy(_trader);
        _checkDelay(_id, false);
        _checkOwner(_id, _trader);
        _checkVault(_stableVault, _outputToken);
        IPosition.Trade memory _trade = position.trades(_id);
        if (_trade.orderType != 0) revert("4"); //IsLimit        
        (uint256 _price,) = tradingExtension.getVerifiedPrice(_trade.asset, _priceData, _signature, 0);

        if (_percent > DIVISION_CONSTANT || _percent == 0) revert BadClosePercent();
        _closePosition(_id, _percent, _price, _stableVault, _outputToken, false); 
    }

    /**
     * @param _id position id
     * @param _addMargin margin amount used to add to the position
     * @param _priceData verifiable off-chain price data
     * @param _signature node signature
     * @param _stableVault StableVault address
     * @param _marginAsset Token being used to add to the position
     * @param _permitData data and signature needed for token approval
     * @param _trader address the trade is initiated for
     */
    function addToPosition(
        uint _id,
        uint _addMargin,
        PriceData calldata _priceData,
        bytes calldata _signature,
        address _stableVault,
        address _marginAsset,
        ERC20PermitData calldata _permitData,
        address _trader
    )
        external
    {
        _validateProxy(_trader);
        _checkOwner(_id, _trader);
        _checkDelay(_id, true);
        IPosition.Trade memory _trade = position.trades(_id);
        tradingExtension.validateTrade(_trade.asset, _trade.tigAsset, _trade.margin + _addMargin, _trade.leverage);
        _checkVault(_stableVault, _marginAsset);
        if (_trade.orderType != 0) revert("4"); //IsLimit
        uint _fee = _handleOpenFees(_trade.asset, _addMargin*_trade.leverage/1e18, _trader, _trade.tigAsset, false);
        _handleDeposit(
            _trade.tigAsset,
            _marginAsset,
            _addMargin - _fee,
            _stableVault,
            _permitData,
            _trader
        );
        position.setAccInterest(_id);
        unchecked {
            (uint256 _price,) = tradingExtension.getVerifiedPrice(_trade.asset, _priceData, _signature, _trade.direction ? 1 : 2);
            uint _positionSize = (_addMargin - _fee) * _trade.leverage / 1e18;
            if (_trade.direction) {
                tradingExtension.modifyLongOi(_trade.asset, _trade.tigAsset, true, _positionSize);
            } else {
                tradingExtension.modifyShortOi(_trade.asset, _trade.tigAsset, true, _positionSize);     
            }
            _updateFunding(_trade.asset, _trade.tigAsset);
            _addMargin -= _fee;
            uint _newMargin = _trade.margin + _addMargin;
            uint _newPrice = _trade.price*_trade.margin/_newMargin + _price*_addMargin/_newMargin;

            position.addToPosition(
                _trade.id,
                _newMargin,
                _newPrice
            );
            
            emit AddToPosition(_trade.id, _newMargin, _newPrice, _trade.trader);
        }
    }

    /**
     * @param _tradeInfo Trade info
     * @param _orderType type of limit order used to open the position
     * @param _price limit price
     * @param _permitData data and signature needed for token approval
     * @param _trader address the trade is initiated for
     */
    function initiateLimitOrder(
        TradeInfo calldata _tradeInfo,
        uint256 _orderType, // 1 limit, 2 stop
        uint256 _price,
        ERC20PermitData calldata _permitData,
        address _trader
    )
        external
    {
        _validateProxy(_trader);
        address _tigAsset = IStableVault(_tradeInfo.stableVault).stable();
        tradingExtension.validateTrade(_tradeInfo.asset, _tigAsset, _tradeInfo.margin, _tradeInfo.leverage);
        _checkVault(_tradeInfo.stableVault, _tradeInfo.marginAsset);
        if (_orderType == 0) revert("5");
        if (_price == 0) revert NoPrice();
        tradingExtension._setReferral(_tradeInfo.referral, _trader);
        _handleDeposit(_tigAsset, _tradeInfo.marginAsset, _tradeInfo.margin, _tradeInfo.stableVault, _permitData, _trader);
        _checkSl(_tradeInfo.slPrice, _tradeInfo.direction, _price);
        uint256 _id = position.getCount();
        position.mint(
            IPosition.MintTrade(
                _trader,
                _tradeInfo.margin,
                _tradeInfo.leverage,
                _tradeInfo.asset,
                _tradeInfo.direction,
                _price,
                _tradeInfo.tpPrice,
                _tradeInfo.slPrice,
                _orderType,
                _tigAsset
            )
        );
        limitDelay[_id] = block.timestamp + 4;
        emit PositionOpened(_tradeInfo, _orderType, _price, _id, _trader, _tradeInfo.margin);
    }

    /**
     * @param _id position ID
     * @param _trader address the trade is initiated for
     */
    function cancelLimitOrder(
        uint256 _id,
        address _trader
    )
        external
    {
        _validateProxy(_trader);
        _checkOwner(_id, _trader);
        IPosition.Trade memory _trade = position.trades(_id);
        if (_trade.orderType == 0) revert();
        IStable(_trade.tigAsset).mintFor(_trader, _trade.margin);
        position.burn(_id);
        emit LimitCancelled(_id, _trader);
    }

    /**
     * @param _id position id
     * @param _marginAsset Token being used to add to the position
     * @param _stableVault StableVault address
     * @param _addMargin margin amount being added to the position
     * @param _permitData data and signature needed for token approval
     * @param _trader address the trade is initiated for
     */
    function addMargin(
        uint256 _id,
        address _marginAsset,
        address _stableVault,
        uint256 _addMargin,
        ERC20PermitData calldata _permitData,
        address _trader
    )
        external
    {
        _validateProxy(_trader);
        _checkOwner(_id, _trader);
        _checkVault(_stableVault, _marginAsset);
        IPosition.Trade memory _trade = position.trades(_id);
        if (_trade.orderType != 0) revert(); //IsLimit
        IPairsContract.Asset memory asset = pairsContract.idToAsset(_trade.asset);
        _handleDeposit(_trade.tigAsset, _marginAsset, _addMargin, _stableVault, _permitData, _trader);
        unchecked {
            uint256 _newMargin = _trade.margin + _addMargin;
            uint256 _newLeverage = _trade.margin * _trade.leverage / _newMargin;
            if (_newLeverage < asset.minLeverage) revert("!lev");
            position.modifyMargin(_id, _newMargin, _newLeverage);
            emit MarginModified(_id, _newMargin, _newLeverage, true, _trader);
        }
    }

    /**
     * @param _id position id
     * @param _stableVault StableVault address
     * @param _outputToken token the trader will receive
     * @param _removeMargin margin amount being removed from the position
     * @param _priceData verifiable off-chain price data
     * @param _signature node signature
     * @param _trader address the trade is initiated for
     */
    function removeMargin(
        uint256 _id,
        address _stableVault,
        address _outputToken,
        uint256 _removeMargin,
        PriceData calldata _priceData,
        bytes calldata _signature,
        address _trader
    )
        external
    {
        _validateProxy(_trader);
        _checkOwner(_id, _trader);
        _checkVault(_stableVault, _outputToken);
        IPosition.Trade memory _trade = position.trades(_id);
        if (_trade.orderType != 0) revert(); //IsLimit
        IPairsContract.Asset memory asset = pairsContract.idToAsset(_trade.asset);
        uint256 _newMargin = _trade.margin - _removeMargin;
        uint256 _newLeverage = _trade.margin * _trade.leverage / _newMargin;
        if (_newLeverage > asset.maxLeverage) revert("!lev");
        (uint _assetPrice,) = tradingExtension.getVerifiedPrice(_trade.asset, _priceData, _signature, 0);
        (,int256 _payout) = TradingLibrary.pnl(_trade.direction, _assetPrice, _trade.price, _newMargin, _newLeverage, _trade.accInterest);
        unchecked {
            if (_payout <= int256(_newMargin*(DIVISION_CONSTANT-liqPercent)/DIVISION_CONSTANT)) revert LiqThreshold();
        }
        position.modifyMargin(_trade.id, _newMargin, _newLeverage);
        _handleWithdraw(_trade, _stableVault, _outputToken, _removeMargin);
        emit MarginModified(_trade.id, _newMargin, _newLeverage, false, _trader);
    }

    /**
     * @param _type true for TP, false for SL
     * @param _id position id
     * @param _limitPrice TP/SL trigger price
     * @param _priceData verifiable off-chain price data
     * @param _signature node signature
     * @param _trader address the trade is initiated for
     */
    function updateTpSl(
        bool _type,
        uint _id,
        uint _limitPrice,
        PriceData calldata _priceData,
        bytes calldata _signature,
        address _trader
    )
        external
    {
        _validateProxy(_trader);
        _checkOwner(_id, _trader);
        IPosition.Trade memory _trade = position.trades(_id);
        if (_trade.orderType != 0) revert("4"); //IsLimit
        if (_type) {
            position.modifyTp(_id, _limitPrice);
        } else {
            (uint256 _price,) = tradingExtension.getVerifiedPrice(_trade.asset, _priceData, _signature, 0);
            _checkSl(_limitPrice, _trade.direction, _price);
            position.modifySl(_id, _limitPrice);
        }
        emit UpdateTPSL(_id, _type, _limitPrice, _trader);
    }

    /**
     * @param _id position id
     * @param _priceData verifiable off-chain price data
     * @param _signature node signature
     */
    function executeLimitOrder(
        uint _id, 
        PriceData calldata _priceData,
        bytes calldata _signature
    ) 
        external
    {
        unchecked {
            _checkDelay(_id, true);
            tradingExtension._checkGas();
            if (tradingExtension.paused()) revert TradingPaused();
            require(block.timestamp >= limitDelay[_id]);
            IPosition.Trade memory trade = position.trades(_id);
            uint _fee = _handleOpenFees(trade.asset, trade.margin*trade.leverage/1e18, trade.trader, trade.tigAsset, true);
            (uint256 _price, uint256 _spread) = tradingExtension.getVerifiedPrice(trade.asset, _priceData, _signature, 0);
            if (trade.orderType == 0) revert("5");
            if (_price > trade.price+trade.price*limitOrderPriceRange/DIVISION_CONSTANT || _price < trade.price-trade.price*limitOrderPriceRange/DIVISION_CONSTANT) revert("6"); //LimitNotMet
            if (trade.direction && trade.orderType == 1) {
                if (trade.price < _price) revert("6"); //LimitNotMet
            } else if (!trade.direction && trade.orderType == 1) {
                if (trade.price > _price) revert("6"); //LimitNotMet
            } else if (!trade.direction && trade.orderType == 2) {
                if (trade.price < _price) revert("6"); //LimitNotMet
                trade.price = _price;
            } else {
                if (trade.price > _price) revert("6"); //LimitNotMet
                trade.price = _price;
            } 
            if(trade.direction) {
                trade.price += trade.price * _spread / DIVISION_CONSTANT;
            } else {
                trade.price -= trade.price * _spread / DIVISION_CONSTANT;
            }
            if (trade.direction) {
                tradingExtension.modifyLongOi(trade.asset, trade.tigAsset, true, trade.margin*trade.leverage/1e18);
            } else {
                tradingExtension.modifyShortOi(trade.asset, trade.tigAsset, true, trade.margin*trade.leverage/1e18);
            }
            _updateFunding(trade.asset, trade.tigAsset);
            position.executeLimitOrder(_id, trade.price, trade.margin - _fee);
            emit LimitOrderExecuted(trade.asset, trade.direction, trade.price, trade.leverage, trade.margin - _fee, _id, trade.trader, _msgSender());
        }
    }

    /**
     * @notice liquidate position
     * @param _id id of the position NFT
     * @param _priceData verifiable off-chain data
     * @param _signature node signature
     */
    function liquidatePosition(
        uint _id,
        PriceData calldata _priceData,
        bytes calldata _signature
    )
        external
    {
        unchecked {
            tradingExtension._checkGas();
            IPosition.Trade memory _trade = position.trades(_id);
            if (_trade.orderType != 0) revert("4"); //IsLimit

            (uint256 _price,) = tradingExtension.getVerifiedPrice(_trade.asset, _priceData, _signature, 0);
            (uint256 _positionSizeAfterPrice, int256 _payout) = TradingLibrary.pnl(_trade.direction, _price, _trade.price, _trade.margin, _trade.leverage, _trade.accInterest);
            uint256 _positionSize = _trade.margin*_trade.leverage/1e18;
            if (_payout > int256(_trade.margin*(DIVISION_CONSTANT-liqPercent)/DIVISION_CONSTANT)) revert NotLiquidatable();
            if (_trade.direction) {
                tradingExtension.modifyLongOi(_trade.asset, _trade.tigAsset, false, _positionSize);
            } else {
                tradingExtension.modifyShortOi(_trade.asset, _trade.tigAsset, false, _positionSize);
            }
            _updateFunding(_trade.asset, _trade.tigAsset);
            _handleCloseFees(_trade.asset, type(uint).max, _trade.tigAsset, _positionSizeAfterPrice, _trade.trader, true);
            position.burn(_id);
            emit PositionLiquidated(_id, _trade.trader, _msgSender());
        }
    }

    /**
     * @dev close position at a pre-set price
     * @param _id id of the position NFT
     * @param _tp true if take profit
     * @param _priceData verifiable off-chain price data
     * @param _signature node signature
     */
    function limitClose(
        uint _id,
        bool _tp,
        PriceData calldata _priceData,
        bytes calldata _signature
    )
        external
    {
        _checkDelay(_id, false);
        (uint _limitPrice, address _tigAsset) = tradingExtension._limitClose(_id, _tp, _priceData, _signature);
        _closePosition(_id, DIVISION_CONSTANT, _limitPrice, address(0), _tigAsset, true);
    }

    /**
     * @notice Trader can approve a proxy wallet address for it to trade on its behalf. Can also provide proxy wallet with gas.
     * @param _proxy proxy wallet address
     * @param _timestamp end timestamp of approval period
     */
    function approveProxy(address _proxy, uint256 _timestamp) external payable {
        proxyApprovals[_msgSender()] = Proxy(
            _proxy,
            _timestamp
        );
        payable(_proxy).transfer(msg.value);
    }

    // ===== INTERNAL FUNCTIONS =====

    /**
     * @dev close the initiated position.
     * @param _id id of the position NFT
     * @param _percent percent of the position being closed
     * @param _price pair price
     * @param _stableVault StableVault address
     * @param _outputToken Token that trader will receive
     * @param _isBot false if closed via market order
     */
    function _closePosition(
        uint _id,
        uint _percent,
        uint _price,
        address _stableVault,
        address _outputToken,
        bool _isBot
    )
        internal
    {
        (IPosition.Trade memory _trade, uint256 _positionSize, int256 _payout) = tradingExtension._closePosition(_id, _price, _percent);
        position.setAccInterest(_id);
        _updateFunding(_trade.asset, _trade.tigAsset);
        if (_percent < DIVISION_CONSTANT) {
            if ((_trade.margin*_trade.leverage*(DIVISION_CONSTANT-_percent)/DIVISION_CONSTANT)/1e18 < tradingExtension.minPos(_trade.tigAsset)) revert("!size");
            position.reducePosition(_id, _percent);
        } else {
            position.burn(_id);
        }
        uint256 _toMint;
        if (_payout > 0) {
            unchecked {
                _toMint = _handleCloseFees(_trade.asset, uint256(_payout)*_percent/DIVISION_CONSTANT, _trade.tigAsset, _positionSize*_percent/DIVISION_CONSTANT, _trade.trader, _isBot);
                if (maxWinPercent > 0 && _toMint > _trade.margin*maxWinPercent/DIVISION_CONSTANT) {
                    _toMint = _trade.margin*maxWinPercent/DIVISION_CONSTANT;
                }
            }
            _handleWithdraw(_trade, _stableVault, _outputToken, _toMint);
        }
        emit PositionClosed(_id, _price, _percent, _toMint, _trade.trader, _isBot ? _msgSender() : _trade.trader);
    }

    /**
     * @dev handle stablevault deposits for different trading functions
     * @param _tigAsset tigAsset token address
     * @param _marginAsset token being deposited into stablevault
     * @param _margin amount being deposited
     * @param _stableVault StableVault address
     * @param _permitData Data for approval via permit
     * @param _trader Trader address to take tokens from
     */
    function _handleDeposit(address _tigAsset, address _marginAsset, uint256 _margin, address _stableVault, ERC20PermitData calldata _permitData, address _trader) internal {
        IStable tigAsset = IStable(_tigAsset);
        if (_tigAsset != _marginAsset) {
            if (_permitData.usePermit) {
                ERC20Permit(_marginAsset).permit(_trader, address(this), _permitData.amount, _permitData.deadline, _permitData.v, _permitData.r, _permitData.s);
            }
            uint256 _balBefore = tigAsset.balanceOf(address(this));
            uint _marginDecMultiplier = 10**(18-ExtendedIERC20(_marginAsset).decimals());
            IERC20(_marginAsset).transferFrom(_trader, address(this), _margin/_marginDecMultiplier);
            IERC20(_marginAsset).approve(_stableVault, type(uint).max);
            IStableVault(_stableVault).deposit(_marginAsset, _margin/_marginDecMultiplier);
            if (tigAsset.balanceOf(address(this)) != _balBefore + _margin) revert BadDeposit();
            tigAsset.burnFrom(address(this), tigAsset.balanceOf(address(this)));
        } else {
            tigAsset.burnFrom(_trader, _margin);
        }        
    }

    /**
     * @dev handle stablevault withdrawals for different trading functions
     * @param _trade Position info
     * @param _stableVault StableVault address
     * @param _outputToken Output token address
     * @param _toMint Amount of tigAsset minted to be used for withdrawal
     */
    function _handleWithdraw(IPosition.Trade memory _trade, address _stableVault, address _outputToken, uint _toMint) internal {
        IStable(_trade.tigAsset).mintFor(address(this), _toMint);
        if (_outputToken == _trade.tigAsset) {
            IERC20(_outputToken).transfer(_trade.trader, _toMint);
        } else {
            uint256 _balBefore = IERC20(_outputToken).balanceOf(address(this));
            IStableVault(_stableVault).withdraw(_outputToken, _toMint);
            if (IERC20(_outputToken).balanceOf(address(this)) != _balBefore + _toMint/(10**(18-ExtendedIERC20(_outputToken).decimals()))) revert BadWithdraw();
            IERC20(_outputToken).transfer(_trade.trader, IERC20(_outputToken).balanceOf(address(this)) - _balBefore);
        }        
    }

    /**
     * @dev handle fees distribution for opening
     * @param _asset asset id
     * @param _positionSize position size
     * @param _trader trader address
     * @param _tigAsset tigAsset address
     * @param _isBot false if opened via market order
     * @return _feePaid total fees paid during opening
     */
    function _handleOpenFees(
        uint _asset,
        uint _positionSize,
        address _trader,
        address _tigAsset,
        bool _isBot
    )
        internal
        returns (uint _feePaid)
    {
        IPairsContract.Asset memory asset = pairsContract.idToAsset(_asset);
        Fees memory _fees = openFees;
        unchecked {
            _fees.daoFees = _fees.daoFees * asset.feeMultiplier / DIVISION_CONSTANT;
            _fees.burnFees = _fees.burnFees * asset.feeMultiplier / DIVISION_CONSTANT;
            _fees.referralFees = _fees.referralFees * asset.feeMultiplier / DIVISION_CONSTANT;
            _fees.botFees = _fees.botFees * asset.feeMultiplier / DIVISION_CONSTANT;
        }
        address _referrer = tradingExtension.getRef(_trader); //referrals.getReferral(referrals.getReferred(_trader));
        if (_referrer != address(0)) {
            unchecked {
                IStable(_tigAsset).mintFor(
                    _referrer,
                    _positionSize
                    * _fees.referralFees // get referral fee%
                    / DIVISION_CONSTANT // divide by 100%
                );
            }
            _fees.daoFees = _fees.daoFees - _fees.referralFees*2;
        }
        if (_isBot) {
            unchecked {
                IStable(_tigAsset).mintFor(
                    _msgSender(),
                    _positionSize
                    * _fees.botFees // get bot fee%
                    / DIVISION_CONSTANT // divide by 100%
                );
            }
            _fees.daoFees = _fees.daoFees - _fees.botFees;
        } else {
            _fees.botFees = 0;
        }
        unchecked {
            uint _daoFeesPaid = _positionSize * _fees.daoFees / DIVISION_CONSTANT;
            _feePaid =
                _positionSize
                * (_fees.burnFees + _fees.botFees) // get total fee%
                / DIVISION_CONSTANT // divide by 100%
                + _daoFeesPaid;
            emit FeesDistributed(
                _tigAsset,
                _daoFeesPaid,
                _positionSize * _fees.burnFees / DIVISION_CONSTANT,
                _referrer != address(0) ? _positionSize * _fees.referralFees / DIVISION_CONSTANT : 0,
                _positionSize * _fees.botFees / DIVISION_CONSTANT,
                _referrer
            );
            IStable(_tigAsset).mintFor(address(this), _daoFeesPaid);
        }
        gov.distribute(_tigAsset, IStable(_tigAsset).balanceOf(address(this)));
    }

    /**
     * @dev handle fees distribution for closing
     * @param _asset asset id
     * @param _payout payout to trader before fees
     * @param _tigAsset margin asset
     * @param _positionSize position size
     * @param _trader trader address
     * @param _isBot false if closed via market order
     * @return payout_ payout to trader after fees
     */
    function _handleCloseFees(
        uint _asset,
        uint _payout,
        address _tigAsset,
        uint _positionSize,
        address _trader,
        bool _isBot
    )
        internal
        returns (uint payout_)
    {
        IPairsContract.Asset memory asset = pairsContract.idToAsset(_asset);
        Fees memory _fees = closeFees;
        uint _daoFeesPaid;
        uint _burnFeesPaid;
        uint _referralFeesPaid;
        unchecked {
            _daoFeesPaid = (_positionSize*_fees.daoFees/DIVISION_CONSTANT)*asset.feeMultiplier/DIVISION_CONSTANT;
            _burnFeesPaid = (_positionSize*_fees.burnFees/DIVISION_CONSTANT)*asset.feeMultiplier/DIVISION_CONSTANT;
        }
        uint _botFeesPaid;
        address _referrer = tradingExtension.getRef(_trader);//referrals.getReferral(referrals.getReferred(_trader));
        if (_referrer != address(0)) {
            unchecked {
                _referralFeesPaid = (_positionSize*_fees.referralFees/DIVISION_CONSTANT)*asset.feeMultiplier/DIVISION_CONSTANT;
            }
            IStable(_tigAsset).mintFor(
                _referrer,
                _referralFeesPaid
            );
             _daoFeesPaid = _daoFeesPaid-_referralFeesPaid*2;
        }
        if (_isBot) {
            unchecked {
                _botFeesPaid = (_positionSize*_fees.botFees/DIVISION_CONSTANT)*asset.feeMultiplier/DIVISION_CONSTANT;
                IStable(_tigAsset).mintFor(
                    _msgSender(),
                    _botFeesPaid
                );
            }
            _daoFeesPaid = _daoFeesPaid - _botFeesPaid;
        }
        emit FeesDistributed(_tigAsset, _daoFeesPaid, _burnFeesPaid, _referralFeesPaid, _botFeesPaid, _referrer);
        payout_ = _payout - _daoFeesPaid - _burnFeesPaid - _botFeesPaid;
        IStable(_tigAsset).mintFor(address(this), _daoFeesPaid);
        IStable(_tigAsset).approve(address(gov), type(uint).max);
        gov.distribute(_tigAsset, _daoFeesPaid);
        return payout_;
    }

    /**
     * @dev update funding rates after open interest changes
     * @param _asset asset id
     * @param _tigAsset tigAsset used for OI
     */
    function _updateFunding(uint256 _asset, address _tigAsset) internal {
        position.updateFunding(
            _asset,
            _tigAsset,
            pairsContract.idToOi(_asset, _tigAsset).longOi,
            pairsContract.idToOi(_asset, _tigAsset).shortOi,
            pairsContract.idToAsset(_asset).baseFundingRate,
            vaultFundingPercent
        );
    }

    /**
     * @dev check that SL price is valid compared to market price
     * @param _sl SL price
     * @param _direction long/short
     * @param _price market price
     */
    function _checkSl(uint _sl, bool _direction, uint _price) internal pure {
        if (_direction) {
            if (_sl > _price) revert("3"); //BadStopLoss
        } else {
            if (_sl < _price && _sl != 0) revert("3"); //BadStopLoss
        }
    }

    /**
     * @dev check that trader address owns the position
     * @param _id position id
     * @param _trader trader address
     */
    function _checkOwner(uint _id, address _trader) internal view {
        if (position.ownerOf(_id) != _trader) revert("2"); //NotPositionOwner   
    }

    /**
     * @notice Check that sufficient time has passed between opening and closing
     * @dev This is to prevent profitable opening and closing in the same tx with two different prices in the "valid signature pool".
     * @param _id position id
     * @param _type true for opening, false for closing
     */
    function _checkDelay(uint _id, bool _type) internal {
        unchecked {
            Delay memory _delay = blockDelayPassed[_id];
            if (_delay.actionType == _type) {
                blockDelayPassed[_id].delay = block.number + blockDelay;
            } else {
                if (block.number < _delay.delay) revert("0"); //Wait
                blockDelayPassed[_id].delay = block.number + blockDelay;
                blockDelayPassed[_id].actionType = _type;
            }
        }
    }

    /**
     * @dev Check that the stablevault input is whitelisted and the margin asset is whitelisted in the vault
     * @param _stableVault StableVault address
     * @param _token Margin asset token address
     */
    function _checkVault(address _stableVault, address _token) internal view {
        require(allowedVault[_stableVault], "Unapproved stablevault");
        require(_token == IStableVault(_stableVault).stable() || IStableVault(_stableVault).allowed(_token), "Token not approved in vault");
    }

    /**
     * @dev Check that the trader has approved the proxy address to trade for it
     * @param _trader Trader address
     */
    function _validateProxy(address _trader) internal view {
        if (_trader != _msgSender()) {
            Proxy memory _proxy = proxyApprovals[_trader];
            require(_proxy.proxy == _msgSender() && _proxy.time >= block.timestamp, "Proxy not approved");
        }
    }

    // ===== GOVERNANCE-ONLY =====

    /**
     * @dev Sets block delay between opening and closing
     * @notice In blocks not seconds
     * @param _blockDelay delay amount
     */
    function setBlockDelay(
        uint _blockDelay
    )
        external
        onlyOwner
    {
        blockDelay = _blockDelay;
    }

    /**
     * @dev Whitelists a stablevault contract address
     * @param _stableVault StableVault address
     * @param _bool true if allowed
     */
    function setAllowedVault(
        address _stableVault,
        bool _bool
    )
        external
        onlyOwner
    {
        allowedVault[_stableVault] = _bool;
    }

    /**
     * @dev Sets max payout % compared to margin
     * @param _maxWinPercent payout %
     */
    function setMaxWinPercent(
        uint _maxWinPercent
    )
        external
        onlyOwner
    {
        maxWinPercent = _maxWinPercent;
    }

    /**
     * @dev Sets executable price range for limit orders
     * @param _range price range in %
     */
    function setLimitOrderPriceRange(uint _range) external onlyOwner {
        limitOrderPriceRange = _range;
    }

    /**
     * @dev Sets the fees for the trading protocol
     * @param _open True if open fees are being set
     * @param _daoFees Fees distributed to the DAO
     * @param _burnFees Fees which get burned
     * @param _referralFees Fees given to referrers
     * @param _botFees Fees given to bots that execute limit orders
     * @param _percent Percent of earned funding fees going to StableVault
     */
    function setFees(bool _open, uint _daoFees, uint _burnFees, uint _referralFees, uint _botFees, uint _percent) external onlyOwner {
        unchecked {
            require(_daoFees >= _botFees+_referralFees*2);
            if (_open) {
                openFees.daoFees = _daoFees;
                openFees.burnFees = _burnFees;
                openFees.referralFees = _referralFees;
                openFees.botFees = _botFees;
            } else {
                closeFees.daoFees = _daoFees;
                closeFees.burnFees = _burnFees;
                closeFees.referralFees = _referralFees;
                closeFees.botFees = _botFees;                
            }
            require(_percent <= DIVISION_CONSTANT);
            vaultFundingPercent = _percent;
        }
    }

    /**
     * @dev Sets the extension contract address for trading
     * @param _ext extension contract address
     */
    function setTradingExtension(
        address _ext
    ) external onlyOwner() {
        tradingExtension = ITradingExtension(_ext);
    }

    // ===== EVENTS =====

    event PositionOpened(
        TradeInfo _tradeInfo,
        uint _orderType,
        uint _price,
        uint _id,
        address _trader,
        uint _marginAfterFees
    );

    event PositionClosed(
        uint _id,
        uint _closePrice,
        uint _percent,
        uint _payout,
        address _trader,
        address _executor
    );

    event PositionLiquidated(
        uint _id,
        address _trader,
        address _executor
    );

    event LimitOrderExecuted(
        uint _asset,
        bool _direction,
        uint _openPrice,
        uint _lev,
        uint _margin,
        uint _id,
        address _trader,
        address _executor
    );

    event UpdateTPSL(
        uint _id,
        bool _isTp,
        uint _price,
        address _trader
    );

    event LimitCancelled(
        uint _id,
        address _trader
    );

    event MarginModified(
        uint _id,
        uint _newMargin,
        uint _newLeverage,
        bool _isMarginAdded,
        address _trader
    );

    event AddToPosition(
        uint _id,
        uint _newMargin,
        uint _newPrice,
        address _trader
    );

    event FeesDistributed(
        address _tigAsset,
        uint _daoFees,
        uint _burnFees,
        uint _refFees,
        uint _botFees,
        address _referrer
    );
}


// File: GovNFT.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ILayerZeroEndpoint.sol";
import "./interfaces/ILayerZeroReceiver.sol";
import "./utils/MetaContext.sol";
import "./interfaces/IGovNFT.sol";
import "./utils/ExcessivelySafeCall.sol";

contract GovNFT is ERC721Enumerable, ILayerZeroReceiver, MetaContext, IGovNFT {
    using ExcessivelySafeCall for address;
    
    uint256 private counter = 1;
    uint256 private constant MAX = 10000;
    uint256 public gas = 150000;
    string public baseURI;
    uint256 public maxBridge = 20;
    ILayerZeroEndpoint public endpoint;

    mapping(uint16 => mapping(address => bool)) public isTrustedAddress;
    mapping(uint16 => mapping(bytes => mapping(uint64 => bytes32))) public failedMessages;
    event MessageFailed(uint16 _srcChainId, bytes _srcAddress, uint64 _nonce, bytes _payload, bytes _reason);
    event RetryMessageSuccess(uint16 _srcChainId, bytes _srcAddress, uint64 _nonce, bytes32 _payloadHash);
    event ReceiveNFT(
        uint16 _srcChainId,
        address _from,
        uint256[] _tokenId
    );

    constructor(
        address _endpoint,
        string memory _setBaseURI,
        string memory _name,
        string memory _symbol
    ) ERC721(_name, _symbol) {
        endpoint = ILayerZeroEndpoint(_endpoint);
        baseURI = _setBaseURI;
    }

    function _baseURI() internal override view returns (string memory) {
        return baseURI;
    }

    function setBaseURI(string calldata _newBaseURI) external onlyOwner {
        baseURI = _newBaseURI;
    }

    function _mint(address to, uint256 tokenId) internal override {
        require(counter <= MAX, "Exceeds supply");
        counter += 1;
        for (uint i=0; i<assetsLength(); i++) {
            userPaid[to][assets[i]] += accRewardsPerNFT[assets[i]];
        }
        super._mint(to, tokenId);
    }

    /**
     * @dev should only be called by layer zero
     * @param to the address to receive the bridged NFTs
     * @param tokenId the NFT id
     */
    function _bridgeMint(address to, uint256 tokenId) public {
        require(msg.sender == address(this) || _msgSender() == owner(), "NotBridge");
        require(tokenId <= 10000, "BadID");
        for (uint i=0; i<assetsLength(); i++) {
            userPaid[to][assets[i]] += accRewardsPerNFT[assets[i]];
        }
        super._mint(to, tokenId);
    }

    /**
    * @notice updates userDebt 
    */
    function _burn(uint256 tokenId) internal override {
        address owner = ownerOf(tokenId);
        for (uint i=0; i<assetsLength(); i++) {
            userDebt[owner][assets[i]] += accRewardsPerNFT[assets[i]];
            userDebt[owner][assets[i]] -= userPaid[owner][assets[i]]/balanceOf(owner);
            userPaid[owner][assets[i]] -= userPaid[owner][assets[i]]/balanceOf(owner);            
        }
        super._burn(tokenId);
    }

    /**
    * @notice updates userDebt for both to and from
    */
    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        require(ownerOf(tokenId) == from, "!Owner");
        for (uint i=0; i<assetsLength(); i++) {
            userDebt[from][assets[i]] += accRewardsPerNFT[assets[i]];
            userDebt[from][assets[i]] -= userPaid[from][assets[i]]/balanceOf(from);
            userPaid[from][assets[i]] -= userPaid[from][assets[i]]/balanceOf(from);
            userPaid[to][assets[i]] += accRewardsPerNFT[assets[i]];
        }
        super._transfer(from, to, tokenId);
    }

    function mintMany(uint _amount) external onlyOwner {
        for (uint i=0; i<_amount; i++) {
            _mint(_msgSender(), counter);
        }
    }

    function mint() external onlyOwner {
        _mint(_msgSender(), counter);
    }

    function setTrustedAddress(uint16 _chainId, address _contract, bool _bool) external onlyOwner {
        isTrustedAddress[_chainId][_contract] = _bool;
    }

    /**
    * @notice used to bridge NFTs crosschain using layer zero
    * @param _dstChainId the layer zero id of the dest chain
    * @param _to receiving address on dest chain
    * @param tokenId array of the ids of the NFTs to be bridged
    */
    function crossChain(
        uint16 _dstChainId,
        bytes memory _destination,
        address _to,
        uint256[] memory tokenId
    ) public payable {
        require(tokenId.length > 0, "Not bridging");
        for (uint i=0; i<tokenId.length; i++) {
            require(_msgSender() == ownerOf(tokenId[i]), "Not the owner");
            // burn NFT
            _burn(tokenId[i]);
        }
        address targetAddress;
        assembly {
            targetAddress := mload(add(_destination, 20))
        }
        require(isTrustedAddress[_dstChainId][targetAddress], "!Trusted");
        bytes memory payload = abi.encode(_to, tokenId);
        // encode adapterParams to specify more gas for the destination
        uint16 version = 1;
        uint256 _gas = 500_000 + gas*tokenId.length;
        bytes memory adapterParams = abi.encodePacked(version, _gas);
        (uint256 messageFee, ) = endpoint.estimateFees(
            _dstChainId,
            address(this),
            payload,
            false,
            adapterParams
        );
        require(
            msg.value >= messageFee,
            "Must send enough value to cover messageFee"
        );
        endpoint.send{value: msg.value}(
            _dstChainId,
            _destination,
            payload,
            payable(_msgSender()),
            address(0x0),
            adapterParams
        );
    }


    function lzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) external override {
        require(_msgSender() == address(endpoint), "!Endpoint");
        (bool success, bytes memory reason) = address(this).excessivelySafeCall(gasleft()*4/5, 150, abi.encodeWithSelector(this.nonblockingLzReceive.selector, _srcChainId, _srcAddress, _nonce, _payload));
        // try-catch all errors/exceptions
        if (!success) {
            failedMessages[_srcChainId][_srcAddress][_nonce] = keccak256(_payload);
            emit MessageFailed(_srcChainId, _srcAddress, _nonce, _payload, reason);
        }
    }

    function nonblockingLzReceive(uint16 _srcChainId, bytes calldata _srcAddress, uint64 _nonce, bytes calldata _payload) public {
        // only internal transaction
        require(msg.sender == address(this), "NonblockingLzApp: caller must be app");
        _nonblockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
    }

    function _nonblockingLzReceive(uint16 _srcChainId, bytes memory _srcAddress, uint64, bytes memory _payload) internal {
        address fromAddress;
        assembly {
            fromAddress := mload(add(_srcAddress, 20))
        }
        require(isTrustedAddress[_srcChainId][fromAddress], "!TrustedAddress");
        (address toAddress, uint256[] memory tokenId) = abi.decode(
            _payload,
            (address, uint256[])
        );
        // mint the tokens
        for (uint i=0; i<tokenId.length; i++) {
            _bridgeMint(toAddress, tokenId[i]);
        }
        emit ReceiveNFT(_srcChainId, toAddress, tokenId);
    }

    function retryMessage(uint16 _srcChainId, bytes calldata _srcAddress, uint64 _nonce, bytes calldata _payload) public {
        // assert there is message to retry
        bytes32 payloadHash = failedMessages[_srcChainId][_srcAddress][_nonce];
        require(payloadHash != bytes32(0), "NonblockingLzApp: no stored message");
        require(keccak256(_payload) == payloadHash, "NonblockingLzApp: invalid payload");
        // clear the stored message
        failedMessages[_srcChainId][_srcAddress][_nonce] = bytes32(0);
        // execute the message. revert if it fails again
        _nonblockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
        emit RetryMessageSuccess(_srcChainId, _srcAddress, _nonce, payloadHash);
    }

    // Endpoint.sol estimateFees() returns the fees for the message
    function estimateFees(
        uint16 _dstChainId,
        address _userApplication,
        bytes calldata _payload,
        bool _payInZRO,
        bytes calldata _adapterParams
    ) external view returns (uint256 nativeFee, uint256 zroFee) {
        return
            endpoint.estimateFees(
                _dstChainId,
                _userApplication,
                _payload,
                _payInZRO,
                _adapterParams
            );
    }

    function setGas(uint _gas) external onlyOwner {
        gas = _gas;
    }

    function setEndpoint(ILayerZeroEndpoint _endpoint) external onlyOwner {
        require(address(_endpoint) != address(0), "ZeroAddress");
        endpoint = _endpoint;
    }

    function safeTransferMany(address _to, uint[] calldata _ids) external {
        for (uint i=0; i<_ids.length; i++) {
            _transfer(_msgSender(), _to, _ids[i]);
        }
    }

    function safeTransferFromMany(address _from, address _to, uint[] calldata _ids) external {
        for (uint i=0; i<_ids.length; i++) {
            safeTransferFrom(_from, _to, _ids[i]);
        }
    }

    function approveMany(address _to, uint[] calldata _ids) external {
        for (uint i=0; i<_ids.length; i++) {
            approve(_to, _ids[i]);
        }
    }

    // Rewards
    address[] public assets;
    mapping(address => bool) private _allowedAsset;
    mapping(address => uint) private assetsIndex;
    mapping(address => mapping(address => uint256)) private userPaid;
    mapping(address => mapping(address => uint256)) private userDebt;
    mapping(address => uint256) private accRewardsPerNFT;

    /**
    * @notice claimable by anyone to claim pending rewards tokens
    * @param _tigAsset reward token address
    */
    function claim(address _tigAsset) external {
        address _msgsender = _msgSender();
        uint256 amount = pending(_msgsender, _tigAsset);
        userPaid[_msgsender][_tigAsset] += amount;
        IERC20(_tigAsset).transfer(_msgsender, amount);
    }

    /**
    * @notice add rewards for NFT holders
    * @param _tigAsset reward token address
    * @param _amount amount to be distributed
    */
    function distribute(address _tigAsset, uint _amount) external {
        if (assets.length == 0 || assets[assetsIndex[_tigAsset]] == address(0) || totalSupply() == 0 || !_allowedAsset[_tigAsset]) return;
        try IERC20(_tigAsset).transferFrom(_msgSender(), address(this), _amount) {
            accRewardsPerNFT[_tigAsset] += _amount/totalSupply();
        } catch {
            return;
        }
    }

    function pending(address user, address _tigAsset) public view returns (uint256) {
        return userDebt[user][_tigAsset] + balanceOf(user)*accRewardsPerNFT[_tigAsset] - userPaid[user][_tigAsset]; 
    }

    function addAsset(address _asset) external onlyOwner {
        require(assets.length == 0 || assets[assetsIndex[_asset]] != _asset, "Already added");
        assetsIndex[_asset] = assets.length;
        assets.push(_asset);
        _allowedAsset[_asset] = true;
    }

    function setAllowedAsset(address _asset, bool _bool) external onlyOwner {
        _allowedAsset[_asset] = _bool;
    }

    function setMaxBridge(uint256 _max) external onlyOwner {
        maxBridge = _max;
    }

    function assetsLength() public view returns (uint256) {
        return assets.length;
    }

    function allowedAsset(address _asset) external view returns (bool) {
        return _allowedAsset[_asset];
    }

    function balanceIds(address _user) external view returns (uint[] memory) {
        uint[] memory _ids = new uint[](balanceOf(_user));
        for (uint i=0; i<_ids.length; i++) {
            _ids[i] = tokenOfOwnerByIndex(_user, i);
        }
        return _ids;
    }

    // META-TX
    function _msgSender() internal view override(Context, MetaContext) returns (address sender) {
        return MetaContext._msgSender();
    }
    function _msgData() internal view override(Context, MetaContext) returns (bytes calldata) {
        return MetaContext._msgData();
    }
}

// File: TradingLibrary.sol
//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../interfaces/IPosition.sol";

interface IPrice {
    function latestAnswer() external view returns (int256);
    function decimals() external view returns (uint256);
}

struct PriceData {
    address provider;
    uint256 asset;
    uint256 price;
    uint256 spread;
    uint256 timestamp;
    bool isClosed;
}

library TradingLibrary {

    using ECDSA for bytes32;

    /**
    * @notice returns position profit or loss
    * @param _direction true if long
    * @param _currentPrice current price
    * @param _price opening price
    * @param _leverage position leverage
    * @param _margin collateral amount
    * @param accInterest funding fees
    * @return _positionSize position size
    * @return _payout payout trader should get
    */
    function pnl(bool _direction, uint _currentPrice, uint _price, uint _margin, uint _leverage, int256 accInterest) external pure returns (uint256 _positionSize, int256 _payout) {
        unchecked {
            uint _initPositionSize = _margin * _leverage / 1e18;
            if (_direction && _currentPrice >= _price) {
                _payout = int256(_margin) + int256(_initPositionSize * (1e18 * _currentPrice / _price - 1e18)/1e18) + accInterest;
            } else if (_direction && _currentPrice < _price) {
                _payout = int256(_margin) - int256(_initPositionSize * (1e18 - 1e18 * _currentPrice / _price)/1e18) + accInterest;
            } else if (!_direction && _currentPrice <= _price) {
                _payout = int256(_margin) + int256(_initPositionSize * (1e18 - 1e18 * _currentPrice / _price)/1e18) + accInterest;
            } else {
                _payout = int256(_margin) - int256(_initPositionSize * (1e18 * _currentPrice / _price - 1e18)/1e18) + accInterest;
            }
            _positionSize = _initPositionSize * _currentPrice / _price;
        }
    }

    /**
    * @notice returns position liquidation price
    * @param _direction true if long
    * @param _tradePrice opening price
    * @param _leverage position leverage
    * @param _margin collateral amount
    * @param _accInterest funding fees
    * @param _liqPercent liquidation percent
    * @return _liqPrice liquidation price
    */
    function liqPrice(bool _direction, uint _tradePrice, uint _leverage, uint _margin, int _accInterest, uint _liqPercent) public pure returns (uint256 _liqPrice) {
        if (_direction) {
            _liqPrice = _tradePrice - ((_tradePrice*1e18/_leverage) * uint(int(_margin)+_accInterest) / _margin) * _liqPercent / 1e10;
        } else {
            _liqPrice = _tradePrice + ((_tradePrice*1e18/_leverage) * uint(int(_margin)+_accInterest) / _margin) * _liqPercent / 1e10;
        }
    }

    /**
    * @notice uses liqPrice() and returns position liquidation price
    * @param _positions positions contract address
    * @param _id position id
    * @param _liqPercent liquidation percent
    */
    function getLiqPrice(address _positions, uint _id, uint _liqPercent) external view returns (uint256) {
        IPosition.Trade memory _trade = IPosition(_positions).trades(_id);
        return liqPrice(_trade.direction, _trade.price, _trade.leverage, _trade.margin, _trade.accInterest, _liqPercent);
    }

    /**
    * @notice verifies that price is signed by a whitelisted node
    * @param _validSignatureTimer seconds allowed before price is old
    * @param _asset position asset
    * @param _chainlinkEnabled is chainlink verification is on
    * @param _chainlinkFeed address of chainlink price feed
    * @param _priceData PriceData object
    * @param _signature signature returned from oracle
    * @param _isNode mapping of allowed nodes
    */
    function verifyPrice(
        uint256 _validSignatureTimer,
        uint256 _asset,
        bool _chainlinkEnabled,
        address _chainlinkFeed,
        PriceData calldata _priceData,
        bytes calldata _signature,
        mapping(address => bool) storage _isNode
    )
        external view
    {
        address _provider = (
            keccak256(abi.encode(_priceData))
        ).toEthSignedMessageHash().recover(_signature);
        require(_provider == _priceData.provider, "BadSig");
        require(_isNode[_provider], "!Node");
        require(_asset == _priceData.asset, "!Asset");
        require(!_priceData.isClosed, "Closed");
        require(block.timestamp >= _priceData.timestamp, "FutSig");
        require(block.timestamp <= _priceData.timestamp + _validSignatureTimer, "ExpSig");
        require(_priceData.price > 0, "NoPrice");
        if (_chainlinkEnabled && _chainlinkFeed != address(0)) {
            int256 assetChainlinkPriceInt = IPrice(_chainlinkFeed).latestAnswer();
            if (assetChainlinkPriceInt != 0) {
                uint256 assetChainlinkPrice = uint256(assetChainlinkPriceInt) * 10**(18 - IPrice(_chainlinkFeed).decimals());
                require(
                    _priceData.price < assetChainlinkPrice+assetChainlinkPrice*2/100 &&
                    _priceData.price > assetChainlinkPrice-assetChainlinkPrice*2/100, "!chainlinkPrice"
                );
            }
        }
    }
}


// File: StableVault.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./utils/MetaContext.sol";
import "./interfaces/IStableVault.sol";

interface IERC20Mintable is IERC20 {
    function mintFor(address, uint256) external;
    function burnFrom(address, uint256) external;
    function decimals() external view returns (uint);
}

interface ERC20Permit is IERC20 {
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

contract StableVault is MetaContext, IStableVault {

    mapping(address => bool) public allowed;
    mapping(address => uint) private tokenIndex;
    address[] public tokens;

    address public immutable stable;

    constructor(address _stable) {
        stable = _stable;
    }

    /**
    * @notice deposit an allowed token and receive tigAsset
    * @param _token address of the allowed token
    * @param _amount amount of _token
    */
    function deposit(address _token, uint256 _amount) public {
        require(allowed[_token], "Token not listed");
        IERC20(_token).transferFrom(_msgSender(), address(this), _amount);
        IERC20Mintable(stable).mintFor(
            _msgSender(),
            _amount*(10**(18-IERC20Mintable(_token).decimals()))
        );
    }

    function depositWithPermit(address _token, uint256 _amount, uint256 _deadline, bool _permitMax, uint8 v, bytes32 r, bytes32 s) external {
        uint _toAllow = _amount;
        if (_permitMax) _toAllow = type(uint).max;
        ERC20Permit(_token).permit(_msgSender(), address(this), _toAllow, _deadline, v, r, s);
        deposit(_token, _amount);
    }

    /**
    * @notice swap tigAsset to _token
    * @param _token address of the token to receive
    * @param _amount amount of _token
    */
    function withdraw(address _token, uint256 _amount) external returns (uint256 _output) {
        IERC20Mintable(stable).burnFrom(_msgSender(), _amount);
        _output = _amount/10**(18-IERC20Mintable(_token).decimals());
        IERC20(_token).transfer(
            _msgSender(),
            _output
        );
    }

    /**
    * @notice allow a token to be used in vault
    * @param _token address of the token
    */
    function listToken(address _token) external onlyOwner {
        require(!allowed[_token], "Already added");
        tokenIndex[_token] = tokens.length;
        tokens.push(_token);
        allowed[_token] = true;
    }

    /**
    * @notice stop a token from being allowed in vault
    * @param _token address of the token
    */
    function delistToken(address _token) external onlyOwner {
        require(allowed[_token], "Not added");
        tokenIndex[tokens[tokens.length-1]] = tokenIndex[_token];
        tokens[tokenIndex[_token]] = tokens[tokens.length-1];
        delete tokenIndex[_token];
        tokens.pop();
        allowed[_token] = false;
    }
}

// File: BondNFT.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BondNFT is ERC721Enumerable, Ownable {
    
    uint constant private DAY = 24 * 60 * 60;

    struct Bond {
        uint id;
        address owner;
        address asset;
        uint amount;
        uint mintEpoch;
        uint mintTime;
        uint expireEpoch;
        uint pending;
        uint shares;
        uint period;
        bool expired;
    }

    mapping(address => uint256) public epoch;
    uint private totalBonds;
    string public baseURI;
    address public manager;
    address[] public assets;

    mapping(address => bool) public allowedAsset;
    mapping(address => uint) private assetsIndex;
    mapping(uint256 => mapping(address => uint256)) private bondPaid;
    mapping(address => mapping(uint256 => uint256)) private accRewardsPerShare; // tigAsset => epoch => accRewardsPerShare
    mapping(uint => Bond) private _idToBond;
    mapping(address => uint) public totalShares;
    mapping(address => mapping(address => uint)) public userDebt; // user => tigAsset => amount

    constructor(
        string memory _setBaseURI,
        string memory _name,
        string memory _symbol
    ) ERC721(_name, _symbol) {
        baseURI = _setBaseURI;
    }

    /**
     * @notice Create a bond
     * @dev Should only be called by a manager contract
     * @param _asset tigAsset token to lock
     * @param _amount tigAsset amount
     * @param _period time to lock for in days
     * @param _owner address to receive the bond
     * @return id ID of the minted bond
     */
    function createLock(
        address _asset,
        uint _amount,
        uint _period,
        address _owner
    ) external onlyManager() returns(uint id) {
        require(allowedAsset[_asset], "!Asset");
        unchecked {
            uint shares = _amount * _period / 365;
            uint expireEpoch = epoch[_asset] + _period;
            id = ++totalBonds;
            totalShares[_asset] += shares;
            Bond memory _bond = Bond(
                id,             // id
                address(0),     // owner
                _asset,         // tigAsset token
                _amount,        // tigAsset amount
                epoch[_asset],  // mint epoch
                block.timestamp,// mint timestamp
                expireEpoch,    // expire epoch
                0,              // pending
                shares,         // linearly scaling share of rewards
                _period,        // lock period
                false           // is expired boolean
            );
            _idToBond[id] = _bond;
            _mint(_owner, _bond);
        }
        emit Lock(_asset, _amount, _period, _owner, id);
    }

    /** 
     * @notice Extend the lock period and/or amount of a bond
     * @dev Should only be called by a manager contract
     * @param _id ID of the bond
     * @param _asset tigAsset token address
     * @param _amount amount of tigAsset being added
     * @param _period days being added to the bond
     * @param _sender address extending the bond
     */
    function extendLock(
        uint _id,
        address _asset,
        uint _amount,
        uint _period,
        address _sender
    ) external onlyManager() {
        Bond memory bond = idToBond(_id);
        Bond storage _bond = _idToBond[_id];
        require(bond.owner == _sender, "!owner");
        require(!bond.expired, "Expired");
        require(bond.asset == _asset, "!BondAsset");
        require(bond.pending == 0);
        require(epoch[bond.asset] == block.timestamp/DAY, "Bad epoch");
        require(bond.period+_period <= 365, "MAX PERIOD");
        unchecked {
            uint shares = (bond.amount + _amount) * (bond.period + _period) / 365;
            uint expireEpoch = block.timestamp/DAY + bond.period + _period;
            totalShares[bond.asset] += shares-bond.shares;
            _bond.shares = shares;
            _bond.amount += _amount;
            _bond.expireEpoch = expireEpoch;
            _bond.period += _period;
            _bond.mintTime = block.timestamp;
            _bond.mintEpoch = epoch[bond.asset];
            bondPaid[_id][bond.asset] = accRewardsPerShare[bond.asset][epoch[bond.asset]] * _bond.shares / 1e18;
        }
        emit ExtendLock(_period, _amount, _sender,  _id);
    }

    /**
     * @notice Release a bond
     * @dev Should only be called by a manager contract
     * @param _id ID of the bond
     * @param _releaser address initiating the release of the bond
     * @return amount amount of tigAsset returned
     * @return lockAmount amount of tigAsset locked in the bond
     * @return asset tigAsset token released
     * @return _owner bond owner
     */
    function release(
        uint _id,
        address _releaser
    ) external onlyManager() returns(uint amount, uint lockAmount, address asset, address _owner) {
        Bond memory bond = idToBond(_id);
        require(bond.expired, "!expire");
        if (_releaser != bond.owner) {
            unchecked {
                require(bond.expireEpoch + 7 < epoch[bond.asset], "Bond owner priority");
            }
        }
        amount = bond.amount;
        unchecked {
            totalShares[bond.asset] -= bond.shares;
            (uint256 _claimAmount,) = claim(_id, bond.owner);
            amount += _claimAmount;
        }
        asset = bond.asset;
        lockAmount = bond.amount;
        _owner = bond.owner;
        _burn(_id);
        emit Release(asset, lockAmount, _owner, _id);
    }
    /**
     * @notice Claim rewards from a bond
     * @dev Should only be called by a manager contract
     * @param _id ID of the bond to claim rewards from
     * @param _claimer address claiming rewards
     * @return amount amount of tigAsset claimed
     * @return tigAsset tigAsset token address
     */
    function claim(
        uint _id,
        address _claimer
    ) public onlyManager() returns(uint amount, address tigAsset) {
        Bond memory bond = idToBond(_id);
        require(_claimer == bond.owner, "!owner");
        amount = bond.pending;
        tigAsset = bond.asset;
        unchecked {
            if (bond.expired) {
                uint _pendingDelta = (bond.shares * accRewardsPerShare[bond.asset][epoch[bond.asset]] / 1e18 - bondPaid[_id][bond.asset]) - (bond.shares * accRewardsPerShare[bond.asset][bond.expireEpoch-1] / 1e18 - bondPaid[_id][bond.asset]);
                if (totalShares[bond.asset] > 0) {
                    accRewardsPerShare[bond.asset][epoch[bond.asset]] += _pendingDelta*1e18/totalShares[bond.asset];
                }
            }
            bondPaid[_id][bond.asset] += amount;
        }
        IERC20(tigAsset).transfer(manager, amount);
        emit ClaimFees(tigAsset, amount, _claimer, _id);
    }

    /**
     * @notice Claim user debt left from bond transfer
     * @dev Should only be called by a manager contract
     * @param _user user address
     * @param _tigAsset tigAsset token address
     * @return amount amount of tigAsset claimed
     */
    function claimDebt(
        address _user,
        address _tigAsset
    ) public onlyManager() returns(uint amount) {
        amount = userDebt[_user][_tigAsset];
        userDebt[_user][_tigAsset] = 0;
        IERC20(_tigAsset).transfer(manager, amount);
        emit ClaimDebt(_tigAsset, amount, _user);
    }

    /**
     * @notice Distribute rewards to bonds
     * @param _tigAsset tigAsset token address
     * @param _amount tigAsset amount
     */
    function distribute(
        address _tigAsset,
        uint _amount
    ) external {
        if (totalShares[_tigAsset] == 0 || !allowedAsset[_tigAsset]) return;
        IERC20(_tigAsset).transferFrom(_msgSender(), address(this), _amount);
        unchecked {
            uint aEpoch = block.timestamp / DAY;
            if (aEpoch > epoch[_tigAsset]) {
                for (uint i=epoch[_tigAsset]; i<aEpoch; i++) {
                    epoch[_tigAsset] += 1;
                    accRewardsPerShare[_tigAsset][i+1] = accRewardsPerShare[_tigAsset][i];
                }
            }
            accRewardsPerShare[_tigAsset][aEpoch] += _amount * 1e18 / totalShares[_tigAsset];
        }
        emit Distribution(_tigAsset, _amount);
    }

    /**
     * @notice Get all data for a bond
     * @param _id ID of the bond
     * @return bond Bond object
     */
    function idToBond(uint256 _id) public view returns (Bond memory bond) {
        bond = _idToBond[_id];
        bond.owner = ownerOf(_id);
        bond.expired = bond.expireEpoch <= epoch[bond.asset] ? true : false;
        unchecked {
            uint _accRewardsPerShare = accRewardsPerShare[bond.asset][bond.expired ? bond.expireEpoch-1 : epoch[bond.asset]];
            bond.pending = bond.shares * _accRewardsPerShare / 1e18 - bondPaid[_id][bond.asset];
        }
    }

    /*
     * @notice Get expired boolean for a bond
     * @param _id ID of the bond
     * @return bool true if bond is expired
     */
    function isExpired(uint256 _id) public view returns (bool) {
        Bond memory bond = _idToBond[_id];
        return bond.expireEpoch <= epoch[bond.asset] ? true : false;
    }

    /*
     * @notice Get pending rewards for a bond
     * @param _id ID of the bond
     * @return bool true if bond is expired
     */
    function pending(
        uint256 _id
    ) public view returns (uint256) {
        return idToBond(_id).pending;
    }

    function totalAssets() public view returns (uint256) {
        return assets.length;
    }

    /*
     * @notice Gets an array of all whitelisted token addresses
     * @return address array of addresses
     */
    function getAssets() public view returns (address[] memory) {
        return assets;
    }

    function _baseURI() internal override view returns (string memory) {
        return baseURI;
    }

    function safeTransferMany(address _to, uint[] calldata _ids) external {
        unchecked {
            for (uint i=0; i<_ids.length; i++) {
                _transfer(_msgSender(), _to, _ids[i]);
            }
        }
    }

    function safeTransferFromMany(address _from, address _to, uint[] calldata _ids) external {
        unchecked {
            for (uint i=0; i<_ids.length; i++) {
                safeTransferFrom(_from, _to, _ids[i]);
            }
        }
    }

    function approveMany(address _to, uint[] calldata _ids) external {
        unchecked {
            for (uint i=0; i<_ids.length; i++) {
                approve(_to, _ids[i]);
            }
        }
    }

    function _mint(
        address to,
        Bond memory bond
    ) internal {
        unchecked {
            bondPaid[bond.id][bond.asset] = accRewardsPerShare[bond.asset][epoch[bond.asset]] * bond.shares / 1e18;
        }
        _mint(to, bond.id);
    }

    function _burn(
        uint256 _id
    ) internal override {
        delete _idToBond[_id];
        super._burn(_id);
    }

    function _transfer(
        address from,
        address to,
        uint256 _id
    ) internal override {
        Bond memory bond = idToBond(_id);
        require(epoch[bond.asset] == block.timestamp/DAY, "Bad epoch");
        require(!bond.expired, "Expired!");
        unchecked {
            require(block.timestamp > bond.mintTime + 300, "Recent update");
            userDebt[from][bond.asset] += bond.pending;
            bondPaid[_id][bond.asset] += bond.pending;
        }
        super._transfer(from, to, _id);
    }

    function balanceIds(address _user) public view returns (uint[] memory) {
        uint[] memory _ids = new uint[](balanceOf(_user));
        unchecked {
            for (uint i=0; i<_ids.length; i++) {
                _ids[i] = tokenOfOwnerByIndex(_user, i);
            }
        }
        return _ids;
    }

    function addAsset(address _asset) external onlyOwner {
        require(assets.length == 0 || assets[assetsIndex[_asset]] != _asset, "Already added");
        assetsIndex[_asset] = assets.length;
        assets.push(_asset);
        allowedAsset[_asset] = true;
        epoch[_asset] = block.timestamp/DAY;
    }

    function setAllowedAsset(address _asset, bool _bool) external onlyOwner {
        require(assets[assetsIndex[_asset]] == _asset, "Not added");
        allowedAsset[_asset] = _bool;
    }

    function setBaseURI(string calldata _newBaseURI) external onlyOwner {
        baseURI = _newBaseURI;
    }

    function setManager(
        address _manager
    ) public onlyOwner() {
        manager = _manager;
    }

    modifier onlyManager() {
        require(msg.sender == manager, "!manager");
        _;
    }

    event Distribution(address _tigAsset, uint256 _amount);
    event Lock(address _tigAsset, uint256 _amount, uint256 _period, address _owner, uint256 _id);
    event ExtendLock(uint256 _period, uint256 _amount, address _owner, uint256 _id);
    event Release(address _tigAsset, uint256 _amount, address _owner, uint256 _id);
    event ClaimFees(address _tigAsset, uint256 _amount, address _claimer, uint256 _id);
    event ClaimDebt(address _tigAsset, uint256 _amount, address _owner);
}

// File: TradingExtension.sol
//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IPairsContract.sol";
import "./utils/TradingLibrary.sol";
import "./interfaces/IReferrals.sol";
import "./interfaces/IPosition.sol";

contract TradingExtension is Ownable{
    uint constant private DIVISION_CONSTANT = 1e10; // 100%

    address public trading;
    uint256 public validSignatureTimer;
    bool public chainlinkEnabled;

    mapping(address => bool) private isNode;
    mapping(address => uint) public minPositionSize;
    mapping(address => bool) public allowedMargin;
    bool public paused;

    IPairsContract private pairsContract;
    IReferrals private referrals;
    IPosition private position;

    uint public maxGasPrice = 1000000000000; // 1000 gwei

    constructor(
        address _trading,
        address _pairsContract,
        address _ref,
        address _position
    )
    {
        trading = _trading;
        pairsContract = IPairsContract(_pairsContract);
        referrals = IReferrals(_ref);
        position = IPosition(_position);
    }

    /**
    * @notice returns the minimum position size per collateral asset
    * @param _asset address of the asset
    */
    function minPos(
        address _asset
    ) external view returns(uint) {
        return minPositionSize[_asset];
    }

    /**
    * @notice closePosition helper
    * @dev only callable by trading contract
    * @param _id id of the position NFT
    * @param _price current asset price
    * @param _percent close percentage
    * @return _trade returns the trade struct from NFT contract
    * @return _positionSize size of the position
    * @return _payout amount of payout to the trader after closing
    */
    function _closePosition(
        uint _id,
        uint _price,
        uint _percent
    ) external onlyProtocol returns (IPosition.Trade memory _trade, uint256 _positionSize, int256 _payout) {
        _trade = position.trades(_id);
        (_positionSize, _payout) = TradingLibrary.pnl(_trade.direction, _price, _trade.price, _trade.margin, _trade.leverage, _trade.accInterest);

        unchecked {
            if (_trade.direction) {
                modifyLongOi(_trade.asset, _trade.tigAsset, false, (_trade.margin*_trade.leverage/1e18)*_percent/DIVISION_CONSTANT);
            } else {
                modifyShortOi(_trade.asset, _trade.tigAsset, false, (_trade.margin*_trade.leverage/1e18)*_percent/DIVISION_CONSTANT);     
            }
        }
    }

    /**
    * @notice limitClose helper
    * @dev only callable by trading contract
    * @param _id id of the position NFT
    * @param _tp true if long, else short
    * @param _priceData price data object came from the price oracle
    * @param _signature to verify the oracle
    * @return _limitPrice price of sl or tp returned from positions contract
    * @return _tigAsset address of the position collateral asset
    */
    function _limitClose(
        uint _id,
        bool _tp,
        PriceData calldata _priceData,
        bytes calldata _signature
    ) external view returns(uint _limitPrice, address _tigAsset) {
        _checkGas();
        IPosition.Trade memory _trade = position.trades(_id);
        _tigAsset = _trade.tigAsset;

        getVerifiedPrice(_trade.asset, _priceData, _signature, 0);
        uint256 _price = _priceData.price;

        if (_trade.orderType != 0) revert("4"); //IsLimit

        if (_tp) {
            if (_trade.tpPrice == 0) revert("7"); //LimitNotSet
            if (_trade.direction) {
                if (_trade.tpPrice > _price) revert("6"); //LimitNotMet
            } else {
                if (_trade.tpPrice < _price) revert("6"); //LimitNotMet
            }
            _limitPrice = _trade.tpPrice;
        } else {
            if (_trade.slPrice == 0) revert("7"); //LimitNotSet
            if (_trade.direction) {
                if (_trade.slPrice < _price) revert("6"); //LimitNotMet
            } else {
                if (_trade.slPrice > _price) revert("6"); //LimitNotMet
            }
            _limitPrice = _trade.slPrice;
        }
    }

    function _checkGas() public view {
        if (tx.gasprice > maxGasPrice) revert("1"); //GasTooHigh
    }

    function modifyShortOi(
        uint _asset,
        address _tigAsset,
        bool _onOpen,
        uint _size
    ) public onlyProtocol {
        pairsContract.modifyShortOi(_asset, _tigAsset, _onOpen, _size);
    }

    function modifyLongOi(
        uint _asset,
        address _tigAsset,
        bool _onOpen,
        uint _size
    ) public onlyProtocol {
        pairsContract.modifyLongOi(_asset, _tigAsset, _onOpen, _size);
    }

    function setMaxGasPrice(uint _maxGasPrice) external onlyOwner {
        maxGasPrice = _maxGasPrice;
    }

    function getRef(
        address _trader
    ) external view returns(address) {
        return referrals.getReferral(referrals.getReferred(_trader));
    }

    /**
    * @notice verifies the signed price and returns it
    * @param _asset id of position asset
    * @param _priceData price data object came from the price oracle
    * @param _signature to verify the oracle
    * @param _withSpreadIsLong 0, 1, or 2 - to specify if we need the price returned to be after spread
    * @return _price price after verification and with spread if _withSpreadIsLong is 1 or 2
    * @return _spread spread after verification
    */
    function getVerifiedPrice(
        uint _asset,
        PriceData calldata _priceData,
        bytes calldata _signature,
        uint _withSpreadIsLong
    ) 
        public view
        returns(uint256 _price, uint256 _spread) 
    {
        TradingLibrary.verifyPrice(
            validSignatureTimer,
            _asset,
            chainlinkEnabled,
            pairsContract.idToAsset(_asset).chainlinkFeed,
            _priceData,
            _signature,
            isNode
        );
        _price = _priceData.price;
        _spread = _priceData.spread;

        if(_withSpreadIsLong == 1) 
            _price += _price * _spread / DIVISION_CONSTANT;
        else if(_withSpreadIsLong == 2) 
            _price -= _price * _spread / DIVISION_CONSTANT;
    }

    function _setReferral(
        bytes32 _referral,
        address _trader
    ) external onlyProtocol {
        
        if (_referral != bytes32(0)) {
            if (referrals.getReferral(_referral) != address(0)) {
                if (referrals.getReferred(_trader) == bytes32(0)) {
                    referrals.setReferred(_trader, _referral);
                }
            }
        }
    }

    /**
     * @dev validates the inputs of trades
     * @param _asset asset id
     * @param _tigAsset margin asset
     * @param _margin margin
     * @param _leverage leverage
     */
    function validateTrade(uint _asset, address _tigAsset, uint _margin, uint _leverage) external view {
        unchecked {
            IPairsContract.Asset memory asset = pairsContract.idToAsset(_asset);
            if (!allowedMargin[_tigAsset]) revert("!margin");
            if (paused) revert("paused");
            if (!pairsContract.allowedAsset(_asset)) revert("!allowed");
            if (_leverage < asset.minLeverage || _leverage > asset.maxLeverage) revert("!lev");
            if (_margin*_leverage/1e18 < minPositionSize[_tigAsset]) revert("!size");
        }
    }

    function setValidSignatureTimer(
        uint _validSignatureTimer
    )
        external
        onlyOwner
    {
        validSignatureTimer = _validSignatureTimer;
    }

    function setChainlinkEnabled(bool _bool) external onlyOwner {
        chainlinkEnabled = _bool;
    }

    /**
     * @dev whitelists a node
     * @param _node node address
     * @param _bool bool
     */
    function setNode(address _node, bool _bool) external onlyOwner {
        isNode[_node] = _bool;
    }

    /**
     * @dev Allows a tigAsset to be used
     * @param _tigAsset tigAsset
     * @param _bool bool
     */
    function setAllowedMargin(
        address _tigAsset,
        bool _bool
    ) 
        external
        onlyOwner
    {
        allowedMargin[_tigAsset] = _bool;
    }

    /**
     * @dev changes the minimum position size
     * @param _tigAsset tigAsset
     * @param _min minimum position size 18 decimals
     */
    function setMinPositionSize(
        address _tigAsset,
        uint _min
    ) 
        external
        onlyOwner
    {
        minPositionSize[_tigAsset] = _min;
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }

    modifier onlyProtocol { 
        require(msg.sender == trading, "!protocol");
        _;
    }
}
"""