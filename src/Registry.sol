//SPDX-License-Identifier: BSD 3-Clause
pragma solidity ^0.8.12;
import "solmate/tokens/ERC20.sol";
import "solmate/utils/SafeTransferLib.sol";

import "./Entity.sol";

// --- Errors ---
error Unauthorized();

/**
 * @notice Registry entity - manages Factory and Entity state info
 */
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

    /**
     * @notice Indicates if the sender of a transaction has "admin" priviledges
     */
    function isAdmin() private view returns (bool) {
        return msg.sender == admin;
    }

    /**
     * @notice Fee parsing to convert the special "uint32 max" value to zero, and zero to the "max"
     * @dev After converting, "uint32 max" will cause overflow/revert when used as a fee percentage multiplier and zero will mean no fee
     */
    function _parseFee(uint32 _value) internal pure returns (uint32) {
        if (_value == 0) {
            return type(uint32).max;
        } else if (_value == type(uint32).max) {
            return 0;
        } else {
            return _value;
        }
    }

    // --- External fns ---

    /**
     * @notice Sets the approval state a factory
     */
    function setFactoryApproval(address _factory, bool _isApproved) external {
        if (!isAdmin()) revert Unauthorized();
        isApprovedFactory[_factory] = _isApproved;
    }

    /**
     * @notice Sets the enable/disable state of an Entity
     */
    function setEntityStatus(Entity _entity, bool _isActive) external {
        bool isFactoryDeploying = _isActive && isApprovedFactory[msg.sender];
        if (!isFactoryDeploying && !isAdmin()) revert Unauthorized();
        isActiveEntity[_entity] = _isActive;
    }

    /**
     * @notice Gets lowest possible donation fee pct (as a ZOC) for an Entity, among default and override
     * @dev Makes use of _parseFee, so if no default or override exists, "max" will be returned
     */
    function getDonationFee(Entity _entity) external view returns (uint32) {
        uint32 _default = _parseFee(defaultDonationFee[_entity.entityType()]);
        uint32 _receiverOverride = _parseFee(donationFeeReceiverOverride[_entity]);
        return _receiverOverride < _default ? _receiverOverride : _default;
    }

    /**
     * @notice Gets lowest possible transfer fee pct (as a ZOC) between sender & receiver Entities, among default and overrides
     * @dev Makes use of _parseFee, so if no default or overrides exist, "uint32 max" will be returned
     */
    function getTransferFee(Entity _sender, Entity _receiver) external view returns (uint32) {
        uint32 _default = _parseFee(defaultTransferFee[_sender.entityType()][_receiver.entityType()]);
        uint32 _senderOverride = _parseFee(transferFeeSenderOverride[_sender][_receiver.entityType()]);
        uint32 _receiverOverride = _parseFee(transferFeeReceiverOverride[_sender.entityType()][_receiver]);

        uint32 _lowestFee = _default;
        _lowestFee = _senderOverride < _lowestFee ? _senderOverride : _lowestFee;
        _lowestFee = _receiverOverride < _lowestFee ? _receiverOverride : _lowestFee;

        return _lowestFee;
    }

    // TODO: Admin only setters for fee mappings
}

