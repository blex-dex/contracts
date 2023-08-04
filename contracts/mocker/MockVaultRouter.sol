// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract MockVaultRouter {
    uint256 public fundLimit = 10000000;
    uint256 public totalAUM = 1000000;
    uint256 public USDBalance;

    address public temAddress;

    mapping(address => uint256) public fundsUsed; // for different market

    function setFundLimit(uint256 _limit) external {
        fundLimit = _limit;
    }

    function setUSDBalance(uint256 _balance) external {
        USDBalance = _balance;
    }

    function borrowFromVault(uint256 _amount) external {
        temAddress = msg.sender;
        fundsUsed[msg.sender] = fundsUsed[msg.sender] + _amount + 10000;

        require(fundsUsed[msg.sender] <= fundLimit);
    }

    function repayToVault(uint256 _amount) external {
        fundsUsed[msg.sender] = fundsUsed[msg.sender] - _amount + 10000;
    }

    function getUSDBalance() external view returns (uint256) {
        return USDBalance;
    }

    function getAUM() external view returns (uint256) {
        return totalAUM;
    }
}
