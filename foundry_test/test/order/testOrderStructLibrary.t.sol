//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {Vm} from "forge-std/Vm.sol";
import {Order} from "../../../contracts/order/OrderStruct.sol";

contract OrderStructTest is Test {
    function testSetKeepLevOnTP() public {
        Order.Props memory order = Order.Props({
            version: uint8(0),
            updatedAtBlock: uint32(block.number),
            triggerAbove: uint8(0),
            account: msg.sender,
            extra3: uint48(1),
            collateral: uint128(100),
            size: uint128(100),
            price: uint128(100),
            extra1: uint128(100),
            orderID: uint64(1),
            extra2: uint64(0),
            extra0: uint128(0),
            refCode: bytes32("")
        });
        assertEq(Order.getTakeprofit(order), 100);
        Order.setTakeprofit(order, 10000);
        assertEq(Order.getTakeprofit(order), 10000);
    }
}
