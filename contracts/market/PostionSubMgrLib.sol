// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;
pragma experimental ABIEncoderV2;

import {Position} from "./../position/PositionStruct.sol";
import {MarketDataTypes} from "./../market/MarketDataTypes.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

library PositionSubMgrLib {
    using SafeCast for int256;
    using SafeCast for uint256;

    function calculateTransToFeeVault(
        Position.Props memory _position,
        int256 dPNL,
        int256 fees,
        bool isCloseAll
    ) internal pure returns (int256) {
        if (fees > _position.collateral.toInt256() + dPNL) {
            if (_position.collateral.toInt256() + dPNL > 0)
                return _position.collateral.toInt256() + dPNL;
            else {
                 require(isCloseAll,"PositionSubMgr:position under liq");
                 return 0;
            }
               
        }
        return fees;
    }

    function calculateTransToVault(
        Position.Props memory _position,
        int256 dPNL
    ) internal pure returns (int256) {
        if (_position.collateral.toInt256() + dPNL <= 0)
            return _position.collateral.toInt256();
        return -1 * dPNL;
    }

    function calculateTransToUser(
        MarketDataTypes.UpdatePositionInputs memory _params,
        Position.Props memory _position,
        int256 dPNL,
        int256 fees
    ) internal pure returns (int256) {
        bool isCloseAll = _position.size == _params._sizeDelta;
        if (isCloseAll) _params.collateralDelta = _position.collateral;
        if (_position.collateral.toInt256() + dPNL - fees <= 0) return 0;
        if (_params.collateralDelta.toInt256() + dPNL - fees > 0)
            return _params.collateralDelta.toInt256() + dPNL - fees;
        if (_params.collateralDelta.toInt256() + dPNL - fees <= 0) return 0;
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
        if (_params.liqState > 0 || isCloseAll) return 0;
        if (_position.collateral.toInt256() + dPNL - fees <= 0) return 0;
        if (_params.collateralDelta.toInt256() + dPNL - fees > 0)
            return _position.collateral - _params.collateralDelta;
        if (_params.collateralDelta.toInt256() + dPNL - fees < 0)
            return (_position.collateral.toInt256() + dPNL - fees).toUint256();
        return _position.collateral - _params.collateralDelta;
    }
}
