// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "../market/GlobalDataTypes.sol";


contract MockGlobalValid{


     function isIncreasePosition(
        GlobalDataTypes.ValidParams memory params
    ) external view returns (bool) {
       return true;
    }

}