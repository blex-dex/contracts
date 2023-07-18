// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;
pragma experimental ABIEncoderV2;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "../order/interface/IOrderBook.sol";
import {PositionSubMgrLib} from "../market/PostionSubMgrLib.sol";

import {IPrice} from "../oracle/interfaces/IPrice.sol";
import {IPositionBook} from "../position/interfaces/IPositionBook.sol";
import {Calc} from "../utils/Calc.sol";
import {IFeeRouter} from "../fee/interfaces/IFeeRouter.sol";
import {IVaultRouter} from "../vault/interfaces/IVaultRouter.sol";
import {MarketStorage} from "./MarketStorage.sol";
import {IMarketValid} from "./interfaces/IMarketValid.sol";
import {MarketLib} from "./MarketLib.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IMarketCallBackIntl.sol";
import {IReferral} from "../referral/interfaces/IReferral.sol";
import "./../position/PositionStruct.sol";
import {TransferHelper, IERC20Decimals} from "./../utils/TransferHelper.sol";
import "../ac/Ac.sol";

contract PositionSubMgr is MarketStorage, ReentrancyGuard, Ac {
    using Calc for uint256;
    using Calc for int256;
    using SafeCast for int256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;
    using Order for Order.Props;
    using MarketLib for uint16;
    using MarketLib for uint256;
    using MarketDataTypes for MarketDataTypes.UpdateOrderInputs;
    using MarketDataTypes for MarketDataTypes.UpdatePositionInputs;
    using MarketDataTypes for int256[];

    constructor() Ac(address(0)) {}

    /**
     * @dev Called by `MarketRouter`.Decreases a position.
     * @param _vars The input variables for updating the position.
     */
    function decreasePosition(
        MarketDataTypes.UpdatePositionInputs memory _vars
    ) external {
        require(_vars.isOpen == false, "PositionSubMgr:isOpen");
        require(
            !_vars._isExec && 0 == _vars._fromOrder,
            "PositionSubMgr:wrong isexec/fromorder"
        );

        // Set a default slippage value if not provided
        if (_vars._slippage == 0) _vars._slippage = 30;
        if (_vars._sizeDelta > 0)
            _vars._oraclePrice = _getClosePrice(_vars._isLong);
        Position.Props memory _position = positionBook.getPosition(
            _vars._account,
            _vars._oraclePrice,
            _vars._isLong
        );

        // Calculate the decrease delta collateral if the size delta is greater than zero
        if (_vars._sizeDelta > 0)
            _vars.collateralDelta = MarketLib.getDecreaseDeltaCollateral(
                _vars.isKeepLev(),
                _position.size,
                _vars._sizeDelta,
                _position.collateral
            );

        // Call the private function to perform the decrease position operation
        _decreasePosition(_vars, _position);
    }

    /**
     * @dev Called by `AutoLiquidate`.Liquidates positions for multiple accounts.
     * @param accounts The array of accounts to liquidate positions for.
     * @param _isLong Boolean flag indicating whether the liquidation is for long positions.
     */
    function liquidatePositions(
        address[] memory accounts,
        bool _isLong
    ) external {
        uint256 _len = accounts.length;

        for (uint256 i; i < _len; ) {
            address _account = accounts[i];

            // Liquidate position for the specified account and flag
            _liquidatePosition(_account, _isLong);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Performs the liquidation of a position for a specific account.
     * @param _account The address of the account to liquidate the position for.
     * @param _isLong Boolean flag indicating whether the liquidation is for long positions.
     * @dev This function is private and should not be called directly from outside the contract.
     */
    function _liquidatePosition(address _account, bool _isLong) private {
        MarketDataTypes.UpdatePositionInputs memory _vars;

        // Initialize the variables for the liquidation process
        _vars.initialize(false);
        _vars._oraclePrice = _getClosePrice(_isLong);
        _vars._account = _account;
        _vars._isExec = true;
        _vars._isLong = _isLong;

        // Get the position details from the position book
        Position.Props memory _position = positionBook.getPosition(
            _account,
            _vars._oraclePrice,
            _isLong
        );

        // Calculate the changes in size and collateral for the liquidation
        _vars._sizeDelta = _position.size;
        _vars.collateralDelta = _position.collateral;
        _vars._market = address(this);

        // Determine the liquidation state using the 'isLiquidate' function from the '_valid' contract
        _vars.liqState = uint8(
            _valid().isLiquidate(
                _account,
                address(this),
                _isLong,
                positionBook,
                feeRouter,
                _vars._oraclePrice
            )
        );

        // Ensure that the liquidation state is greater than 0, indicating a valid liquidation
        require(_vars.liqState > 0, "PositionSubMgr:should'nt liq");

        // Decrease the position using the '_decreasePosition' function
        _decreasePosition(_vars, _position);
    }

    /**
     * @dev Performs the decrease position operation.
     * @param _params The input parameters for updating the position.
     * @param _position The position details.
     */
    function _decreasePosition(
        MarketDataTypes.UpdatePositionInputs memory _params,
        Position.Props memory _position
    ) private {
        // Return if the position size is zero or the account is invalid
        if (_position.size == 0 || _params._account == address(0)) return;

        // Update the cumulative funding rate
        MarketLib._updateCumulativeFundingRate(positionBook, feeRouter);

        // Check if the position is being closed entirely
        bool isCloseAll = _position.size == _params._sizeDelta;

        if (isCloseAll) {
            // Determine the cancellation reason based on the liquidation state
            CancelReason reason = CancelReason.PositionClosed;
            if (_params.liqState == 1) reason = CancelReason.Liquidation;
            else if (_params.liqState == 2)
                reason = CancelReason.LeverageLiquidation;

            // Get the order book based on the position type (long/short)
            IOrderBook ob = _params._isLong ? orderBookLong : orderBookShort;

            // Remove orders associated with the account
            Order.Props[] memory _ordersDeleted = ob.removeByAccount(
                false,
                _params._account
            );

            // Iterate over the deleted orders and perform necessary actions
            for (uint i = 0; i < _ordersDeleted.length; i++) {
                Order.Props memory _orderDeleted = _ordersDeleted[i];
                if (_orderDeleted.account == address(0)) {
                    continue;
                }
                _params.execNum += 1;

                // Perform actions after deleting the order
                MarketLib.afterDeleteOrder(
                    MarketOrderCallBackIntl.DeleteOrderEvent(
                        _orderDeleted,
                        _params,
                        uint8(reason),
                        "",
                        0
                    ),
                    pluginGasLimit,
                    plugins,
                    collateralToken,
                    address(this)
                );
            }
        }
        _params._market = address(this);

        int256[] memory _fees = feeRouter.getFees(_params, _position);

        IMarketValid mv = _valid();
        if (_params._sizeDelta == 0) {
            mv.validCollateralDelta(
                4,
                _position.collateral,
                _params.collateralDelta,
                _position.size,
                0,
                0
            );
        } else {
            mv.validPosition(_params, _position, _fees);
        }

        int256 dPnl;
        if (_params._sizeDelta > 0) {
            dPnl = positionBook.getPNL(
                _params._account,
                _params._sizeDelta,
                _params._oraclePrice,
                _params._isLong
            );
        }
        _position.realisedPnl = dPnl;

        int256 feesTotal = _fees.totoalFees();

        (uint256 newCollateralUnsigned, ) = _decreaseTransaction(
            _params,
            _position,
            dPnl,
            feesTotal
        );

        int256 _nowFundRate = feeRouter.cumulativeFundingRates(
            address(this),
            _params._isLong
        );
        // 5. 调用position.sol, 减仓
        IVaultRouter(vaultRouter).repayToVault(
            TransferHelper.formatCollateral(
                _params._sizeDelta,
                IERC20Decimals(collateralToken).decimals()
            )
        );

        Position.Props memory result = positionBook.decreasePosition(
            _params._account,
            isCloseAll
                ? _position.collateral
                : (_position.collateral - newCollateralUnsigned),
            _params._sizeDelta,
            _nowFundRate,
            _params._isLong
        );

        _valid().validLev(result.size, result.collateral);

        if (
            (_params.liqState != 1 || _params.liqState != 2) &&
            _params._sizeDelta != _position.size
        ) validLiq(_params._account, _params._isLong);

        feeRouter.collectFees(_params._account, collateralToken, _fees);

        MarketLib.afterUpdatePosition(
            MarketPositionCallBackIntl.UpdatePositionEvent(
                _params,
                _position,
                _fees,
                collateralToken,
                indexToken,
                int256(
                    isCloseAll
                        ? _position.collateral
                        : (_position.collateral - newCollateralUnsigned)
                )
            ),
            pluginGasLimit,
            plugins,
            collateralToken,
            address(this)
        );
    }

    function _transferToVault(
        IERC20 _collateralTokenERC20,
        uint256 _amount
    ) private {
        _amount = TransferHelper.formatCollateral(
            _amount,
            collateralTokenDigits
        );
        _collateralTokenERC20.approve(vaultRouter, _amount);
        IVaultRouter(vaultRouter).transferToVault(address(this), _amount);
    }

    
    function _decreaseTransaction(
        MarketDataTypes.UpdatePositionInputs memory _params,
        Position.Props memory _position,
        int256 dPNL,
        int256 fees
    ) private returns (uint256 newCollateralUnsigned, int256 transToUser) {
        address _collateralToken = collateralToken;
        IERC20 _collateralTokenERC20 = IERC20(_collateralToken);
        //================================================
        // fee vault transactions
        //================================================
        int256 _transToFeeVault = PositionSubMgrLib.calculateTransToFeeVault(
            _position,
            dPNL,
            fees
        );
        if (_transToFeeVault > 0) {
            uint256 amount = TransferHelper.formatCollateral(
                _transToFeeVault.toUint256(),
                IERC20Decimals(collateralToken).decimals()
            );
            IERC20(collateralToken).approve(address(feeRouter), amount);
        }

        //================================================
        // vault transactions
        //================================================
        int256 _transToVault = PositionSubMgrLib.calculateTransToVault(
            _position,
            dPNL
        );
        if (_transToVault > 0)
            _transferToVault(_collateralTokenERC20, uint256(_transToVault));
        else
            MarketLib.vaultWithdraw(
                _collateralToken,
                address(this),
                -_transToVault,
                collateralTokenDigits,
                vaultRouter
            );
        //================================================
        // newCollateral
        //================================================
        newCollateralUnsigned = PositionSubMgrLib.calculateNewCollateral(
            _params,
            _position,
            dPNL,
            fees
        );

        //================================================
        // transToUser
        //================================================
        transToUser = PositionSubMgrLib.calculateTransToUser(
            _params,
            _position,
            dPNL,
            fees
        );
        if (transToUser > 0)
            TransferHelper.transferOut(
                _collateralToken,
                _params._account,
                uint256(transToUser)
            );
    }

    function decreasePositionFromOrder(
        Order.Props memory order,
        MarketDataTypes.UpdatePositionInputs memory _params
    ) private {
        _params._oraclePrice = _getClosePrice(_params._isLong);
        Position.Props memory _position = positionBook.getPosition(
            order.account,
            _params._oraclePrice,
            _params._isLong
        );

        // 先删掉要执行的订单
        Order.Props[] memory ods = (
            _params._isLong ? orderBookLong : orderBookShort
        ).remove(order.getKey(), false);
        require(ods[0].account != address(0), "PositionSubMgr:!account");

        // 遍历要删除的订单, 并且emit事件
        for (uint i = 0; i < ods.length; i++) {
            Order.Props memory od = ods[i];
            if (address(0) == od.account) continue;
            MarketLib.afterDeleteOrder(
                MarketOrderCallBackIntl.DeleteOrderEvent(
                    od,
                    _params,
                    uint8(
                        i == 0
                            ? CancelReason.Executed
                            : CancelReason.TpAndSlExecuted
                    ), // Executed, TpAndSlExecuted, 3, 4
                    "",
                    i == 0
                        ? (_position.realisedPnl *
                            _params._sizeDelta.toInt256()) /
                            _position.size.toInt256()
                        : int256(0)
                ),
                pluginGasLimit,
                plugins,
                collateralToken,
                address(this)
            );
            if (i == 0) _params.execNum += 1;
        }

        _decreasePosition(_params, _position);
    }

    function _valid() internal view returns (IMarketValid) {
        return IMarketValid(marketValid);
    }

    function execOrderKey(
        Order.Props memory order,
        MarketDataTypes.UpdatePositionInputs memory _params
    ) external {
        order.validOrderAccountAndID();
        require(_params.isOpen == false, "PositionSubMgr:invalid isOpen");
        validLiq(order.account, _params._isLong);

        decreasePositionFromOrder(order, _params);
    }

    function validLiq(address acc, bool _isLong) private view {
        require(
            _valid().isLiquidate(
                acc,
                address(this),
                _isLong,
                positionBook,
                feeRouter,
                _getClosePrice(_isLong)
            ) == 0,
            "PositionSubMgr:position under liq"
        );
    }

    function _getClosePrice(bool _isLong) private view returns (uint256 p) {
        p = IPrice(priceFeed).getPrice(indexToken, !_isLong);
    }
}
