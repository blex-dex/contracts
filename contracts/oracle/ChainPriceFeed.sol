// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/IPriceFeed.sol";
import "../ac/Ac.sol";

contract ChainPriceFeed is Ac {
    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public sampleSpace = 3;

    mapping(address => address) public priceFeeds;
    mapping(address => uint256) public priceDecimals;
    address public USDT;

    constructor() Ac(msg.sender) {}

    function setSampleSpace(uint256 _times) external onlyManager {
        require(_times > 0, "PriceFeed: invalid _priceSampleSpace");
        sampleSpace = _times;
    }

    function setPriceFeed(
        address _token,
        address _feed,
        uint256 _decimal
    ) external onlyInitOr(MANAGER_ROLE) {
        priceFeeds[_token] = _feed;
        priceDecimals[_token] = _decimal;
    }

    function setUSDT(
        address _token,
        address _feed,
        uint256 _decimal
    ) external onlyInitOr(MANAGER_ROLE) {
        USDT = _token;
        priceFeeds[_token] = _feed;
        priceDecimals[_token] = _decimal;
    }

    function getLatestPrice(address _token) public view returns (uint256) {
        uint256 xxxUSD = _getLatestPrice(_token);
        uint256 _USDTUSD = _getLatestPrice(USDT);
        if (xxxUSD < (2 ** 256 - 1) / PRICE_PRECISION)
            return (xxxUSD * PRICE_PRECISION) / _USDTUSD;
        return (xxxUSD / PRICE_PRECISION) * _USDTUSD;
    }

    function _getLatestPrice(address _token) private view returns (uint256) {
        address _feed = priceFeeds[_token];
        require(_feed != address(0), "PriceFeed: invalid price feed");

        IPriceFeed _priceFeed = IPriceFeed(_feed);

        int256 _price = _priceFeed.latestAnswer();
        require(_price > 0, "PriceFeed: invalid price");

        return uint256(_price);
    }

    function getPrice(
        address _token,
        bool _maximise
    ) public view returns (uint256) {
        uint256 xxxUSD = _getPrice(_token, _maximise);
        uint256 _USDTUSD = _getPrice(USDT, _maximise);
        if (xxxUSD < (2 ** 256 - 1) / PRICE_PRECISION)
            return (xxxUSD * PRICE_PRECISION) / _USDTUSD;
        return (xxxUSD / PRICE_PRECISION) * _USDTUSD;
    }

    function _getPrice(
        address _token,
        bool _maximise
    ) private view returns (uint256) {
        address _feed = priceFeeds[_token];
        require(_feed != address(0), "PriceFeed: invalid price feed");

        IPriceFeed _priceFeed = IPriceFeed(_feed);

        uint256 _price = 0;
        uint80 _id = _priceFeed.latestRound();

        for (uint80 i = 0; i < sampleSpace; i++) {
            if (_id <= i) {
                break;
            }
            uint256 p;

            if (i == 0) {
                int256 _p = _priceFeed.latestAnswer();
                require(_p > 0, "PriceFeed: invalid price");
                p = uint256(_p);
            } else {
                (, int256 _p, , , ) = _priceFeed.getRoundData(_id - i);
                require(_p > 0, "PriceFeed: invalid price");
                p = uint256(_p);
            }

            if (_price == 0) {
                _price = p;
                continue;
            }

            if (_maximise && p > _price) {
                _price = p;
                continue;
            }

            if (!_maximise && p < _price) {
                _price = p;
            }
        }

        require(_price > 0, "PriceFeed: could not fetch price");

        uint256 _decimals = priceDecimals[_token];
        return (_price * PRICE_PRECISION) / (10 ** _decimals);
    }
}
