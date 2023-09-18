// // SPDX-License-Identifier: BUSL-1.1
// pragma solidity ^0.8.17;

// import {Test} from "../../lib/forge-std/src/Test.sol";
// import {Vm} from "../../lib/forge-std/src/Vm.sol";

// import {CoreVault} from "../../contracts/vault/CoreVault.sol";
// import {RewardDistributor} from "../../contracts/vault/RewardDistributor.sol";
// import {VaultReward} from "../../contracts/vault/VaultReward.sol";
// import {VaultRouter} from "../../contracts/vault/VaultRouter.sol";

// import {FeeRouter} from "../../contracts/fee/FeeRouter.sol";
// import {FeeVault} from "../../contracts/fee/FeeVault.sol";
// import {FundFee} from "../../contracts/fee/FundFee.sol";

// import {Referral} from "../../contracts/referral/Referral.sol";
// import {PositionBook} from "../../contracts/position/PositionBook.sol";
// import {PositionStore} from "../../contracts/position/PositionStore.sol";

// import {OrderBook} from "../../contracts/order/OrderBook.sol";
// import {OrderStore} from "../../contracts/order/OrderStore.sol";

// import {ChainPriceFeed} from "../../contracts/oracle/ChainPriceFeed.sol";
// import {FastPriceFeed} from "../../contracts/oracle/FastPriceFeed.sol";
// import {Price} from "../../contracts/oracle/Price.sol";

// import {GlobalValid} from "../../contracts/market/GlobalValid.sol";
// import {MarketValid} from "../../contracts/market/MarketValid.sol";
// import {MarketFactory} from "../../contracts/market/MarketFactory.sol";
// import {MarketReader} from "../../contracts/market/MarketReader.sol";
// import {MarketRouter} from "../../contracts/market/MarketRouter.sol";
// import {OrderMgr} from "../../contracts/market/OrderMgr.sol";
// import {PositionAddMgr} from "../../contracts/market/PositionAddMgr.sol";
// import {PositionSubMgr} from "../../contracts/market/PositionSubMgr.sol";


// import {USDC} from "../../contracts/mocker/USDC.sol";


// contract DeployContract{

//         CoreVault public coreVault;
//     RewardDistributor public rewardDistributor;
//     VaultReward public vaultReward;
//     VaultRouter public vaultRouter;
//     USDC public usdc;

//     function testVault() public {
//         //vault
//         coreVault = new CoreVault();
//         rewardDistributor = new RewardDistributor();
//         vaultReward = new VaultReward();
//         vaultRouter = new VaultRouter();
//         usdc=new USDC("USDC","USDC",10000000);
//         // coreVault.initialize()
//     }


// }