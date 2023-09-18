// // SPDX-License-Identifier: BUSL-1.1
// pragma solidity ^0.8.17;

// //import {Test} from "forge-std/Test.sol";
// import {Test} from "../../lib/forge-std/src/Test.sol";
// import {Vm} from "../../lib/forge-std/src/Vm.sol";
// import {CoreVault} from "../../contracts/vault/CoreVault.sol";
// import {USDC} from "../../contracts/mocker/USDC.sol";
// import {VaultRouter} from "../../contracts/vault/VaultRouter.sol";
// import {FeeRouter} from "../../contracts/fee/FeeRouter.sol";
// import {VaultReward} from "../../contracts/vault/VaultReward.sol";
// import {MarketRouter} from "../../contracts/market/MarketRouter.sol";
// //getGlobalSize

// import {console2} from "../../lib/forge-std/src/console2.sol";
// import "../../lib/forge-std/src/StdJson.sol";


// contract ReadContract is Test{

//     struct BlexAddress{
//       address MarketFactory;
//       address ERC20Mocker;
//       address CoreVault;
//       address CoreVaultImpl;
//       address VaultRouter;
//       address VaultRouterImpl;
//       address VaultReward;
//       address VaultRewardImpl;
//       address RewardDistributor;
//       address RewardDistributorImpl;
//       address FeeVault;
//       address FundFee;
//       address FeeRouter;
//       address PositionBook;
//       address OrderBookLong;
//       address OrderBookShort;
//       address OrderStore0;
//       address OrderStore1;
//       address OrderStore2;
//       address OrderStore3;
//       address MarketValid;
//       address PositionAddMgr;
//       address PositionSubMgr;
//       address OrderMgr;
//       address GlobalValid;
//       address MarketRouter;
//       address MarketRouterImpl;
//       address Market;
//       address MarketReader;
//       address ETHAutoOpenLongOrderMock;
//       address ETHAutoOpenShortOrderMock;
//       address ETHAutoCloseLongOrderMock;
//       address ETHAutoCloseShortOrderMock;
//       address amLiq_Long0x642B2C10a1f6d42F4aE2670e218517128F63A3D7;
//       address amLiq_Short0x642B2C10a1f6d42F4aE2670e218517128F63A3D7;
//     }


//     // struct 

//     address factroy;
//     CoreVault public coreVault;
//     USDC public usdc;
//     VaultRouter public vaultRouter;
//     FeeRouter public feeRouter;
//     VaultReward public vaultReward;
   
//     function setUp() public {
        
//     }


//      function testJson()public  view{
//       // bytes  memory  json= vm.readFileBinary('./contract-addresses-arbitrum_42161.json');

//        string  memory  json= vm.readFile('./contract-addresses-localhost.json');
//        console2.log(json);
//       // bytes memory transactionDetails = json.parseRaw(".transactions[0].tx");

//       // //  bytes memory  jsonss=vm.parseJson(json);
//       //  bytes memory sss=vm.parseJson(json, 'MarketFactory');


//       //  address  a=abi.decode(sss,(address));
//       //  console2.log("MarketFactory",a);

//       //  int256 pnl=MarketRouter(a.MarketRouter).getGlobalPNL();
       
// //       console2.log(pnl);

//      }

    
// }

