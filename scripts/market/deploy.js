const {
  deployGlobalValid,
  readGlobalValidContract,
  setMaxSizeLimit,
  setMaxNetSizeLimit,
  setMaxUserNetSizeLimit,
  setMaxMarketSizeLimit,
} = require("./globalValid.js");

const {
  deployMarketFactory,
  readMarketFactoryContract,
  createMarket: factoryCreateMarket,
} = require("./marketFactory.js");

const {
  deployMarketReader,
  readMarketReaderContract,
  initializeReader,
} = require("./marketReader.js");

const {
  deployMarketRouter,
  readMarketRouterContract,
  initializeRouter,
  addMarket,
  removeMarket,
} = require("./marketRouter.js");

const {
  deployMarketValid,
  readMarketValidContract,
  setMarketValidConf,
  setMarketValidConfData,
} = require("./marketValid.js");

const {
  deployMarketValidReader,
  readMarketValidReaderContract,
} = require("./marketValidReader.js");

const { deployOrderMgr, readOrderMgrContract } = require("./orderMgr.js");

const {
  deployPositionAddMgr,
  readPositionAddMgrContract,
} = require("./positionAddMgr.js");

const {
  deployPositionSubMgr,
  readPositionSubMgrContract,
} = require("./positionSubMgr.js");

const {
  deployMarket,
  readMarketContract,
  initialize,
  addPlugin,
  setOrderBooks,
  setPositionBook,
  setMarketValid,
  setPositionMgr,
  setOrderMgr,
} = require("./market.js");

const {
  deployPositionBook,
  readPositionBookContract,
  initPositionBook,
} = require("../position/positionBook.js");

const { deployOrderBook } = require("../order/deployAll.js");
const { ethers } = require("hardhat");
const { deployUSDC } = require("../mocker/USDC.js");
const { deployOracle } = require("../mock/oracle.js");
const { deployFee } = require("../fee/deployFeeAll.js");
const { deployVaultRouter } = require("../vault/vaultRouter.js");
const { grantRoleIfNotGranted } = require("../utils/helpers.js");

async function deployGlobalMarket(vaultRouterAddr, writeJson) {
  const globalValid = await deployGlobalValid(writeJson);
  const factory = await deployMarketFactory(writeJson);
  //const market =await deployMarket(factory.address, writeJson);
  const marketReader = await deployMarketReader(factory.address, writeJson);
  const marketRouter = await deployMarketRouter(factory.address, writeJson);
  const orderMgr = await deployOrderMgr(writeJson);
  const positionAddMgr = await deployPositionAddMgr(writeJson);
  const positionSubMgr = await deployPositionSubMgr(writeJson);

  await initializeReader(marketRouter.address, vaultRouterAddr);
  await initializeRouter(globalValid.address, vaultRouterAddr);

  return {
    globalValid: globalValid,
    factory: factory,
    marketReader: marketReader,
    marketRouter: marketRouter,
    orderMgr: orderMgr,
    positionAddMgr: positionAddMgr,
    positionSubMgr: positionSubMgr,
  };
}

/**
 * @description:
 * @param {string} name
 * @param {object{
 * 		factory: string
 * 		oracle: string,		// oracle address
 * 		indexToken: string, 	// indexToken address
 * 		feeRouter: string,	// feeRouter address
 * 		vaultRouter: string,	// vaultRouter address
 * 		collateralToken: string	// collateralToken address
 * 		positionSubMgr: string	// positionSubMgr address
 * 		positionAddMgr: string
 * 		marketRouter: string
 * 		globalValid: string
 * 		orderMgr: string
 * 	}} contracts
 * @param {object {
 * 	minSlippage: int,
 * 	maxSlippage: int,
 * 	minLeverage: int,
 * 	maxLeverage: int,
 * 	maxTradeAmount: int,
 * 	minPay: int,
 * 	minCollateral: int,
 * 	allowOpen: bool,
 * 	allowClose: bool,
 * 	tokenDigits: int
 * }} configs
 * @param {bool} writeJson
 */
