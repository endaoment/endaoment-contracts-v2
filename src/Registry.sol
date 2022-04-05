//SPDX-License-Identifier: BSD 3-Clause
pragma solidity ^0.8.12;
import "solmate/tokens/ERC20.sol";
import "solmate/utils/SafeTransferLib.sol";

import "./Entity.sol";

// --- Errors ---
error Unauthorized();

contract Registry {

    // --- Storage ---

    /// @notice Admin address can modify system vars
    address public admin;

    /// @notice Treasury address can receives fees
    address public treasury;

    /// @notice Base Token address is the stable coin contract used throughout the system
    ERC20 public immutable baseToken;

    /// @notice mapping of approved factory contracts that are allowed to register new Entities
    mapping (address => bool) public isApprovedFactory;
    /// @notice mapping of active status of entities
    mapping (Entity => bool) public isActiveEntity;

    /// @notice maps entity type to fee percentage stored as a zoc, where uint32 MAX represents 0
    mapping (uint8 => uint32) defaultDonationFee;
    /// @notice maps specific entity receiver to fee percentage stored as a zoc
    mapping (Entity => uint32) donationFeeReceiverOverride;
    /// @notice maps specific donator to entity type to fee percentage stored as a zoc
    mapping (address => mapping(uint8 => uint32)) donationFeeSenderOverride;

    /// @notice maps sender entity type to receiver entity type to fee percentage as a zoc
    mapping (uint8 => mapping(uint8 => uint32)) defaultTransferFee;
    /// @notice maps specific entity sender to receiver entity type to fee percentage as a zoc
    mapping (Entity => mapping(uint8 => uint32)) transferFeeSenderOverride;
    /// @notice maps sender entity type to specific entity receiver to fee percentage as a zoc
    mapping (uint8 => mapping(Entity => uint32)) transferFeeReceiverOverride;

    // --- Constructor ---
    constructor(address _admin, address _treasury, ERC20 _baseToken) {
        admin = _admin;
        treasury = _treasury;
        baseToken = _baseToken;
    }

    // --- Internal fns ---

    function isAdmin() private view returns (bool) {
        return msg.sender == admin;
    }

    // --- External fns ---

    function setFactoryApproval(address _factory, bool _isApproved) external {
        if (!isAdmin()) revert Unauthorized();
        isApprovedFactory[_factory] = _isApproved;
    }

    function setEntityStatus(Entity _entity, bool _isActive) external {
        bool isFactoryDeploying = _isActive && isApprovedFactory[msg.sender];
        if (!isFactoryDeploying && !isAdmin()) revert Unauthorized();
        isActiveEntity[_entity] = _isActive;
    }

    function getDonationFee(address _sender, Entity _entity) external view returns (uint32) {
        uint32 _default = _flipMaxAndZero(defaultDonationFee[_entity.entityType()]);
        uint32 _senderOverride = _flipMaxAndZero(donationFeeSenderOverride[_sender][_entity.entityType()]);
        uint32 _receiverOverride = _flipMaxAndZero(donationFeeReceiverOverride[_entity]);

        // TODO: helper function lowest(a, b, c)
        uint32 _lowestFee = _default;
        _lowestFee = _senderOverride < _lowestFee ? _senderOverride : _lowestFee;
        _lowestFee = _receiverOverride < _lowestFee ? _receiverOverride : _lowestFee;

        return _lowestFee;
    }

    function getTransferFee(Entity _sender, Entity _receiver) external view returns (uint32) {
        uint32 _default = _flipMaxAndZero(defaultTransferFee[_sender.entityType()][_receiver.entityType()]);
        uint32 _senderOverride = _flipMaxAndZero(transferFeeSenderOverride[_sender][_receiver.entityType()]);
        uint32 _receiverOverride = _flipMaxAndZero(transferFeeReceiverOverride[_sender.entityType()][_receiver]);

        uint32 _lowestFee = _default;
        _lowestFee = _senderOverride < _lowestFee ? _senderOverride : _lowestFee;
        _lowestFee = _receiverOverride < _lowestFee ? _receiverOverride : _lowestFee;

        return _lowestFee;
    }

    /// @dev uint32 max is a special number that represents a fee of 0, whereas the EVM's default of 0 means the fee value
    /// @dev has simply not been set.  This method flips the two to enable this.
    function _flipMaxAndZero(uint32 _value) internal pure returns (uint32) {
        if (_value == 0) {
            return type(uint32).max;
        } else if (_value == type(uint32).max) {
            return 0;
        } else {
            return _value;
        }
    }

    // TODO: Admin only setters for fee mappings
}

