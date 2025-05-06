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

// File: Referrals.sol
//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IReferrals.sol";

contract Referrals is Ownable, IReferrals {

    bool private isInit;

    address public protocol;

    mapping(bytes32 => address) private _referral;
    mapping(address => bytes32) private _referred;

    /**
    * @notice used by any address to create a ref code
    * @param _hash hash of the string code
    */
    function createReferralCode(bytes32 _hash) external {
        require(_referral[_hash] == address(0), "Referral code already exists");
        _referral[_hash] = _msgSender();
        emit ReferralCreated(_msgSender(), _hash);
    }

    /**
    * @notice set the ref data
    * @dev only callable by trading
    * @param _referredTrader address of the trader
    * @param _hash ref hash
    */
    function setReferred(address _referredTrader, bytes32 _hash) external onlyProtocol {
        if (_referred[_referredTrader] != bytes32(0)) {
            return;
        }
        if (_referredTrader == _referral[_hash]) {
            return;
        }
        _referred[_referredTrader] = _hash;
        emit Referred(_referredTrader, _hash);
    }

    function getReferred(address _trader) external view returns (bytes32) {
        return _referred[_trader];
    }

    function getReferral(bytes32 _hash) external view returns (address) {
        return _referral[_hash];
    }

    // Owner

    function setProtocol(address _protocol) external onlyOwner {
        protocol = _protocol;
    }

    /**
    * @notice deprecated
    */
    function initRefs(
        address[] memory _codeOwners,
        bytes32[] memory _ownedCodes,
        address[] memory _referredA,
        bytes32[] memory _referredTo
    ) external onlyOwner {
        require(!isInit);
        isInit = true;
        uint _codeOwnersL = _codeOwners.length;
        uint _referredAL = _referredA.length;
        for (uint i=0; i<_codeOwnersL; i++) {
            _referral[_ownedCodes[i]] = _codeOwners[i];
        }
        for (uint i=0; i<_referredAL; i++) {
            _referred[_referredA[i]] = _referredTo[i];
        }
    }

    // Modifiers

    modifier onlyProtocol() {
        require(_msgSender() == address(protocol), "!Protocol");
        _;
    }

    event ReferralCreated(address _referrer, bytes32 _hash);
    event Referred(address _referredTrader, bytes32 _hash);

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

// File: StableToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "./utils/MetaContext.sol";

contract StableToken is ERC20Permit, MetaContext {

    mapping(address => bool) public isMinter;

    constructor(string memory name_, string memory symbol_) ERC20Permit(name_) ERC20(name_, symbol_) {}

    function burnFrom(
        address account,
        uint256 amount
    ) 
        public 
        virtual 
        onlyMinter() 
    {
        _burn(account, amount);
    }

    function mintFor(
        address account,
        uint256 amount
    ) 
        public 
        virtual 
        onlyMinter() 
    {  
        _mint(account, amount);
    }

    /**
     * @dev Sets the status of minter.
     */
    function setMinter(
        address _address,
        bool _status
    ) 
        public
        onlyOwner()
    {
        isMinter[_address] = _status;
    }

    /**
     * @dev Throws if called by any account that is not minter.
     */
    modifier onlyMinter() {
        require(isMinter[_msgSender()], "!Minter");
        _;
    }

    // META-TX
    function _msgSender() internal view override(Context, MetaContext) returns (address sender) {
        return MetaContext._msgSender();
    }

    // Unreachable
    function _msgData() internal view override(Context, MetaContext) returns (bytes calldata) {
        return MetaContext._msgData();
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

// File: Lock.sol
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IBondNFT.sol";
import "./interfaces/IGovNFT.sol";

contract Lock is Ownable{

    uint public constant minPeriod = 7;
    uint public constant maxPeriod = 365;

    IBondNFT public immutable bondNFT;
    IGovNFT public immutable govNFT;

    mapping(address => bool) public allowedAssets;
    mapping(address => uint) public totalLocked;

    constructor(
        address _bondNFTAddress,
        address _govNFT
    ) {
        bondNFT = IBondNFT(_bondNFTAddress);
        govNFT = IGovNFT(_govNFT);
    }

    /**
     * @notice Claim pending rewards from a bond
     * @param _id Bond NFT id
     * @return address claimed tigAsset address
     */
    function claim(
        uint256 _id
    ) public returns (address) {
        claimGovFees();
        (uint _amount, address _tigAsset) = bondNFT.claim(_id, msg.sender);
        IERC20(_tigAsset).transfer(msg.sender, _amount);
        return _tigAsset;
    }

    /**
     * @notice Claim pending rewards left over from a bond transfer
     * @param _tigAsset token address being claimed
     */
    function claimDebt(
        address _tigAsset
    ) external {
        claimGovFees();
        uint amount = bondNFT.claimDebt(msg.sender, _tigAsset);
        IERC20(_tigAsset).transfer(msg.sender, amount);
    }

    /**
     * @notice Lock up tokens to create a bond
     * @param _asset tigAsset being locked
     * @param _amount tigAsset amount
     * @param _period number of days to be locked for
     */
    function lock(
        address _asset,
        uint _amount,
        uint _period
    ) public {
        require(_period <= maxPeriod, "MAX PERIOD");
        require(_period >= minPeriod, "MIN PERIOD");
        require(allowedAssets[_asset], "!asset");

        claimGovFees();

        IERC20(_asset).transferFrom(msg.sender, address(this), _amount);
        totalLocked[_asset] += _amount;
        
        bondNFT.createLock( _asset, _amount, _period, msg.sender);
    }

    /**
     * @notice Reset the lock time and extend the period and/or token amount
     * @param _id Bond id being extended
     * @param _amount tigAsset amount being added
     * @param _period number of days being added
     */
    function extendLock(
        uint _id,
        uint _amount,
        uint _period
    ) public {
        address _asset = claim(_id);
        IERC20(_asset).transferFrom(msg.sender, address(this), _amount);
        bondNFT.extendLock(_id, _asset, _amount, _period, msg.sender);
    }

    /**
     * @notice Release the bond once it's expired
     * @param _id Bond id being released
     */
    function release(
        uint _id
    ) public {
        claimGovFees();
        (uint amount, uint lockAmount, address asset, address _owner) = bondNFT.release(_id, msg.sender);
        totalLocked[asset] -= lockAmount;
        IERC20(asset).transfer(_owner, amount);
    }

    /**
     * @notice Claim rewards from gov nfts and distribute them to bonds
     */
    function claimGovFees() public {
        address[] memory assets = bondNFT.getAssets();

        for (uint i=0; i < assets.length; i++) {
            uint balanceBefore = IERC20(assets[i]).balanceOf(address(this));
            IGovNFT(govNFT).claim(assets[i]);
            uint balanceAfter = IERC20(assets[i]).balanceOf(address(this));
            IERC20(assets[i]).approve(address(bondNFT), type(uint256).max);
            bondNFT.distribute(assets[i], balanceAfter - balanceBefore);
        }
    }

    /**
     * @notice Whitelist an asset
     * @param _tigAsset tigAsset token address
     * @param _isAllowed set tigAsset as allowed
     */
    function editAsset(
        address _tigAsset,
        bool _isAllowed
    ) external onlyOwner() {
        allowedAssets[_tigAsset] = _isAllowed;
    }

    /**
     * @notice Owner can retreive Gov NFTs
     * @param _ids array of gov nft ids
     */
    function sendNFTs(
        uint[] memory _ids
    ) external onlyOwner() {
        govNFT.safeTransferMany(msg.sender, _ids);
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

// File: MetaContext.sol
//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

contract MetaContext is Ownable {
    mapping(address => bool) private _isTrustedForwarder;

    function setTrustedForwarder(address _forwarder, bool _bool) external onlyOwner {
        _isTrustedForwarder[_forwarder] = _bool;
    }

    function isTrustedForwarder(address _forwarder) external view returns (bool) {
        return _isTrustedForwarder[_forwarder];
    }

    function _msgSender() internal view virtual override returns (address sender) {
        if (_isTrustedForwarder[msg.sender]) {
            // The assembly code is more direct than the Solidity version using `abi.decode`.
            /// @solidity memory-safe-assembly
            assembly {
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        } else {
            return super._msgSender();
        }
    }

    function _msgData() internal view virtual override returns (bytes calldata) {
        if (_isTrustedForwarder[msg.sender]) {
            return msg.data[:msg.data.length - 20];
        } else {
            return super._msgData();
        }
    }
}


// File: IBondNFT.sol
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IBondNFT {
    function createLock(
        address _asset,
        uint _amount,
        uint _period,
        address _owner
    ) external returns(uint id);

    function extendLock(
        uint _id,
        address _asset,
        uint _amount,
        uint _period,
        address _sender
    ) external;

    function claim(
        uint _id,
        address _owner
    ) external returns(uint amount, address tigAsset);

    function claimDebt(
        address _owner,
        address _tigAsset
    ) external returns(uint amount);

    function release(
        uint _id,
        address _releaser
    ) external returns(uint amount, uint lockAmount, address asset, address _owner);

    function distribute(
        address _tigAsset,
        uint _amount
    ) external;

    function ownerOf(uint _id) external view returns (uint256);
    
    function totalAssets() external view returns (uint256);
    function getAssets() external view returns (address[] memory);
}

// File: IGovNFT.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGovNFT {
    function distribute(address _tigAsset, uint _amount) external;
    function safeTransferMany(address _to, uint[] calldata _ids) external;
    function claim(address _tigAsset) external;
    function pending(address user, address _tigAsset) external view returns (uint256);
}

// File: ILayerZeroEndpoint.sol
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./ILayerZeroUserApplicationConfig.sol";

interface ILayerZeroEndpoint is ILayerZeroUserApplicationConfig {
    // @notice send a LayerZero message to the specified address at a LayerZero endpoint.
    // @param _dstChainId - the destination chain identifier
    // @param _destination - the address on destination chain (in bytes). address length/format may vary by chains
    // @param _payload - a custom bytes payload to send to the destination contract
    // @param _refundAddress - if the source transaction is cheaper than the amount of value passed, refund the additional amount to this address
    // @param _zroPaymentAddress - the address of the ZRO token holder who would pay for the transaction
    // @param _adapterParams - parameters for custom functionality. e.g. receive airdropped native gas from the relayer on destination
    function send(uint16 _dstChainId, bytes calldata _destination, bytes calldata _payload, address payable _refundAddress, address _zroPaymentAddress, bytes calldata _adapterParams) external payable;

    // @notice used by the messaging library to publish verified payload
    // @param _srcChainId - the source chain identifier
    // @param _srcAddress - the source contract (as bytes) at the source chain
    // @param _dstAddress - the address on destination chain
    // @param _nonce - the unbound message ordering nonce
    // @param _gasLimit - the gas limit for external contract execution
    // @param _payload - verified payload to send to the destination contract
    function receivePayload(uint16 _srcChainId, bytes calldata _srcAddress, address _dstAddress, uint64 _nonce, uint _gasLimit, bytes calldata _payload) external;

    // @notice get the inboundNonce of a receiver from a source chain which could be EVM or non-EVM chain
    // @param _srcChainId - the source chain identifier
    // @param _srcAddress - the source chain contract address
    function getInboundNonce(uint16 _srcChainId, bytes calldata _srcAddress) external view returns (uint64);

    // @notice get the outboundNonce from this source chain which, consequently, is always an EVM
    // @param _srcAddress - the source chain contract address
    function getOutboundNonce(uint16 _dstChainId, address _srcAddress) external view returns (uint64);

    // @notice gets a quote in source native gas, for the amount that send() requires to pay for message delivery
    // @param _dstChainId - the destination chain identifier
    // @param _userApplication - the user app address on this EVM chain
    // @param _payload - the custom message to send over LayerZero
    // @param _payInZRO - if false, user app pays the protocol fee in native token
    // @param _adapterParam - parameters for the adapter service, e.g. send some dust native token to dstChain
    function estimateFees(uint16 _dstChainId, address _userApplication, bytes calldata _payload, bool _payInZRO, bytes calldata _adapterParam) external view returns (uint nativeFee, uint zroFee);

    // @notice get this Endpoint's immutable source identifier
    function getChainId() external view returns (uint16);

    // @notice the interface to retry failed message on this Endpoint destination
    // @param _srcChainId - the source chain identifier
    // @param _srcAddress - the source chain contract address
    // @param _payload - the payload to be retried
    function retryPayload(uint16 _srcChainId, bytes calldata _srcAddress, bytes calldata _payload) external;

    // @notice query if any STORED payload (message blocking) at the endpoint.
    // @param _srcChainId - the source chain identifier
    // @param _srcAddress - the source chain contract address
    function hasStoredPayload(uint16 _srcChainId, bytes calldata _srcAddress) external view returns (bool);

    // @notice query if the _libraryAddress is valid for sending msgs.
    // @param _userApplication - the user app address on this EVM chain
    function getSendLibraryAddress(address _userApplication) external view returns (address);

    // @notice query if the _libraryAddress is valid for receiving msgs.
    // @param _userApplication - the user app address on this EVM chain
    function getReceiveLibraryAddress(address _userApplication) external view returns (address);

    // @notice query if the non-reentrancy guard for send() is on
    // @return true if the guard is on. false otherwise
    function isSendingPayload() external view returns (bool);

    // @notice query if the non-reentrancy guard for receive() is on
    // @return true if the guard is on. false otherwise
    function isReceivingPayload() external view returns (bool);

    // @notice get the configuration of the LayerZero messaging library of the specified version
    // @param _version - messaging library version
    // @param _chainId - the chainId for the pending config change
    // @param _userApplication - the contract address of the user application
    // @param _configType - type of configuration. every messaging library has its own convention.
    function getConfig(uint16 _version, uint16 _chainId, address _userApplication, uint _configType) external view returns (bytes memory);

    // @notice get the send() LayerZero messaging library version
    // @param _userApplication - the contract address of the user application
    function getSendVersion(address _userApplication) external view returns (uint16);

    // @notice get the lzReceive() LayerZero messaging library version
    // @param _userApplication - the contract address of the user application
    function getReceiveVersion(address _userApplication) external view returns (uint16);
}

// File: ILayerZeroReceiver.sol
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

interface ILayerZeroReceiver {
    // @notice LayerZero endpoint will invoke this function to deliver the message on the destination
    // @param _srcChainId - the source endpoint identifier
    // @param _srcAddress - the source sending contract address from the source chain
    // @param _nonce - the ordered message nonce
    // @param _payload - the signed payload is the UA bytes has encoded to be sent
    function lzReceive(uint16 _srcChainId, bytes calldata _srcAddress, uint64 _nonce, bytes calldata _payload) external;
}

// File: ILayerZeroUserApplicationConfig.sol
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

interface ILayerZeroUserApplicationConfig {
    // @notice set the configuration of the LayerZero messaging library of the specified version
    // @param _version - messaging library version
    // @param _chainId - the chainId for the pending config change
    // @param _configType - type of configuration. every messaging library has its own convention.
    // @param _config - configuration in the bytes. can encode arbitrary content.
    function setConfig(uint16 _version, uint16 _chainId, uint _configType, bytes calldata _config) external;

    // @notice set the send() LayerZero messaging library version to _version
    // @param _version - new messaging library version
    function setSendVersion(uint16 _version) external;

    // @notice set the lzReceive() LayerZero messaging library version to _version
    // @param _version - new messaging library version
    function setReceiveVersion(uint16 _version) external;

    // @notice Only when the UA needs to resume the message flow in blocking mode and clear the stored payload
    // @param _srcChainId - the chainId of the source chain
    // @param _srcAddress - the contract address of the source contract at the source chain
    function forceResumeReceive(uint16 _srcChainId, bytes calldata _srcAddress) external;
}

// File: IPairsContract.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IPairsContract {

    struct Asset {
        string name;
        address chainlinkFeed;
        uint256 minLeverage;
        uint256 maxLeverage;
        uint256 feeMultiplier;
        uint256 baseFundingRate;
    }

    struct OpenInterest {
        uint256 longOi;
        uint256 shortOi;
        uint256 maxOi;
    }

    function allowedAsset(uint) external view returns (bool);
    function idToAsset(uint256 _asset) external view returns (Asset memory);
    function idToOi(uint256 _asset, address _tigAsset) external view returns (OpenInterest memory);
    function setAssetBaseFundingRate(uint256 _asset, uint256 _baseFundingRate) external;
    function modifyLongOi(uint256 _asset, address _tigAsset, bool _onOpen, uint256 _amount) external;
    function modifyShortOi(uint256 _asset, address _tigAsset, bool _onOpen, uint256 _amount) external;
}

// File: IPosition.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IPosition {

    struct Trade {
        uint margin;
        uint leverage;
        uint asset;
        bool direction;
        uint price;
        uint tpPrice;
        uint slPrice;
        uint orderType;
        address trader;
        uint id;
        address tigAsset;
        int accInterest;
    }

    struct MintTrade {
        address account;
        uint256 margin;
        uint256 leverage;
        uint256 asset;
        bool direction;
        uint256 price;
        uint256 tp;
        uint256 sl;
        uint256 orderType;
        address tigAsset;
    }

    function trades(uint256) external view returns (Trade memory);
    function executeLimitOrder(uint256 _id, uint256 _price, uint256 _newMargin) external;
    function modifyMargin(uint256 _id, uint256 _newMargin, uint256 _newLeverage) external;
    function addToPosition(uint256 _id, uint256 _newMargin, uint256 _newPrice) external;
    function reducePosition(uint256 _id, uint256 _newMargin) external;
    function assetOpenPositions(uint256 _asset) external view returns (uint256[] calldata);
    function assetOpenPositionsIndexes(uint256 _asset, uint256 _id) external view returns (uint256);
    function limitOrders(uint256 _asset) external view returns (uint256[] memory);
    function limitOrderIndexes(uint256 _asset, uint256 _id) external view returns (uint256);
    function assetOpenPositionsLength(uint256 _asset) external view returns (uint256);
    function limitOrdersLength(uint256 _asset) external view returns (uint256);
    function ownerOf(uint _id) external view returns (address);
    function mint(MintTrade memory _mintTrade) external;
    function burn(uint _id) external;
    function modifyTp(uint _id, uint _tpPrice) external;
    function modifySl(uint _id, uint _slPrice) external;
    function getCount() external view returns (uint);
    function updateFunding(uint256 _asset, address _tigAsset, uint256 _longOi, uint256 _shortOi, uint256 _baseFundingRate, uint256 _vaultFundingPercent) external;
    function setAccInterest(uint256 _id) external;
}

// File: IReferrals.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IReferrals {

    function createReferralCode(bytes32 _hash) external;
    function setReferred(address _referredTrader, bytes32 _hash) external;
    function getReferred(address _trader) external view returns (bytes32);
    function getReferral(bytes32 _hash) external view returns (address);
    
}

// File: IStableVault.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IStableVault {
    function deposit(address, uint) external;
    function withdraw(address, uint) external returns (uint256);
    function allowed(address) external view returns (bool);
    function stable() external view returns (address);
}

// File: ITrading.sol
// SPDX-License-Identifier: MIT

import "../utils/TradingLibrary.sol";

pragma solidity ^0.8.0;

interface ITrading {

    struct TradeInfo {
        uint256 margin;
        address marginAsset;
        address stableVault;
        uint256 leverage;
        uint256 asset;
        bool direction;
        uint256 tpPrice;
        uint256 slPrice;
        bytes32 referral;
    }

    struct ERC20PermitData {
        uint256 deadline;
        uint256 amount;
        uint8 v;
        bytes32 r;
        bytes32 s;
        bool usePermit;
    }

    function initiateMarketOrder(
        TradeInfo calldata _tradeInfo,
        PriceData calldata _priceData,
        bytes calldata _signature,
        ERC20PermitData calldata _permitData,
        address _trader
    ) external;

    function initiateCloseOrder(
        uint _id,
        uint _percent,
        PriceData calldata _priceData,
        bytes calldata _signature,
        address _stableVault,
        address _outputToken,
        address _trader
    ) external;

    function addMargin(
        uint256 _id,
        address _marginAsset,
        address _stableVault,
        uint256 _addMargin,
        ERC20PermitData calldata _permitData,
        address _trader
    ) external;

    function removeMargin(
        uint256 _id,
        address _stableVault,
        address _outputToken,
        uint256 _removeMargin,
        PriceData calldata _priceData,
        bytes calldata _signature,
        address _trader
    ) external;

    function addToPosition(
        uint _id,
        uint _addMargin,
        PriceData calldata _priceData,
        bytes calldata _signature,
        address _stableVault,
        address _marginAsset,
        ERC20PermitData calldata _permitData,
        address _trader
    ) external;

    function initiateLimitOrder(
        TradeInfo calldata _tradeInfo,
        uint256 _orderType, // 1 limit, 2 momentum
        uint256 _price,
        ERC20PermitData calldata _permitData,
        address _trader
    ) external;

    function cancelLimitOrder(
        uint256 _id,
        address _trader
    ) external;

    function updateTpSl(
        bool _type, // true is TP
        uint _id,
        uint _limitPrice,
        PriceData calldata _priceData,
        bytes calldata _signature,
        address _trader
    ) external;

    function executeLimitOrder(
        uint _id, 
        PriceData calldata _priceData,
        bytes calldata _signature
    ) external;

    function liquidatePosition(
        uint _id,
        PriceData calldata _priceData,
        bytes calldata _signature
    ) external;

    function limitClose(
        uint _id,
        bool _tp,
        PriceData calldata _priceData,
        bytes calldata _signature
    ) external;
}