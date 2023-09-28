// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { MarketDataTypes } from "../../market/MarketDataTypes.sol";
import { Position } from "../../position/PositionStruct.sol";
import { Precision } from "../../utils/TransferHelper.sol";

// import "../market/interfaces/IMarketFactory.sol";

library FeeRouterLib {
    using SafeCast for int256;

    enum FeeType {
        OpenFee,     // 0
        CloseFee,    // 1
        FundFee,     // 2
        ExecFee,     // 3
        LiqFee,      // 4
        BuyLpFee,    // 5
        SellLpFee,   // 6
        ExtraFee0,
        ExtraFee1,
        ExtraFee2,
        ExtraFee3,
        ExtraFee4,
        Counter
    }
    uint256 public constant FEE_RATE_PRECISION = Precision.FEE_RATE_PRECISION;

    /**
     * This function only calculates the fees to be collected based on the current position, 
     * excluding the order of collection and whether they can be collected.
     * @param params User input parameters
     * @param _fundFee Funding fee
     * @param feeAndRates Fee rate parameters
     */
    function getFees(
        MarketDataTypes.UpdatePositionInputs memory params,
        int256 _fundFee,
        mapping(address => mapping(uint8 => uint256)) storage feeAndRates
    ) internal view returns (int256[] memory fees) {
        fees = new int256[](uint8(FeeType.Counter));
        address _market = params._market;
        fees[uint8(FeeType.FundFee)] = _fundFee;

        if (params._sizeDelta == 0 && params.collateralDelta != 0) {
            return fees;
        }

        // Open position
        if (params.isOpen) {
            fees[uint8(FeeType.OpenFee)] = int256(
                getFee(
                    _market,
                    params._sizeDelta,
                    uint8(FeeType.OpenFee),
                    feeAndRates
                )
            );
        } else {
            // Close position
            fees[uint8(FeeType.CloseFee)] = int256(
                getFee(
                    _market,
                    params._sizeDelta,
                    uint8(FeeType.CloseFee),
                    feeAndRates
                )
            );

            // Liquidate position
            if (params.liqState == 1) {
                uint256 _fee = feeAndRates[_market][uint8(FeeType.LiqFee)];
                fees[uint8(FeeType.LiqFee)] = int256(_fee);
            }
        }
        if (params.execNum > 0) {
            // Execution fee
            uint256 _fee = feeAndRates[_market][uint8(FeeType.ExecFee)];
            _fee = _fee * params.execNum;

            fees[uint8(FeeType.ExecFee)] = int256(_fee);
        }
        return fees;
    }

    /**
     * @dev Calculates the fee for a given size delta and fee kind.
     * @param market The address of the market.
     * @param sizeDelta The change in position size.
     * @param kind The fee kind.
     * @return The fee amount.
     */
    function getFee(
        address market,
        uint256 sizeDelta,
        uint8 kind,
        mapping(address => mapping(uint8 => uint256)) storage feeAndRates
    ) internal view returns (uint256) {
        if (sizeDelta == 0) {
            return 0;
        }

        uint256 _point = feeAndRates[market][kind];
        if (_point == 0) {
            _point = 100000;
        }

        uint256 _size = (sizeDelta * (FEE_RATE_PRECISION - _point)) /
            FEE_RATE_PRECISION;
        return sizeDelta - _size;
    }
}
