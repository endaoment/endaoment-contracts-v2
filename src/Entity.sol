//SPDX-License-Identifier: BSD 3-Clause
pragma solidity ^0.8.12;
import "solmate/tokens/ERC20.sol";
import "solmate/utils/SafeTransferLib.sol";

import "./Registry.sol";

/**
 * @notice Entity contract inherited by Org and Fund
 */
abstract contract Entity {
    using  SafeTransferLib for ERC20;

    Registry public immutable registry;
    address public manager;
    ERC20 public immutable baseToken;
    uint256 public balance;

    function entityType() public pure virtual returns (uint8);

    constructor(Registry _registry, address _manager) {
        registry = _registry;
        manager = _manager;
        baseToken = _registry.baseToken();
    }

    function donate(uint256 _amount) external {
        require(registry.isActiveEntity(this));

        uint256 _fee = zocmul(_amount, registry.getDonationFee(this));
        uint256 _netAmount = _amount - _fee; // overflow check prevents fee proportion > 0

        baseToken.safeTransferFrom(msg.sender, registry.treasury(), _fee);
        baseToken.safeTransferFrom(msg.sender, address(this), _netAmount);

        balance += _netAmount;
    }

    function transfer(Entity _to, uint256 _amount) external {
        require(msg.sender == manager);
        require(registry.isActiveEntity(this));
        require(balance >= _amount);

        uint256 _fee = zocmul(_amount, registry.getTransferFee(this, _to));
        uint256 _netAmount = _amount - _fee;

        baseToken.safeTransferFrom(msg.sender, registry.treasury(), _fee);
        baseToken.safeTransfer(address(_to), _netAmount);

        unchecked {
            balance -= _amount;
        }
    }

    // TODO: God mode for admin

    function zocmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * y;
        unchecked {
            z /= 1e4;
        }
    }
}
