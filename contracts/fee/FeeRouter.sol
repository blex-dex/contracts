// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "../ac/Ac.sol";

import {IFundFee} from "./interfaces/IFundFee.sol";
import {IFeeVault} from "./interfaces/IFeeVault.sol";
import {MarketDataTypes} from "../market/MarketDataTypes.sol";
import {Position} from "../position/PositionStruct.sol";
import {TransferHelper} from "./../utils/TransferHelper.sol";
import "../market/interfaces/IMarketFactory.sol";

import "./interfaces/IFeeRouter.sol";
import {Precision} from "../utils/TransferHelper.sol";

contract FeeRouter is Ac, IFeeRouter {
    using SafeERC20 for IERC20;
    using SafeCast for int256;
    using SafeCast for uint256;

    address public feeVault;
    address public fundFee;
    address public factory;

    uint256 public constant FEE_RATE_PRECISION = Precision.FEE_RATE_PRECISION;
    uint256 public constant DEFAULT_MIN_RATE=100000;

    // market's feeRate and fee
    mapping(address => mapping(uint8 => uint256)) public feeAndRates;

    event UpdateFee(
        address indexed account,
        address indexed market,
        int256[] fees,
        uint256 amount
    );
    event UpdateFeeAndRates(
        address indexed market,
        uint8 kind,
        uint256 oldFeeOrRate,
        uint256 feeOrRate
    );

    constructor(address _factory) Ac(_factory) {
        require(_factory != address(0), "invalid address");
        factory = _factory;
        _grantRole(MANAGER_ROLE, msg.sender);
    }

    modifier onlyMarket() {
        require(_isMarket(msg.sender), "invalid market");
        _;
    }

    modifier onlyFeeController() {
        require(
            _isMarket(msg.sender) || hasRole(ROLE_CONTROLLER, msg.sender),
            "feeRouter: access denied"
        );
        _;
    }

    function initialize(
        address vault,
        address fundingFee
    ) external initializer {
        require(vault != address(0), "invalid fee vault");
        require(fundingFee != address(0), "invalid fundFee");

        feeVault = vault;
        fundFee = fundingFee;
    }

    event SetFeeVault(address vault);

    function setFeeVault(address vault) external onlyManager {
        require(vault != address(0), "invalid fee vault");
        feeVault = vault;

        emit SetFeeVault(vault);
    }

    event SetFundFee(address fundingFee);

    function setFundFee(address fundingFee) external onlyManager {
        require(fundFee != address(0), "invalid fundFee");
        fundFee = fundingFee;

        emit SetFundFee(fundingFee);
    }

    function setFeeAndRates(
        address market,
        uint256[] memory rates
    ) external onlyInitOr(MARKET_MGR_ROLE) {
        require(
            rates.length > 0 && rates.length <= uint(type(FeeType).max) + 1,
            "invalid params"
        );

        for (uint8 i = 0; i < rates.length; i++) {
            uint256 old = feeAndRates[market][i];
            uint256 rate = rates[i];
            feeAndRates[market][i] = rate;
            emit UpdateFeeAndRates(market, i, old, rate);
        }
    }

    function withdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyRole(WITHDRAW_ROLE) {
        IFeeVault(feeVault).withdraw(token, to, amount);
    }

    /**
     * @dev Updates the cumulative funding rate for a specific market.
     * Only the controller can call this function.
     * @param market The address of the market.
     * @param longSize The size of the long position.
     * @param shortSize The size of the short position.
     */
    function updateCumulativeFundingRate(
        address market,
        uint256 longSize,
        uint256 shortSize
    ) external onlyMarket {
        IFundFee(fundFee).updateCumulativeFundingRate(
            market,
            longSize,
            shortSize
        );
    }

    /**
     * @dev Collects fees from the sender and increases the fees in the fee vault for the specified account.
     * Only the controller can call this function.
     * @param account The account to increase fees for.
     * @param token The address of the token to collect fees in.
     * @param fees The array of fee amounts.
     */
    function collectFees(
        address account,
        address token,
        int256[] memory fees
    ) external onlyFeeController {
        uint256 _amount = IERC20(token).allowance(msg.sender, address(this));
        if (_amount == 0) {
            return;
        }

        IERC20(token).safeTransferFrom(msg.sender, feeVault, _amount);

        emit UpdateFee(account, msg.sender, fees, _amount);
    }

    /**
     * @dev Retrieves the execution fee for a specific market.
     * @param market The address of the market.
     * @return The execution fee for the market.
     */
    function getExecFee(address market) external view returns (uint256) {
        return feeAndRates[market][uint8(FeeType.ExecFee)];
    }

    /**
     * @dev Retrieves the funding rate for a specific market and position.
     * @param market The address of the market.
     * @param isLong A flag indicating whether the position is long (true) or short (false).
     * @return The funding rate for the market and position.
     */
    function getFundingRate(
        address market,
        bool isLong
    ) external view returns (int256) {
        return IFundFee(fundFee).getFundingRate(market, isLong);
    }

    /**
     * @dev Retrieves the cumulative funding rates for a specific market and position.
     * @param market The address of the market.
     * @param isLong A flag indicating whether the position is long (true) or short (false).
     * @return The cumulative funding rates for the market and position.
     */
    function cumulativeFundingRates(
        address market,
        bool isLong
    ) external view returns (int256) {
        return IFeeVault(feeVault).cumulativeFundingRates(market, isLong);
    }

    /**
     * @dev Retrieves the total fees for an order by calculating the trade fee and adding it to the execution fee.
     * @param params The parameters of the order.
     * @return fees The total fees for the order.
     */
    function getOrderFees(
        MarketDataTypes.UpdateOrderInputs memory params
    ) external view returns (int256 fees) {
        uint8 _kind;

        if (params.isOpen) {
            _kind = uint8(FeeType.OpenFee);
        } else {
            _kind = uint8(FeeType.CloseFee);
        }

        uint256 _tradeFee = _getFee(params._market, params._order.size, _kind);
        uint256 _execFee = feeAndRates[params._market][uint8(FeeType.ExecFee)];
        return (_tradeFee + _execFee).toInt256();
    }

    /**
     * @dev Retrieves the fees associated with updating a position.
     * @param params The parameters of the position update.
     * @param position The properties of the position.
     * @return fees An array of fees for each fee type.
     */
    function getFees(
        MarketDataTypes.UpdatePositionInputs memory params,
        Position.Props memory position
    ) external view returns (int256[] memory fees) {
        fees = new int256[](uint8(FeeType.Counter));
        address _market = params._market;

        int256 _fundFee = _getFundingFee(
            _market,
            params._isLong,
            position.size,
            position.entryFundingRate
        );
        fees[uint8(FeeType.FundFee)] = _fundFee;

        if (params._sizeDelta == 0 && params.collateralDelta != 0) {
            return fees;
        }

        // open position
        if (params.isOpen) {
            fees[uint8(FeeType.OpenFee)] = (
                _getFee(_market, params._sizeDelta, uint8(FeeType.OpenFee))
            ).toInt256();
        } else {
            // close position
            fees[uint8(FeeType.CloseFee)] = (
                _getFee(_market, params._sizeDelta, uint8(FeeType.CloseFee))
            ).toInt256();

            // liquidate position
            if (params.liqState == 1) {
                uint256 _fee = feeAndRates[_market][uint8(FeeType.LiqFee)];
                fees[uint8(FeeType.LiqFee)] = _fee.toInt256();
            }
        }
        if (params.execNum > 0) {
            // exec fee
            uint256 _fee = feeAndRates[_market][uint8(FeeType.ExecFee)];
            _fee = _fee * params.execNum;

            fees[uint8(FeeType.ExecFee)] = _fee.toInt256();
        }
        return fees;
    }

    /**
     * @dev Calculates the funding fee for a given position update.
     * @param market The address of the market.
     * @param isLong A flag indicating whether the position is long (true) or short (false).
     * @param sizeDelta The change in position size.
     * @param entryFundingRate The funding rate at the entry of the position.
     * @return The funding fee for the position update.
     */
    function _getFundingFee(
        address market,
        bool isLong,
        uint256 sizeDelta,
        int256 entryFundingRate
    ) private view returns (int256) {
        if (sizeDelta == 0) {
            return 0;
        }

        return
            IFundFee(fundFee).getFundingFee(
            market,
            sizeDelta,
            entryFundingRate,
            isLong
        );
    }

    /**
     * @dev Calculates the fee for a given size delta and fee kind.
     * @param market The address of the market.
     * @param sizeDelta The change in position size.
     * @param kind The fee kind.
     * @return The fee amount.
     */

    function _getFee(
        address market,
        uint256 sizeDelta,
        uint8 kind
    ) private view returns (uint256) {
        if (sizeDelta == 0) {
            return 0;
        }

        require(kind <= uint(type(FeeType).max), "invalid FeeType");
        uint256 _point = feeAndRates[market][kind];
        if (_point == 0) {
            _point = DEFAULT_MIN_RATE;
        }

        uint256 _size = (sizeDelta * (FEE_RATE_PRECISION - _point)) /
                    FEE_RATE_PRECISION;
        return sizeDelta - _size;
    }

    function _isMarket(address _market) private view returns (bool) {
        IMarketFactory.Props memory _marketProps = IMarketFactory(factory)
            .getMarket(_market);
        return (_marketProps.inputs._allowOpen ||
            _marketProps.inputs._allowClose);
    }
}