async function createMarket(name, contracts, configs, writeJson) {
  const market = await deployMarket(contracts.factory, writeJson);
  const marketValid = await deployMarketValid(contracts.factory, writeJson);
  const positionBook = await deployPositionBook(contracts.factory, writeJson);
  const orderBookLongContracts = await deployOrderBook(
    contracts.factory,
    true,
    writeJson
  );
  const orderBookShortContracts = await deployOrderBook(
    contracts.factory,
    false,
    writeJson
  );

  const createInputs = {
    _name: name,
    _marketAddress: market.address, // Enter market address here
    addrs: [
      positionBook.address, // 0
      orderBookLongContracts.orderBook.address, // 1
      orderBookShortContracts.orderBook.address, // 2
      marketValid.address, // 3
      contracts.oracle, // 4
      contracts.positionSubMgr, // 5
      contracts.positionAddMgr, // 6
      contracts.indexToken, // 7
      contracts.feeRouter, // 8
      contracts.marketRouter, // 9
      contracts.vaultRouter, // 10
      contracts.collateralToken, // 11
      contracts.globalValid, // 12
      contracts.orderMgr, // 13
    ], // Enter array of addresses here
    _openStoreLong: orderBookLongContracts.orderStoreOpen.address, // Enter open store long address here
    _closeStoreLong: orderBookLongContracts.orderStoreClose.address, // Enter close store long address here
    _openStoreShort: orderBookShortContracts.orderStoreOpen.address, // Enter open store short address here
    _closeStoreShort: orderBookShortContracts.orderStoreClose.address, // Enter close store short address here
    _minSlippage: configs.minSlippage,
    _maxSlippage: configs.maxSlippage,
    _minLeverage: configs.minLeverage,
    _maxLeverage: configs.maxLeverage,
    _maxTradeAmount: configs.maxTradeAmount,
    _minPay: configs.minPay,
    _minCollateral: configs.minCollateral,
    _allowOpen: configs.allowOpen,
    _allowClose: configs.allowClose,
    _tokenDigits: configs.tokenDigits,
  };

  await factoryCreateMarket(createInputs);

  return {
    market: market,
    positionBook: positionBook,
    marketValid: marketValid,
    orderBookLong: orderBookLongContracts.orderBook,
    orderBookShort: orderBookShortContracts.orderBook,
    openStoreLong: orderBookLongContracts.orderStoreOpen.address,
    closeStoreLong: orderBookLongContracts.orderStoreClose.address,
    openStoreShort: orderBookShortContracts.orderStoreOpen.address,
    closeStoreShort: orderBookShortContracts.orderStoreClose.address,
  };
}

async function createMarketPlace(writeJson) {
  const [owner, second, third] = await ethers.getSigners();
  const globalValid = await deployGlobalValid(writeJson);
  const usdc = await deployUSDC(
    "USDC",
    "USDC",
    "1000000000000000000",
    writeJson
  );
  const priceFeed = await deployOracle(writeJson);
  const factory = await deployMarketFactory(writeJson);
  const marketRouter = await deployMarketRouter(factory.address, writeJson);
  const orderMgr = await deployOrderMgr(writeJson);
  const positionAddMgr = await deployPositionAddMgr(writeJson);
  const positionSubMgr = await deployPositionSubMgr(writeJson);
  const marketValid = await deployMarketValid(factory.address, writeJson);
  const positionBook = await deployPositionBook(factory.address, writeJson);
  const orderBookLongContracts = await deployOrderBook(
    factory.address,
    true,
    writeJson
  );
  const orderBookShortContracts = await deployOrderBook(
    factory.address,
    false,
    writeJson
  );
  ///isInit
  const feeContracts = await deployFee(factory.address, true, true, writeJson);
  const market = await deployMarket(factory.address, writeJson);
  const vaultRouter = await deployVaultRouter(writeJson);
  const addressjson = {
    ETH: "0x62CAe0FA2da220f43a51F86Db2EDb36DcA9A5A08",
    BTC: "0x6550bc2301936011c1334555e62A87705A81C12C",
  };

  let addrs = [
    positionBook.address,
    orderBookLongContracts.orderBook.address,
    orderBookShortContracts.orderBook.address,
    marketValid.address,
    priceFeed.address,
    positionSubMgr.address,
    positionAddMgr.address,
    //indexToken.address,
    "0x62CAe0FA2da220f43a51F86Db2EDb36DcA9A5A08",
    feeContracts.feeRouter.address,
    marketRouter.address,
    vaultRouter.address,
    usdc.address,
    globalValid.address,
    orderMgr.address,
  ];
  await initialize("ETH/USD", addrs);

  return {
    globalValid: globalValid,
    priceFeed: priceFeed,
    factory: factory,
    marketRouter: marketRouter,
    orderMgr: orderMgr,
    positionAddMgr: positionAddMgr,
    positionSubMgr: positionSubMgr,
    marketValid: marketValid,
    positionBook: positionBook,
    orderBookLongContracts: orderBookLongContracts,
    orderBookShortContracts: orderBookShortContracts,
    feeContracts: feeContracts,
    market: market,
    vaultRouter: vaultRouter,
  };
}

module.exports = {
  deployGlobalMarket,
  createMarket,
  createMarketPlace,
};
