// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;
pragma experimental ABIEncoderV2;

import {IOrderBook} from "../order/interface/IOrderBook.sol";
import {IPrice} from "../oracle/interfaces/IPrice.sol";
import {IFeeRouter} from "../fee/interfaces/IFeeRouter.sol";
import {IPositionBook} from "../position/interfaces/IPositionBook.sol";
import {MarketStorage} from "./MarketStorage.sol";
import {IMarketValid} from "./interfaces/IMarketValid.sol";
import {MarketLib} from "./MarketLib.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IMarketRouter} from "./interfaces/IMarketRouter.sol";
import "./../position/PositionStruct.sol";
import {Order} from "../order/OrderStruct.sol";
import {MarketDataTypes} from "./MarketDataTypes.sol";
import {TransferHelper} from "../utils/TransferHelper.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../ac/Ac.sol";

contract Market is MarketStorage, ReentrancyGuard, Ac {
    using MarketLib for uint16;
    using Order for Order.Props;

    constructor(address _f) Ac(_f) {}

    fallback() external payable onlyController {
        _callAddress(orderMgr, msg.data, "unknown", true);
    }

    receive() external payable {
        revert("unacceptable");
    }

    function increasePositionWithOrders(
        MarketDataTypes.UpdatePositionInputs memory /* _inputs */
    ) external onlyController {
        _callAddress(
            positionAddMgr,
            msg.data,
            "increasePositionWithOrders",
            true
        );
    }

    function decreasePosition(
        MarketDataTypes.UpdatePositionInputs memory /* _vars */
    ) external onlyController {
        _callAddress(positionSubMgr, msg.data, "decreasePosition", true);
    }

    function liquidatePositions(
        address[] memory /* accounts */,
        bool /* _isLong */
    ) external onlyPositionKeeper {
        _callAddress(positionSubMgr, msg.data, "liquidatePositions", true);
    }

    bytes4 private constant SELECTOR_EXE_ORDER_KEY =
        bytes4(
            keccak256(
                bytes(
                    "execOrderKey((uint8,uint32,uint8,address,uint48,uint128,uint128,uint128,uint128,uint64,uint64,uint128,bytes32),(address,bool,uint256,bool,address,uint256,uint256,uint256,bool,uint8,uint64,bytes32,uint256,uint8,uint256[]))"
                )
            )
        );

    /**
     * @dev Called by `AutoOrder`.Executes the order key operation using the provided order properties and market data inputs.
     * @param exeOrder The order properties to be executed.
     * @param _params The market data inputs required for the execution.
     */
    function execOrderKey(
        Order.Props memory exeOrder,
        MarketDataTypes.UpdatePositionInputs memory _params
    ) external onlyPositionKeeper {
        (string memory errorMessage, bool suc) = _callAddress(
            _params.isOpen ? positionAddMgr : positionSubMgr,
            abi.encodeWithSelector(SELECTOR_EXE_ORDER_KEY, exeOrder, _params),
            "execOrderKey",
            false
        );

        if (!suc) {
            bytes32[] memory keys = new bytes32[](1);
            keys[0] = exeOrder.getKey();

            bool[] memory longs = new bool[](1);
            longs[0] = _params._isLong;

            bool[] memory iis = new bool[](1);
            iis[0] = _params.isOpen;

            string[] memory reasons = new string[](1);
            reasons[0] = errorMessage;

            _callAddress(
                orderMgr,
                abi.encodeWithSignature(
                    "sysCancelOrder(bytes32[],bool[],bool[],string[])",
                    keys,
                    longs,
                    iis,
                    reasons
                ),
                "sysCancelOrder",
                true
            );
        }
    }

    function updateCumulativeFundingRate() external {
        MarketLib._updateCumulativeFundingRate(positionBook, feeRouter);
    }

    /**
     * @dev Called by `MarketRouter`.This function calculates the Profit and Loss (PNL) for a user in a particular market.
     * @return pnl The PNL for the user in the market.
     * The function retrieves the current price of the `indexToken` using the `IPrice` contract and calculates the PNL for the market using the `getMarketPNL()` function from the `IPositionBook` contract.
     * The PNL is then converted to the user's `collateralToken` denomination using the `parseVaultAssetSigned()` function from the `TransferHelper` library.
     * This function is read-only and does not modify the state of the contract.
     */
    function getPNL() external view returns (int256 pnl) {
        uint256 longPrice = IPrice(priceFeed).getPrice(indexToken, false);
        uint256 shortPrice = IPrice(priceFeed).getPrice(indexToken, true);
        pnl = TransferHelper.parseVaultAssetSigned(
            IPositionBook(positionBook).getMarketPNL(longPrice, shortPrice),
            collateralTokenDigits
        );
    }

    //==============================================
    //==============================================

    function initialize(
        address[] memory addrs,
        string memory _name
    ) external initializer {
        name = _name;

        positionBook = IPositionBook(addrs[0]);
        orderBookLong = IOrderBook(addrs[1]);
        orderBookShort = IOrderBook(addrs[2]);
        marketValid = addrs[3];
        priceFeed = addrs[4];
        positionSubMgr = addrs[5];
        positionAddMgr = addrs[6];
        indexToken = addrs[7];
        feeRouter = IFeeRouter(addrs[8]);
        marketRouter = addrs[9];
        vaultRouter = addrs[10];
        collateralToken = addrs[11];
        globalValid = addrs[12];
        orderMgr = addrs[13];

        orderStores[true][true] = orderBookLong.openStore();
        orderStores[true][false] = orderBookLong.closeStore();
        orderStores[false][true] = orderBookShort.openStore();
        orderStores[false][false] = orderBookShort.closeStore();
        collateralTokenDigits = IERC20Metadata(collateralToken).decimals();

        positionStoreLong = positionBook.longStore();
        positionStoreShort = positionBook.shortStore();
        plugins.push(marketRouter);
    }

    function addPlugin(address _addr) external onlyInitOr(MANAGER_ROLE) {
        address[] memory _plugins = plugins;
        for (uint i = 0; i < _plugins.length; i++)
            if (_plugins[i] == _addr) revert("Market:same address");

        plugins.push(_addr);
    }

    function removePlugin(address _addr) external onlyAdmin {
        for (uint i = 0; i < plugins.length; i++) {
            if (plugins[i] == _addr) {
                // Replace the element to remove with the last element
                plugins[i] = _plugins[_plugins.length - 1];
                // Remove the last element
                plugins.pop();
                // Exit the loop
                break;
            }
        }
    }

    function setOrderBooks(
        address obl,
        address obs
    ) external onlyRole(MARKET_MGR_ROLE) {
        require(obl != address(0), "obl zero");
        require(obs != address(0), "obs zero");
        _setOrderBook(true, obl);
        _setOrderBook(false, obs);
    }

    function _setOrderBook(bool isLong, address ob) private {
        IOrderBook nob = IOrderBook(ob);
        if (isLong) {
            nob.initialize(
                isLong,
                address(orderBookLong.openStore()),
                address(orderBookLong.closeStore())
            );
            orderBookLong = nob;
        } else {
            nob.initialize(
                isLong,
                address(orderBookShort.openStore()),
                address(orderBookShort.closeStore())
            );
            orderBookShort = nob;
        }
    }

    function setPositionBook(address pb) external onlyRole(MARKET_MGR_ROLE) {
        require(pb != address(0), "zero");
        require(
            positionBook.longStore() == IPositionBook(pb).longStore(),
            "invalid store"
        );
        require(
            positionBook.shortStore() == IPositionBook(pb).shortStore(),
            "invalid store"
        );
        IMarketRouter(marketRouter).updatePositionBook(pb);
        positionBook = IPositionBook(pb);
    }

    function setMarketValid(address _newMv) external onlyRole(MARKET_MGR_ROLE) {
        require(_newMv != address(0), "zero");

        if (marketValid != address(0)) {
            IMarketValid(_newMv).setConfData(
                IMarketValid(marketValid).conf().data
            );
        }
        marketValid = _newMv;
    }

    function setPositionMgr(
        address _m,
        bool add
    ) external onlyRole(MARKET_MGR_ROLE) {
        require(_m != address(0), "zero");

        if (add) positionAddMgr = _m;
        else positionSubMgr = _m;
    }

    function setOrderMgr(address _m) external onlyRole(MARKET_MGR_ROLE) {
        require(_m != address(0), "zero");
        orderMgr = _m;
    }

    function _valid() private view returns (IMarketValid) {
        return IMarketValid(marketValid);
    }

    function getPrice(bool _isMax) private view returns (uint256) {
        IPrice _p = IPrice(priceFeed);
        return _p.getPrice(indexToken, _isMax);
    }

    function getPositions(
        address account
    ) external view returns (Position.Props[] memory _poss) {
        _poss = positionBook.getPositions(account);
        for (uint i = 0; i < _poss.length; i++) {
            _poss[i].market = address(this);
        }
    }

    function USDDecimals() external pure returns (uint8) {
        return TransferHelper.getUSDDecimals();
    }

    function _callAddress(
        address _addr,
        bytes memory msgdata,
        string memory defaultRevertMsg,
        bool raise
    ) private returns (string memory _errorMessage, bool success) {
        bytes memory returnData;
        (success, returnData) = _addr.delegatecall(msgdata);
        if (!success) {
            if (returnData.length < 68) {
                _errorMessage = defaultRevertMsg;
            } else {
                assembly {
                    returnData := add(returnData, 0x04)
                }
                _errorMessage = abi.decode(returnData, (string));
                if (bytes(_errorMessage).length == 0)
                    _errorMessage = defaultRevertMsg;
            }
            if (raise) revert(_errorMessage);
        }
    }
}
