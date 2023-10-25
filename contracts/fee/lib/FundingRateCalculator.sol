// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "../../utils/Calc.sol";

library FundingRateCalculator {
    using SafeCast for uint256;
    using SafeCast for int256;

    uint256 public constant MIN_FUNDING_INTERVAL_3600 = 1 hours; // 8hours
    uint256 public constant ONE_WITH_8_DECIMALS = 10 ** 8; //0.0001666666*100000000
    uint256 public constant BASIS_INTERVAL_HOUR_24 = 24;
    uint256 public constant DEFAULT_RATE_DIVISOR_100 = 100;

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

    event UpdateCalFundRates(
        address indexed market,
        int256 longRate,
        int256 shortRate
    );

    event UpdateLastCalRate(
        address indexed market,
        uint256 longRate,
        uint256 shortRate
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

    /**
     *
     * @param openInterest18Decimals 18zeros
     * @param aumWith18Decimals 18zeros
     * @param maxFRatePerDayWith8Decimals 8zeros
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

    /**
     * capFundingRateByLimits Calculate the unit funding rate (with maximum and minimum limits)
     * @param long long size
     * @param short short size
     * @param maxFRate max FRate
     * @param minFRate min FRate
     * @param calculatedMaxFRate8Decimals calculated max FRate
     * @param fRate intervals
     * @param minority minority rate
     */
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
     * @param _intervals intervals
     * @return _longCumulativeRates long Cumulative Rates with 8 decimals
     * @return _shortCumulativeRates short Cumulative Rates with 8 decimals
     * @return _roundedTime _roundedTime
     */
    function _getCumulativeFundingRateDelta(
        uint256 _longRate,
        uint256 _shortRate,
        uint256 _calcIntervalSeconds, //3600
        uint256 _lastCalcTime,
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

    /**
     * calUserFundingFee Calculate the user's funding fee
     * @param size  position size
     * @param entryFundingRate the rate of position start
     * @param cumRates current rate
     */
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

    /**
     * calFeeRate Calculate the funding fee formula: maxFRate = Total Open interest / AUM * FRate per day /（24/interval）
     * @param _longSizeWith18Decimals  _longSizeWith18Decimals
     * @param _shortSizeWith18Decimals _shortSizeWith18Decimals
     * @param _intervalSeconds _intervalSeconds
     * @param fRateFactorWith8Decimals fRateFactorWith8Decimals
     */
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
            deductFundFeeAmount = _getLossOffset(
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
            deductFundFeeAmount = _getLossOffset(
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
    // function _getFundingFeeLoss(
    function _getLossOffset(
        uint256 size,
        uint256 _CFRate,
        uint256 fundingFeeLossOffLimit,
        uint256 totalLoss
    ) internal pure returns (uint256) {
        // Funding fee loss <= Size_Long * C_FRate_Long * 10%
        return
            Math.min(
                (size * _CFRate * fundingFeeLossOffLimit) /
                    (ONE_WITH_8_DECIMALS ** 2),
                totalLoss
            );
    }

    // Calculate the nearest hour
    function calcRoundedTime(
        uint256 currentTimeStamp,
        uint256 _fundingInterval
    ) internal pure returns (uint256) {
        return (currentTimeStamp / _fundingInterval) * _fundingInterval;
    }

    // isFundingTimeReached
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

        emit UpdateCalFundRates(market, cumLongRateDelta, cumShortRateDelta);
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
        emit UpdateCalFundRates(market, 0, 0);
        emit UpdateLastCalTime(market, timestamp);
    }

    /**
     * Common function used to get the funding interval for "Cumulative Funding Rate" or "Temporary Cumulative Funding Rate"
     * @param fundingIntervals The funding interval.
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

    /**
     * _calcPart1Intervals Number of intervals in the larger time frame. eg: 8 hours
     * @param _calcIntervalSeconds smaller time frame
     * @param _lastCalcTime last time calculated
     * @param _blockTimeStamp current time
     * @param _collectIntervalSeconds the larger time frame
     */
    function _calcPart1Intervals(
        uint256 _calcIntervalSeconds, //3600
        uint256 _lastCalcTime, //6
        uint256 _blockTimeStamp,
        uint256 _collectIntervalSeconds //8 hours
    ) internal pure returns (uint256 intervals, uint256 endRoundedTime) {
        // current time = 17
        // roundedCollectedTime = 16
        // lastcaltime = 6
        // calInterval = 1 hr
        // return 10

        uint256 lastRoundedTime = calcRoundedTime(
            _lastCalcTime,
            _collectIntervalSeconds
        );
        uint256 nowRoundedTime = calcRoundedTime(
            _blockTimeStamp,
            _collectIntervalSeconds
        );

        if (lastRoundedTime == nowRoundedTime) return (0, lastRoundedTime);

        intervals = _calculateIntervals(
            lastRoundedTime + _collectIntervalSeconds,
            _lastCalcTime,
            _calcIntervalSeconds
        );

        return (intervals, lastRoundedTime + _collectIntervalSeconds);
    }

    function _calcPart2Intervals(
        uint256 _calcIntervalSeconds, //3600
        uint256 _lastCalcTime, //6
        uint256 _blockTimeStamp,
        uint256 _collectIntervalSeconds //8 hours
    ) internal pure returns (uint256 collectIntervals, uint256 collectDivCalc) {
        collectDivCalc = _collectIntervalSeconds / _calcIntervalSeconds;

        uint256 nowRoundedTime = calcRoundedTime(
            _blockTimeStamp,
            _collectIntervalSeconds
        );
        if (_lastCalcTime >= nowRoundedTime)
            return (0, _collectIntervalSeconds);

        collectIntervals = _calculateIntervals(
            nowRoundedTime,
            _lastCalcTime,
            _collectIntervalSeconds
        );
        collectDivCalc = _collectIntervalSeconds;
    }

    function _calcPart3Intervals(
        uint256 _calcIntervalSeconds, //3600
        uint256 _lastCalcTime, //6
        uint256 _blockTimeStamp
    ) internal pure returns (uint256) {
        return
            _calculateIntervals(
                calcRoundedTime(_blockTimeStamp, _calcIntervalSeconds),
                _lastCalcTime,
                _calcIntervalSeconds
            );
    }

    /**
     * addNegativeFeeLoss Accumulated funding fee losses.
     * @param market Market address
     * @param amount funding fee losses
     * @param fundFeeLoss the storage of fundFeeLoss
     */
    function addNegativeFeeLoss(
        address market,
        uint256 amount,
        mapping(address => uint256) storage fundFeeLoss
    ) internal {
        uint256 _before = fundFeeLoss[market];
        fundFeeLoss[market] += amount;
        emit AddNegativeFeeLoss(market, amount, _before, fundFeeLoss[market]);
    }

    /**
     * addPositiveFeeLoss Deducting funding fee losses
     * @param market Market address
     * @param deductAmount Deducting amount
     * @param fundFeeLoss the storage of fundFeeLoss
     */
    function addPositiveFeeLoss(
        address market,
        uint256 deductAmount,
        mapping(address => uint256) storage fundFeeLoss
    ) internal {
        uint256 _before = fundFeeLoss[market];

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
     * @param calIntervals calculative intervals
     * @param collectIntervals collective intervals
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

    /**
     * _calcAndUpdateFundingRates about Long_CumFRate and Short_CumFRate
     * @param _cache infos
     * @param calFundingRates the storage of FundFee.calFundingRates
     * @param lastCalTimes the storage of FundFee.lastCalTimes
     */
    function _calcAndUpdateFundingRates(
        CalcAndUpdateFundingRatesCache memory _cache,
        mapping(address => mapping(bool => int256)) storage calFundingRates,
        mapping(address => uint256) storage lastCalTimes
    ) internal returns (uint256 intervals, uint256 collectIntervals) {
        collectIntervals = 1;
        if (_cache.calcPart == 1)
            (intervals, ) = _calcPart1Intervals(
                _cache.calIntervals,
                lastCalTimes[_cache.market],
                _cache.currentTS,
                _cache.collectIntervals
            );
        else if (_cache.calcPart == 2)
            intervals = _cache.collectIntervals / _cache.calIntervals;
        else if (_cache.calcPart == 3)
            intervals = _calcPart3Intervals(
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

    /**
     * updateCalFundingRate Update the FRate periodic fee rate
     * @param c infos
     * @param calFundingRates the storage of FundFee.calFundingRates
     * @param lastCalTimes the storage of FundFee.lastCalTimes
     * @param configs the storage of FundFee.configs
     */
    function updateCalFundingRate(
        UpdateCalFundingRateCache memory c,
        mapping(address => mapping(bool => int256)) storage calFundingRates,
        mapping(address => uint256) storage lastCalTimes,
        uint256[] storage configs,
        mapping(address => mapping(bool => uint256)) storage lastCalRate
    ) internal {
        // If FRate periodic fee rate is not initialized, initialize it and exit.
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
        // If it's not time for FRate periodic fee rate update, exit.
        if (
            !isFundingTimeReached(
                _roundedTime,
                c.calcInterval,
                c.currentTimeStamp
            )
        ) return;
        // Calculate the FRate for the current point
        (uint256 _longFRate, uint256 _shortFRate) = capFundingRateByLimits(
            c.longSize,
            c.shortSize,
            configs[uint256(CfgIdx.MaxFRate)],
            configs[uint256(CfgIdx.MinFRate)],
            c.calculatedMaxFRate,
            c.calculatedFRate,
            configs[uint256(CfgIdx.MinorityFRate)]
        );
        lastCalRate[c.market][true] = _longFRate;
        lastCalRate[c.market][false] = _shortFRate;

        emit UpdateLastCalRate(c.market, _longFRate, _shortFRate);

        _calcAndUpdateFundingRates(
            CalcAndUpdateFundingRatesCache(
                c.market,
                _longFRate,
                _shortFRate,
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

    struct GetNextFundingRateCache {
        int256 Long_CumFRate;
        int256 Short_CumFRate;
        uint256 longFRate;
        uint256 shortFRate;
        uint256 leftIntervals;
        // inputs
        uint256 calInterval;
        uint256 lastCalTimes;
        uint256 ts;
        uint256 collectInterval;
        uint256 minCFRate;
        uint256 fundingFeeLossOffLimit;
        uint256 fundingFeeLoss;
    }

    /**
     * @dev Retrieves the next funding rates for a market based on the sizes of long and short positions.
     * @param market The address of the market.
     * @param longSize The size of the long position on single market.
     * @param shortSize The size of the short position on single market.
     * @return _longCFRate The next funding rates for long and short positions.
     * @return _shortCFRate The next funding rates for long and short positions.
     */
    function getNextFundingRate(
        address market,
        uint256 longSize,
        uint256 shortSize,
        GetNextFundingRateCache memory c,
        mapping(address => mapping(bool => int256)) storage calFundingRates,
        mapping(address => mapping(bool => uint256)) storage lastCalRate
    ) internal view returns (int256 _longCFRate, int256 _shortCFRate) {
        bool _isCalcBegan = isCalcBegan(
            c.ts,
            c.collectInterval,
            c.lastCalTimes
        );
        if (_isCalcBegan) {
            c.Long_CumFRate = calFundingRates[market][true];
            c.Short_CumFRate = calFundingRates[market][false];
        }

        c.longFRate = lastCalRate[market][true];
        c.shortFRate = lastCalRate[market][false];

        c.leftIntervals = _calcLeftIntervals(
            c.calInterval,
            c.lastCalTimes,
            c.ts,
            c.collectInterval,
            _isCalcBegan
        );

        c.Long_CumFRate += (c.longFRate * c.leftIntervals).toInt256();
        c.Short_CumFRate += (c.shortFRate * c.leftIntervals).toInt256();

        uint256 CFRate = calCFRate(
            c.Long_CumFRate,
            c.Short_CumFRate,
            c.minCFRate
        );
        (_longCFRate, _shortCFRate, ) = calNextCFRate(
            c.Long_CumFRate,
            c.Short_CumFRate,
            CFRate,
            c.fundingFeeLossOffLimit,
            c.fundingFeeLoss,
            longSize,
            shortSize
        );
    }

    function _calcLeftIntervals(
        uint256 calInterval,
        uint256 lastCalTimes,
        uint256 ts,
        uint256 collectInterval,
        bool _isCalcBegan
    ) internal pure returns (uint256 leftIntervals) {
        uint256 part1;
        if (_isCalcBegan) {
            (part1, ) = _calcPart1Intervals(
                calInterval, // _cache.calIntervals
                lastCalTimes,
                ts,
                collectInterval
            );

            return
                collectInterval /
                calInterval -
                _calcPart3Intervals(
                    calInterval,
                    lastCalTimes + part1 * calInterval,
                    ts
                );
        } else return collectInterval / calInterval;
    }

    function isCalcBegan(
        uint256 ts,
        uint256 collectInterval,
        uint256 lastCalTimes
    ) internal pure returns (bool) {
        uint256 collectRoundedTime = calcRoundedTime(ts, collectInterval);
        if (
            (collectRoundedTime < lastCalTimes) ||
            (collectRoundedTime - lastCalTimes) < collectInterval
        ) return true;
        return false;
    }
}
