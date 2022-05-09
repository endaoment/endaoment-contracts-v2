//SPDX-License-Identifier: BSD 3-Clause
pragma solidity ^0.8.12;

import { Registry } from "../Registry.sol";
import { Entity } from "../Entity.sol";
import { Portfolio } from "../Portfolio.sol";
import { IYVault } from "../interfaces/IYVault.sol";
import { Auth } from "../lib/auth/Auth.sol";
import { Math } from "../lib/Math.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

contract YearnUSDCPortfolio is Portfolio {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    IYVault public constant yvUsdc = IYVault(0xa354F35829Ae975e850e23e9615b11Da1B3dC4DE);
    ERC20 public immutable usdc;

    error AssetMismatch();
    error RoundsToZero();
    error TooFewAssets();

    /**
     * @param _registry Endaoment registry.
     * @param _asset Underlying ERC20 asset token for portfolio.
     * @param _cap Amount of baseToken that this portfolio's asset balance should not exceed.
     * @param _redemptionFee Percentage fee as ZOC that should go to treasury on redemption. (100 = 1%).
     */
    constructor(
        Registry _registry,
        address _asset,
        uint256 _cap,
        uint256 _redemptionFee
    ) Portfolio(_registry, _asset, "Yearn USDC Vault Portfolio Shares", "yvUSDC-PS", _cap, _redemptionFee) {
        usdc = registry.baseToken();
        if (address(usdc) != yvUsdc.token()) revert AssetMismatch(); // Sanity check.
        usdc.approve(address(yvUsdc), type(uint256).max);
    }

    /**
     * @notice Returns the USDC value of all yvUsdc held by this contract.
     */
    function totalAssets() public view override returns (uint256) {
        return convertToUsdc(yvUsdc.balanceOf(address(this)));
    }

    /**
     * @notice Takes some amount of assets from this portfolio as assets under management fee.
     * @param _amountAssets Amount of assets to take.
     */
    function takeFees(uint256 _amountAssets) external override requiresAuth {
        uint256 _sharesEstimate = convertToYvUsdc(_amountAssets);
        uint256 _assets = yvUsdc.withdraw(_sharesEstimate);
        if (_assets < _amountAssets) revert TooFewAssets();

        ERC20(asset).safeTransfer(registry.treasury(), _amountAssets);

    }

    /**
     * @inheritdoc Portfolio
     * @dev Rounding down in both of these favors the portfolio, so the user gets slightly less and the portfolio gets slightly more,
     * that way it prevents a situation where the user is owed x but the vault only has x - epsilon, where epsilon is some tiny number
     * due to rounding error.
     */
    function convertToShares(uint256 _assets) public view override returns (uint256) {
        uint256 _supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        return _supply == 0 ? _assets : _assets.mulDivDown(_supply, totalAssets());
    }

    /**
     * @inheritdoc Portfolio
     * @dev Rounding down in both of these favors the portfolio, so the user gets slightly less and the portfolio gets slightly more,
     * that way it prevents a situation where the user is owed x but the vault only has x - epsilon, where epsilon is some tiny number
     * due to rounding error.
     */
    function convertToAssets(uint256 _shares) public view override returns (uint256) {
        uint256 _supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        return _supply == 0 ? _shares : _shares.mulDivDown(totalAssets(), _supply);
    }

    /**
     * @notice Converts a quantity of yvUSDC to USDC.
     */
    function convertToUsdc(uint256 _yvUsdcAmount) public view returns (uint256) {
        return _yvUsdcAmount.mulMilDown(yvUsdc.pricePerShare());
    }

    /**
     * @notice Converts a quantity of USDC to yvUSDC.
     */
    function convertToYvUsdc(uint256 _usdcAmount) public view returns (uint256) {
        return _usdcAmount.divMilDown(yvUsdc.pricePerShare());
    }

    /**
     * @inheritdoc Portfolio
     * @dev Deposit the specified number of base token assets, which are deposited into Yearn. The `_data`
     * parameter is unused.
     */
    function deposit(uint256 _amountBaseToken, bytes calldata /* _data */) external override returns (uint256) {
        if(!_isEntity(Entity(msg.sender))) revert NotEntity();
        if(totalAssets() + _amountBaseToken > cap) revert ExceedsCap();
        if (_amountBaseToken > yvUsdc.availableDepositLimit()) revert ExceedsCap();

        uint256 _shares = convertToShares(_amountBaseToken);
        if (_shares == 0) revert RoundsToZero();

        usdc.safeTransferFrom(msg.sender, address(this), _amountBaseToken);
        _mint(msg.sender, _shares);
        emit Deposit(msg.sender, msg.sender, _amountBaseToken, _shares);

        yvUsdc.deposit(_amountBaseToken);
        return _shares;
    }

     /**
     * @inheritdoc Portfolio
     * @dev Redeem the specified number of shares to get back the underlying base token assets, which are
     * withdrawn from Yearn. The `_data` parameter is unused.
     */
    function redeem(uint256 _amountShares, bytes calldata /* _data */) external override returns (uint256) {
        uint256 _yearnShares = convertToYvUsdc(convertToAssets(_amountShares));
        uint256 _assets = yvUsdc.withdraw(_yearnShares);
        if (_assets == 0) revert RoundsToZero();

        _burn(msg.sender, _amountShares);

        uint256 _fee;
        uint256 _netAmount;
        unchecked {
            // unchecked as no possibility of overflow with baseToken precision and redemption fee bound
            _fee = _assets.zocmul(redemptionFee);
            // unchecked as the redemptionFee bound means _fee is guaranteed to be smaller than _assets
            _netAmount = _assets - _fee;
        }
        usdc.safeTransfer(registry.treasury(), _fee);
        usdc.safeTransfer(msg.sender, _netAmount);
        emit Redeem(msg.sender, msg.sender, _assets, _amountShares);
        return _netAmount;
    }

    /**
     * @notice Deposits stray USDC for the benefit of everyone else.
     */
    function sync() external requiresAuth {
        yvUsdc.deposit(usdc.balanceOf(address(this)));
    }
}
