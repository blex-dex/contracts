module.exports = {
  skipFiles: [
    "ac",
    "fee",
    "am",
    "mocker",
    "order",
    "oracle",
    "position",
    "referral",
    "test",
    "utils",
    "vault",
    "market/MarketConfigStruct.sol",
    "market/MarketFactory.sol",
    "market/MarketLogic.sol",
    "market/MarketReader.sol",
    "market/GlobalValid.sol",
    "market/MarketValid.sol",
    "market/MarketDataTypes.sol",
    "market/MarketLib.sol",
  ],
  configureYulOptimizer: true,
};
