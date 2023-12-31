// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "../utils/EnumerableValues.sol";
import "./PositionStruct.sol";
import "../ac/Ac.sol";

contract PositionStore is Ac {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableValues for EnumerableSet.AddressSet;

    // contract address of positionBook
    address public positionBook;
    // position long/short status
    bool public immutable isLong;

    // save user position, address -> position
    mapping(address => Position.Props) private positions;
    // set of position address
    EnumerableSet.AddressSet private positionKeys;
    // global position
    Position.Props private globalPositions;

    event UpdatePositionBook(
        address indexed oldAddress,
        address indexed newAddress
    );
    event UpdatePosition(
        address indexed account,
        uint256 size,
        uint256 collateral
    );
    event RemovePosition(
        address indexed account,
        uint256 size,
        uint256 collateral
    );

    constructor(address factory, bool islong) Ac(factory) {
        positionBook = msg.sender;
        isLong = islong;
        _grantRole(ROLE_CONTROLLER, msg.sender);
        _disableInitializers();
    }

    function setPositionBook(address pb) external onlyManager {
        require(pb != address(0), "invalid address");
        address _old = positionBook;
        _revokeRole(ROLE_CONTROLLER, _old);
        positionBook = pb;
        _grantRole(ROLE_CONTROLLER, pb);
        emit UpdatePositionBook(_old, pb);
    }

    /**
     * @dev Called by `PositionBook`.Sets the position and global position for a specific account.
     * @param account The address of the account.
     * @param position The Props struct representing the position.
     * @param globalPosition The Props struct representing the global position.
     * @dev This function can only be called by the controller.
     */
    function set(
        address account,
        Position.Props calldata position,
        Position.Props calldata globalPosition
    ) external onlyController {
        globalPositions = globalPosition;

        positions[account] = position;
        positionKeys.add(account);

        emit UpdatePosition(account, position.size, position.collateral);
    }

    /**
     * @dev Called by `PositionBook`.Removes the position and updates the global position for a specific account.
     * @param account The address of the account.
     * @param globalPosition The Props struct representing the global position.
     * @dev This function can only be called by the controller.
     */
    function remove(
        address account,
        Position.Props calldata globalPosition
    ) external onlyController {
        bool has = positionKeys.contains(account);
        require(has, "position does not exist");

        globalPositions = globalPosition;

        Position.Props memory _position = positions[account];
        delete positions[account];
        positionKeys.remove(account);

        emit RemovePosition(account, _position.size, _position.collateral);
    }

    function globalSize() external view returns (uint256) {
        return globalPositions.size;
    }

    function getGlobalPosition() external view returns (Position.Props memory) {
        return globalPositions;
    }

    function get(
        address account
    ) external view returns (Position.Props memory) {
        return positions[account];
    }

    function contains(address account) external view returns (bool) {
        return positionKeys.contains(account);
    }

    function getPositionCount() external view returns (uint256) {
        return positionKeys.length();
    }

    function getPositionKeys(
        uint256 start,
        uint256 end
    ) external view returns (address[] memory) {
        return positionKeys.valuesAt(start, end);
    }
}
