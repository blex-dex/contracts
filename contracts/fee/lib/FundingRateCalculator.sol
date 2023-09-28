// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "../../utils/Calc.sol";

library FundingRateCalculator {
    using SafeCast for uint256;
    using SafeCast for int256;

    uint256 public constant MIN_FUNDING_INTERVAL_3600 = 1 hours; // Minimum funding interval of 1 hour
    uint256 public constant ONE_WITH_8_DECIMALS = 10 ** 8; // 0.0001666666 * 100000000
    uint256 public constant BASIS_INTERVAL_HOUR_24 = 24; // 24 hours in a day
    uint256 public constant DEFAULT_RATE_DIVISOR_100 = 100; // Default rate divisor of 100

    enum CfgIdx {
        Skiptime,
        MaxFRatePerDay,
        FRateFactor,
        MaxFRate,
        MinFRate,
        FeeLoss,
        MinFundingInterval,
        MinorityFRate,
        MinCFRate,
        FundingFeeLossOffLimit, // Deduction limit for funding fee not exceeding 10% of the current funding fee income (configured in admin)
        Counter
    }

    event UpdateCalFundRate(
        address indexed market,
        int256 longRate,
        int256 shortRate
    );
    event UpdateLastCalTime(address indexed market, uint256 timestamp);
    event AddNegativeFeeLoss(
        address indexed market,
        uint256 amount,
        uint256 lossBefore,
        uint256 lossAfter
    );
    event AddPositiveFeeLoss(
        address indexed market,
        uint256 deductAmount,
        uint256 lossBefore,
        uint256 lossAfter
    );

    /** Calculate the maximum unit funding rate limit */
    /**
     *
     * @param openInterest18Decimals 18 zeros
     * @param aumWith18Decimals 18 zeros
     * @param maxFRatePerDayWith8Decimals 8 zeros
     * @param fundingIntervalSeconds seconds
     */
    function calculateMaxFundingRate(
        uint256 openInterest18Decimals,
        uint256 aumWith18Decimals,
        uint256 maxFRatePerDayWith8Decimals,
        uint256 fundingIntervalSeconds
    ) internal pure returns (uint256) {
        uint256 _maxFRate = (openInterest18Decimals *
            fundingIntervalSeconds *
            maxFRatePerDayWith8Decimals *
            ONE_WITH_8_DECIMALS) /
            aumWith18Decimals /
            BASIS_INTERVAL_HOUR_24 /
            ONE_WITH_8_DECIMALS /
            MIN_FUNDING_INTERVAL_3600;
        return _maxFRate;
    }

    /** Calculate the unit funding rate (with maximum and minimum limits) */
    function capFundingRateByLimits(
        uint256 long,
        uint256 short,
        uint256 maxFRate,
        uint256 minFRate,
        uint256 calculatedMaxFRate8Decimals,
        uint256 fRate,
        uint256 minority
    ) internal pure returns (uint256, uint256) {
        //- When FRate<=minFRate: FRate=minFRate (eliminate bilateral MinFRate).
        /*
        if (fRate <= minFRate) return (minFRate, minFRate);
         */
        maxFRate = maxFRate == 0 ? calculatedMaxFRate8Decimals : maxFRate;
        if (fRate > maxFRate) fRate = maxFRate;
        if (fRate < minFRate) fRate = minFRate;
        return long >= short ? (fRate, minority) : (minority, fRate);
    }

    /**
     * _getCumulativeFundingRateDelta
     * @param _longRate with 8 decimals
     * @param _shortRate with 8 decimals
     * @param _calcIntervalSeconds calculative interval seconds
     * @param _lastCalcTime last calculated time
     * @param _blockTimeStamp block time stamp
     * @param _intervals intervals
     * @return _longCumulativeRates long Cumulative Rates with 8 decimals
     * @return _shortCumulativeRates short Cumulative Rates with 8 decimals
     * @return _roundedTime
     */
    function _getCumulativeFundingRateDelta(
        uint256 _longRate,
        uint256 _shortRate,
        uint256 _calcIntervalSeconds, // 3600 seconds
        uint256 _lastCalcTime,
        uint256 _blockTimeStamp,
        uint256 _intervals
    )
        internal
        pure
        returns (
            uint256 _longCumulativeRates,
            uint256 _shortCumulativeRates,
            uint256 _roundedTime
        )
    {
        if (_intervals == 0 || _calcIntervalSeconds == 0) {
            return (0, 0, _lastCalcTime);
        }

        _longCumulativeRates = _longRate * _intervals;
        _shortCumulativeRates = _shortRate * _intervals;
        _roundedTime =
            uint256(_intervals) *
            _calcIntervalSeconds +
            _lastCalcTime;
    }

    /** Calculate the user's funding fee */
    function calUserFundingFee(
        uint256 size,
        int256 entryFundingRate,
        int256 cumRates
    ) internal pure returns (int256) {
        // Calculate the funding fee by multiplying the position size with the rate.
        // - When the fee collection period has a negative funding fee position of 0, and the positive funding fee is >0, the negative funding fee rate is <0; the collected funding fee is used to offset losses, and no distribution is made when there are no losses.
        // TODO: Needs discussion with painter
        return
            (int256(size) * (cumRates - entryFundingRate)) /
            int256(ONE_WITH_8_DECIMALS);
    }

    /** Calculate the funding fee formula */
    function calFeeRate(
        uint256 _longSizeWith18Decimals,
        uint256 _shortSizeWith18Decimals,
        uint256 _intervalSeconds,
        uint256 fRateFactorWith8Decimals
    ) internal pure returns (uint256) {
        // Calculate the absolute difference between longSize and shortSize.
        uint256 _size = Calc.abs(
            _longSizeWith18Decimals,
            _shortSizeWith18Decimals
        );
        uint256 _rate;
        if (_size != 0) {
            // Calculate the divisor by summing longSize and shortSize.
            uint256 _divisor = _longSizeWith18Decimals +
                _shortSizeWith18Decimals;

            // Calculate the fee rate.
            _rate = (_size * ONE_WITH_8_DECIMALS) / _divisor;

            // ((2000-1664)/(2000+1664) * 10**8)**2 * 3600 / (10**8) / 100 / 24 / 3600
            // 350
            _rate =
                ((_rate ** 2) * _intervalSeconds) /
                ONE_WITH_8_DECIMALS /
                DEFAULT_RATE_DIVISOR_100 /
                BASIS_INTERVAL_HOUR_24 /
                MIN_FUNDING_INTERVAL_3600;
            _rate = (_rate * fRateFactorWith8Decimals) / ONE_WITH_8_DECIMALS;
        }
        return _rate;
    }

    /**
     * Calculate CFRate
     * @param Long_CumFRate Cumulative funding rate for long positions with 8 decimal precision
     * @param Short_CumFRate Cumulative funding rate for short positions with 8 decimal precision
     * @param minCFRate Minimum CFRate limit, configured in the admin, with 8 decimal precision
     */
    function calCFRate(
        int256 Long_CumFRate,
        int256 Short_CumFRate,
        uint256 minCFRate
    ) internal pure returns (uint256 _CFRate) {
        // - Funding rate C_FRate: When the FRate of both long and short positions completes a calculation cycle (i.e., 8 FRates are calculated), the absolute difference between the CumFRates of long and short positions is the C_Frate.
        //   - C_FRate = |Long_CumFRate - Short_CumFRate |
        // - minC_FRate is used to limit the lower bound of C_FRate (configured in admin, range 0-1, defaulting to 0.0001, and collecting a minimum funding rate of one-thousandth per day).
        //   - When C_FRate < minC_FRate, C_FRate takes minC_FRate.
        _CFRate = Calc.abs(Long_CumFRate, Short_CumFRate).toUint256();
        _CFRate = Math.max(_CFRate, minCFRate);
    }

    /**
     * Used to calculate C_FRate_Long and C_FRate_Short
     * @param Long_CumFRate Cumulative funding rate for long positions with 8 decimal precision
     * @param Short_CumFRate Cumulative funding rate for short positions with 8 decimal precision
     * @param C_FRate C_FRate with 8 decimal precision
     * @param fundingFeeLossOffLimit Funding fee loss formula offset percentage (configured in admin) with 8 decimal precision, in the range [0, 10^8]
     * @param fundingFeeLoss Total funding fee loss for a single market with 18 decimal precision
     * @param Size_Long Size_Long with 18 decimal precision
     * @param Size_Short Size_Short with 18 decimal precision
     * @return C_FRate_Long C_FRate_Long with 8 decimal precision
     * @return C_FRate_Short C_FRate_Short with 8 decimal precision
     * @return deductFundFeeAmount Deducted funding fee amount
     */
    function calNextCFRate(
        int256 Long_CumFRate,
        int256 Short_CumFRate,
        uint256 C_FRate,
        uint256 fundingFeeLossOffLimit,
        uint256 fundingFeeLoss,
        uint256 Size_Long,
        uint256 Size_Short
    )
        internal
        pure
        returns (
            int256 C_FRate_Long,
            int256 C_FRate_Short,
            uint256 deductFundFeeAmount
        )
    {
        // - When the fee collection period has a positive funding fee position of 0, the positive funding fee >0, and the collected funding fee is 0, the negative funding fee rate is 0;
        // - When the fee collection period has a negative funding fee position of 0, the positive funding fee >0, and the negative funding fee rate is 0;
        bool isFomular = Size_Long > 0 && Size_Short > 0;
        if (Long_CumFRate >= Short_CumFRate) {
            deductFundFeeAmount = _getFundingFeeLoss(
                Size_Long,
                C_FRate,
                fundingFeeLossOffLimit,
                fundingFeeLoss
            );
            C_FRate_Long = C_FRate.toInt256();
            if (isFomular)
                C_FRate_Short =
                    -((Size_Long.toInt256() * C_FRate_Long) -
                        deductFundFeeAmount.toInt256() *
                        ONE_WITH_8_DECIMALS.toInt256()) /
                    Size_Short.toInt256();
        } else {
            deductFundFeeAmount = _getFundingFeeLoss(
                Size_Short,
                C_FRate,
                fundingFeeLossOffLimit,
                fundingFeeLoss
            );
            C_FRate_Short = C_FRate.toInt256();
            if (isFomular)
                // feeLoss calculated is always < Size_Short.toInt256() * C_FRate_Short
                C_FRate_Long =
                    -((Size_Short.toInt256() * C_FRate_Short) -
                        deductFundFeeAmount.toInt256() *
                        ONE_WITH_8_DECIMALS.toInt256()) /
                    Size_Long.toInt256();
        }
    }

    /**
     * Calculate funding fee loss value
     * @param size Position size for a particular direction, with 18 decimal precision
     * @param _CFRate CFRate with 8 decimal precision
     * @param fundingFeeLossOffLimit Funding fee loss formula offset percentage (configured in admin) with 8 decimal precision
     * @param fundingFeeLoss Total funding fee loss for a single market with 18 decimal precision
     */
    function _getFundingFeeLoss(
        uint256 size,
        uint256 _CFRate,
        uint256 fundingFeeLossOffLimit,
        uint256 fundingFeeLoss
    ) internal pure returns (uint256) {
        // Funding fee loss <= Size_Long * C_FRate_Long * 10%
        return
            Math.min(
                (size * _CFRate * fundingFeeLossOffLimit) /
                    (ONE_WITH_8_DECIMALS ** 2),
                fundingFeeLoss
            );
    }

    // Calculate the nearest hour
    function calcRoundedTime(
        uint256 currentTimeStamp,
        uint256 _fundingInterval
    ) internal pure returns (uint256) {
        return (currentTimeStamp / _fundingInterval) * _fundingInterval;
    }

    function isFundingTimeReached(
        uint256 _roundedTime,
        uint256 _fundingIntervalSeconds,
        uint256 _blockTimeStamp
    ) internal pure returns (bool) {
        return (_roundedTime + _fundingIntervalSeconds) <= _blockTimeStamp;
    }

    /**
     * Update "Temporary Cumulative Funding Rate" for a market
     * @param market Market address
     * @param cumLongRateDelta Delta value to add/subtract from "Temporary Cumulative Funding Rate" for long positions
     * @param cumShortRateDelta Delta value to add/subtract from "Temporary Cumulative Funding Rate" for short positions
     * @param roundedTime Current time
     * @param calFundingRates State variable: "Temporary Cumulative Funding Rate"
     * @param lastCalTimes State variable: Last updated time for "Temporary Cumulative Funding Rate"
     */
    function _updateGlobalCalRate(
        address market,
        int256 cumLongRateDelta,
        int256 cumShortRateDelta,
        uint256 roundedTime,
        mapping(address => mapping(bool => int256)) storage calFundingRates,
        mapping(address => uint256) storage lastCalTimes
    ) internal {
        // Accumulate the funding rate calculation
        calFundingRates[market][true] += cumLongRateDelta;
        calFundingRates[market][false] += cumShortRateDelta;

        // Record the time of this update
        lastCalTimes[market] = roundedTime;

        emit UpdateCalFundRate(market, cumLongRateDelta, cumShortRateDelta);
        emit UpdateLastCalTime(market, roundedTime);
    }

    /**
     * Reset temporary cumulative funding rate calculation values to zero
     * @param market Market address
     * @param timestamp Current time
     * @param calFundingRates State variable: "Temporary Cumulative Funding Rate"
     * @param lastCalTimes State variable: Last updated time for "Temporary Cumulative Funding Rate"
     */
    function resetCalFundingRate(
        address market,
        uint256 timestamp,
        mapping(address => mapping(bool => int256)) storage calFundingRates,
        mapping(address => uint256) storage lastCalTimes
    ) internal {
        calFundingRates[market][true] = 0;
        calFundingRates[market][false] = 0;
        lastCalTimes[market] = timestamp;
        emit UpdateCalFundRate(market, 0, 0);
        emit UpdateLastCalTime(market, timestamp);
    }

    /**
     * Common function used to get the funding interval for "Cumulative Funding Rate" or "Temporary Cumulative Funding Rate"
     */
    function getFundingInterval(
        address market,
        mapping(address => uint256) storage fundingIntervals
    ) internal view returns (uint256 _interval) {
        _interval = fundingIntervals[market];
        if (_interval == 0) return MIN_FUNDING_INTERVAL_3600;
    }

    /**
     * @dev Calculates the number of funding intervals that have passed since the last funding time.
     * @param _intervalSeconds The funding interval.
     * @return The number of intervals.
     */
    function _calculateIntervals(
        uint256 _end,
        uint256 _start,
        uint256 _intervalSeconds
    ) internal pure returns (uint256) {
        require(_intervalSeconds > 0);
        if (_start > _end) return 0;
        return (_end - _start) / _intervalSeconds;
    }

    function _calcPart1Intervals(
        uint256 _calcIntervalSeconds, // 3600
        uint256 _lastCalcTime, // 6
        uint256 _blockTimeStamp,
        uint256 _collectIntervalSeconds // 8 hours
    ) internal pure returns (uint256) {
        return
            _calculateIntervals(
                // Interval multiples of eight hours
                calcRoundedTime(_blockTimeStamp, _collectIntervalSeconds), // Current whole point in time
                // Last time
                _lastCalcTime, // Last time
                // One-hour interval
                _calcIntervalSeconds // Interval
            );
    }

    function _calcPart2Intervals(
        uint256 _calcIntervalSeconds, // 3600
        uint256 _lastCalcTime, // 6
        uint256 _blockTimeStamp
    ) internal pure returns (uint256) {
        return
            _calculateIntervals(
                // Interval multiples of one hour
                calcRoundedTime(_blockTimeStamp, _calcIntervalSeconds),
                // Last time
                _lastCalcTime,
                // One-hour interval
                _calcIntervalSeconds
            );
    }

    function addNegativeFeeLoss(
        address market,
        uint256 amount,
        mapping(address => uint256) storage fundFeeLoss
    ) internal {
        uint256 _before = fundFeeLoss[market];
        fundFeeLoss[market] += amount;
        emit AddNegativeFeeLoss(market, amount, _before, fundFeeLoss[market]);
    }

    function addPositiveFeeLoss(
        address market,
        uint256 deductAmount,
        mapping(address => uint256) storage fundFeeLoss
    ) internal {
        uint256 _before = fundFeeLoss[market];

        // When the total loss cannot be completely deducted in one go, the funding fee continues to deduct until the total loss is deducted.
        fundFeeLoss[market] = (fundFeeLoss[market] > deductAmount)
            ? (fundFeeLoss[market] - deductAmount)
            : 0;

        emit AddPositiveFeeLoss(
            market,
            deductAmount,
            _before,
            fundFeeLoss[market]
        );
    }

    /**
     * This function is used to calculate and update the temporary cumulative funding rate for a market (for the next CFRate calculation)
     * @param market Market address
     * @param longRate Long position rate with 8 decimal precision
     * @param shortRate Short position rate with 8 decimal precision
     * @param currentTS Current timestamp
     * @param calcPart
     * @param longCumulativeRatesDelta
     * @param shortCumulativeRatesDelta
     * @param roundedTime
     * @param calIntervals Calculative intervals
     * @param collectIntervals Collective intervals
     */
    struct CalcAndUpdateFundingRatesCache {
        address market;
        uint256 longRate;
        uint256 shortRate;
        uint256 currentTS;
        uint256 calcPart; // 1 or 2
        uint256 longCumulativeRatesDelta;
        uint256 shortCumulativeRatesDelta;
        uint256 roundedTime;
        uint256 calIntervals;
        uint256 collectIntervals;
    }

    function _calcAndUpdateFundingRates(
        CalcAndUpdateFundingRatesCache memory _cache,
        mapping(address => mapping(bool => int256)) storage calFundingRates,
        mapping(address => uint256) storage lastCalTimes
    ) internal {
        uint256 intervals;
        if (_cache.calcPart == 1)
            intervals = _calcPart1Intervals(
                _cache.calIntervals,
                lastCalTimes[_cache.market],
                _cache.currentTS,
                _cache.collectIntervals
            );
        else if (_cache.calcPart == 2)
            intervals = _calcPart2Intervals(
                _cache.calIntervals,
                lastCalTimes[_cache.market],
                _cache.currentTS
            );
        else revert("!calcPart");
        (
            _cache.longCumulativeRatesDelta,
            _cache.shortCumulativeRatesDelta,
            _cache.roundedTime
        ) = _getCumulativeFundingRateDelta(
            _cache.longRate,
            _cache.shortRate,
            _cache.calIntervals,
            lastCalTimes[_cache.market],
            _cache.currentTS,
            intervals
        );
        _updateGlobalCalRate(
            _cache.market,
            _cache.longCumulativeRatesDelta.toInt256(),
            _cache.shortCumulativeRatesDelta.toInt256(),
            _cache.roundedTime,
            calFundingRates,
            lastCalTimes
        );
    }

    struct UpdateCalFundingRateCache {
        address market;
        uint256 longSize; // 18 decimals
        uint256 shortSize; // 18 decimals
        uint256 calcPart; //1 or 2
        uint256 calcInterval;
        uint256 collectInterval;
        uint256 currentTimeStamp;
        uint256 calculatedMaxFRate; // 8 decimals
        uint256 calculatedFRate; // 8 decimals
    }

    function updateCalFundingRate(
        UpdateCalFundingRateCache memory c,
        mapping(address => mapping(bool => int256)) storage calFundingRates,
        mapping(address => uint256) storage lastCalTimes,
        uint256[] storage configs
    ) internal {
        uint256 _roundedTime = lastCalTimes[c.market];
        if (_roundedTime == 0) {
            _updateGlobalCalRate(
                c.market,
                0,
                0,
                calcRoundedTime(c.currentTimeStamp, c.calcInterval),
                calFundingRates,
                lastCalTimes
            );
            return;
        }

        if (
            !isFundingTimeReached(
                _roundedTime,
                c.calcInterval,
                c.currentTimeStamp
            )
        ) return;

        (uint256 _longRate, uint256 _shortRate) = capFundingRateByLimits(
            c.longSize,
            c.shortSize,
            configs[uint256(CfgIdx.MaxFRate)],
            configs[uint256(CfgIdx.MinFRate)],
            c.calculatedMaxFRate,
            c.calculatedFRate,
            configs[uint256(CfgIdx.MinorityFRate)]
        );

        _calcAndUpdateFundingRates(
            CalcAndUpdateFundingRatesCache(
                c.market,
                _longRate,
                _shortRate,
                c.currentTimeStamp,
                c.calcPart,
                0,
                0,
                0,
                c.calcInterval,
                c.collectInterval
            ),
            calFundingRates,
            lastCalTimes
        );
    }
}
