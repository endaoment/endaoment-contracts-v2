//SPDX-License-Identifier: BSD 3-Clause
pragma solidity ^0.8.12;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { Registry } from "./Registry.sol";
import { Entity } from "./Entity.sol";
import { Authority, Auth } from "./lib/auth/Auth.sol";
import { Math } from "./lib/Math.sol";

abstract contract Portfolio is ERC20, Auth {

    Registry public immutable registry;
    uint256 public cap;
    uint256 public redemptionFee;
    address public immutable asset;
    uint256 public totalAssets;

    error Unauthorized();
    error TransferDisallowed();
    error NotEntity();
    error ExceedsCap();
    error PercentageOver100();

    /// @notice `sender` has exchanged `assets` for `shares`, and transferred those `shares` to `receiver`.
    event Deposit(address indexed sender, address indexed receiver, uint256 assets, uint256 shares);

    /// @notice `sender` has exchanged `shares` for `assets`, and transferred those `assets` to `receiver`.
    event Redeem(address indexed sender, address indexed receiver, uint256 assets, uint256 shares);

    /// @notice Event emitted when `cap` is set.
    event CapSet(uint256 cap);

    /// @notice Event emitted when `redemptionFee` is set.
    event RedemptionFeeSet(uint256 fee);

    /**
     * @param _registry Endaoment registry.
     * @param _name Name of the ERC20 Portfolio share tokens.
     * @param _symbol Symbol of the ERC20 Portfolio share tokens.
     * @param _cap Amount in baseToken that value of totalAssets should not exceed.
     * @param _redemptionFee Percentage fee as ZOC that will go to treasury on share redemption.
     */
    constructor(Registry _registry, address _asset, string memory _name, string memory _symbol, uint256 _cap, uint256 _redemptionFee) ERC20(_name, _symbol, ERC20(_asset).decimals()) Auth(address(0), Authority(address(_registry))) {
        registry = _registry;
        redemptionFee = _redemptionFee;
        cap = _cap;
        asset = _asset;
    }

    /**
     * @notice Modifier for methods that require auth.
     * @dev Overridden from Auth.sol. Reason: use custom error.
     */
    modifier requiresAuth override {
        if(!isAuthorized(msg.sender, msg.sig)) revert Unauthorized();

        _;
    }

    /**
     * @notice Function used to determine whether an Entity is active on the registry.
     * @param _entity The Entity.
     */
    function _isEntity(Entity _entity) internal view returns (bool) {
        return registry.isActiveEntity(_entity);
    }

    /**
     * @notice Set the Portfolio cap.
     * @param _amount Amount, denominated in baseToken.
     */
    function setCap(uint256 _amount) external virtual requiresAuth {
        cap = _amount;
        emit CapSet(_amount);
    }

    /**
     * @notice Set redemption fee.
     * @param _pct Percentage as ZOC (e.g. 1000 = 10%).
     */
    function setRedemptionFee(uint256 _pct) external virtual requiresAuth {
        if(_pct > Math.ZOC) revert PercentageOver100();
        redemptionFee = _pct;
        emit RedemptionFeeSet(_pct);
    }

    function takeFees(uint256 _AmountAssets) external virtual;

    // /// @notice The address of the underlying ERC20 token used for the Portfolio for accounting, depositing, and withdrawing.
    // function asset() external view virtual returns (address asset);

    /**
     * @notice Exchange `_amountBaseToken` for some amount of Portfolio shares.
     * @param _amountBaseToken The amount of the Entity's baseToken to deposit.
     * @param _data Data that the portfolio needs to make the deposit. In some cases, this will be swap parameters.
     * @return shares The amount of shares that this deposit yields to the Entity.
     */
    function deposit(uint256 _amountBaseToken, bytes calldata _data) virtual external returns (uint256 shares);
    
    /**
     * @notice Exchange `_amountShares` for some amount of baseToken.
     * @param _amountShares The amount of the Entity's portfolio shares to exchange.
     * @param _data Data that the portfolio needs to make the redemption. In some cases, this will be swap parameters.
     * @return baseTokenOut The amount of baseToken that this redemption yields to the Entity.
     */
    function redeem(uint256 _amountShares, bytes calldata _data) virtual external returns (uint256 baseTokenOut);
    
    
    /**
     * @notice The amount of shares that the Portfolio should exchange for the amount of assets provided.
     * @param _amountAssets Amount of assets.
     */
    function convertToShares(uint256 _amountAssets) virtual public view returns (uint256);

    /**
     * @notice The amount of assets that the Portfolio should exchange for the amount of shares provided.
     * @param _amountShares Amount of shares.
     */
    function convertToAssets(uint256 _amountShares) virtual public view returns (uint256);
    
    /// @notice `transfer` disabled on Portfolio tokens.
    function transfer(address /** to */, uint256 /** amount */) public pure override returns (bool) {
        revert TransferDisallowed();
    }

    /// @notice `transferFrom` disabled on Portfolio tokens.
    function transferFrom(address /** from */, address /** to */, uint256 /** amount */) public pure override returns (bool) {
        revert TransferDisallowed();
    }

    /// @notice `transferFrom` disabled on Portfolio tokens.
    function approve(address /** to */, uint256 /** amount */) public pure override returns (bool) {
        revert TransferDisallowed();
    }

    /**
     * @dev We override Auth.sol:isAuthorized() in order to achieve the following:
     * - Instead of asking this Portfolio about roles and such, ask the Registry.
     *   - Reason: We want to manage all permissions in one place -- on the Registry.
     * - Instead of passing `address(this)` to `auth.canCall`, we pass `address(bytes20("portfolio"))`
     *   - Reason: We are meeting the requirement to scope permissions across all Portfolios together.
     * - Instead of asking this Portfolio about its Auth `owner`, we ask the Registry.
     *   - Reason: We want to manage `owner` in one place -- on the Registry.
     */
    function isAuthorized(address user, bytes4 functionSig) internal view override returns (bool) {
        // Instead of asking this Entity about roles and capabilities, ask the Registry.
        Authority auth = registry.authority();

        // We make a couple small modifications to reframe auth in terms of Registry.
        return (address(auth) != address(0) && auth.canCall(user, address(bytes20("portfolio")), functionSig)) || user == registry.owner();
    }

}
