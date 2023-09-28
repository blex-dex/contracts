// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;
pragma experimental ABIEncoderV2;

import {Position} from "./../../position/PositionStruct.sol";
import {MarketDataTypes} from "./../../market/MarketDataTypes.sol";
import {FeeRouterLib} from "../../fee/lib/FeeRouterLib.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";

library PositionSubMgrLib {
    using SafeCast for int256;
    using SafeCast for uint256;
    using MarketDataTypes for int256[];
    error TotalFeesLtZero();

    /**
     * @param _originFees Original fee data to be collected
     * @return withdrawAmount The total fee amount to be withdrawn to the market
     * @return afterFees The actual fee array returned after considering fee priorities and profit/loss data
     */
    function calculateWithdrawFromFeeVault(
        int256[] memory _originFees
    ) internal pure returns (int256 withdrawAmount, int256[] memory afterFees) {
        int256 fundFee = _originFees[uint8(FeeRouterLib.FeeType.FundFee)];
        if (fundFee >= 0) return (0, _originFees);
        afterFees = new int256[](_originFees.length);
        for (uint i = 0; i < _originFees.length; i++) {
            afterFees[i] = _originFees[i];
        }
        afterFees[uint8(FeeRouterLib.FeeType.FundFee)] = 0;
        return (-fundFee, afterFees);
    }

    /**
     *
     * @param _position User position
     * @param dPNL Profit and loss
     * @param fees Original fee data
     */
    function calculateTransToFeeVault(
        Position.Props memory _position,
        int256 dPNL,
        int256 fees
    ) internal pure returns (int256 transferToFeeVaultAmount) {
        int256 remain = _position.collateral.toInt256() + dPNL; // Calculate remaining amount
        if (fees < 0) revert TotalFeesLtZero(); // Throw an exception if fees are less than 0
        if (remain > 0) return SignedMath.min(remain, fees); // Return the smaller of remaining amount and fees if remaining amount is greater than 0
        // Default to returning 0
    }

    function calculateTransToVault(
        int256 collateral,
        int256 dPNL
    ) internal pure returns (int256) {
        return collateral + dPNL <= 0 ? collateral : -dPNL;
    }

    function calculateTransToUser(
        MarketDataTypes.UpdatePositionInputs memory _params,
        Position.Props memory _position,
        int256 dPNL,
        int256 fees
    ) internal pure returns (int256) {
        bool isCloseAll = _position.size == _params._sizeDelta;
        if (isCloseAll) _params.collateralDelta = _position.collateral;
        if (_position.collateral.toInt256() + dPNL - fees <= 0) return 0; // Liquidated
        if (_params.collateralDelta.toInt256() + dPNL - fees > 0)
            return _params.collateralDelta.toInt256() + dPNL - fees;
        if (_params.collateralDelta.toInt256() + dPNL - fees <= 0) return 0; // Includes deleveraging without maintaining leverage
        return _params.collateralDelta.toInt256() + dPNL;
    }

    function calculateNewCollateral(
        MarketDataTypes.UpdatePositionInputs memory _params,
        Position.Props memory _position,
        int256 dPNL,
        int256 fees
    ) internal pure returns (uint256) {
        bool isCloseAll = _position.size == _params._sizeDelta;
        if (isCloseAll) _params.collateralDelta = _position.collateral;
        if (_params.liqState > 0 || isCloseAll) return 0; // Return 0 if in liquidation state or fully closed
        if (_position.collateral.toInt256() + dPNL - fees <= 0) return 0; // Return 0 if collateral plus PNL minus fees is less than or equal to 0
        if (_params.collateralDelta.toInt256() + dPNL - fees < 0)
            return (_position.collateral.toInt256() + dPNL - fees).toUint256(); // Return the value of collateral plus PNL minus fees if collateral delta plus PNL minus fees is less than 0
        return _position.collateral - _params.collateralDelta; // Otherwise, return the value of collateral minus collateral delta
    }

    /**
     * Calculate user fund fee loss
     * @param coll User position collateral 18 decimals
     * @param pnl Profit and loss amount 18 decimals
     * @param fs Fee array 18 decimals
     * @return fundFeeLoss Fund fee loss 18 decimals
     */
    function calculateFundFeeLoss(
        int256 coll, // User position collateral
        int256 pnl, // Profit and loss amount
        int256[] memory fs // Fee array
    ) internal pure returns (uint256 fundFeeLoss) {
        int256 fFee = fs[uint8(FeeRouterLib.FeeType.FundFee)]; // Fund fee
        int256 remain = -fs[uint8(FeeRouterLib.FeeType.CloseFee)] + coll + pnl; // Remaining funds
        if (fFee > 0 && fFee > remain)
            return uint256(fFee - SignedMath.max(remain, 0)); // Calculate fund fee loss
    }

    struct DecreaseTransactionOuts {
        int256 transToFeeVault;
        int256 transToVault;
        uint256 newCollateralUnsigned;
        int256 transToUser;
    }

    function calDecreaseTransactionValues(
        MarketDataTypes.UpdatePositionInputs memory _params,
        Position.Props memory _position,
        int256 dPNL,
        int256[] memory _originFees
    ) internal pure returns (DecreaseTransactionOuts memory outs) {
        // Calculate withdrawal amount and remaining fees from the fee vault
        (int256 withdrawAmount, int256[] memory afterFees) = PositionSubMgrLib
            .calculateWithdrawFromFeeVault(_originFees);
        int256 totalFees = afterFees.totoalFees();
        // If withdrawal amount is greater than 0, increase position collateral
        if (withdrawAmount > 0) _position.collateral += uint256(withdrawAmount);
        // Calculate the amount to transfer to the fee vault
        outs.transToFeeVault =
            calculateTransToFeeVault(_position, dPNL, totalFees) -
            withdrawAmount;
        // Calculate the amount to transfer to the vault
        outs.transToVault = calculateTransToVault(
            _position.collateral.toInt256(),
            dPNL
        );
        // Calculate the new collateral amount (unsigned)
        outs.newCollateralUnsigned = calculateNewCollateral(
            _params,
            _position,
            dPNL,
            totalFees
        );
        // Calculate the amount to transfer to the user
        outs.transToUser = calculateTransToUser(
            _params,
            _position,
            dPNL,
            totalFees
        );
    }
}
