//SPDX-License-Identifier: BSD 3-Clause
pragma solidity ^0.8.12;

import { Registry } from "../Registry.sol";
import { Entity } from "../Entity.sol";
import { Portfolio } from "../Portfolio.sol";
import { ICErc20 } from "../interfaces/ICErc20.sol";
import { Auth } from "../lib/auth/Auth.sol";
import { Math } from "../lib/Math.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

contract CompoundUSDCPortfolio is Portfolio {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    ICErc20 public constant cusdc = ICErc20(0x39AA39c021dfbaE8faC545936693aC917d5E7563);
    ERC20 public immutable usdc;

    error AssetMismatch();
    error CompoundError(uint256 errorCode);
    error RoundsToZero();

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
    ) Portfolio(_registry, _asset, "Compound USDC Portfolio Shares", "cUSDC-PS", _cap, _redemptionFee) {
        usdc = registry.baseToken();
        if (address(usdc) != cusdc.underlying()) revert AssetMismatch(); // Sanity check.
        usdc.approve(address(cusdc), type(uint256).max);
    }

    /**
     * @notice Returns the USDC value of all cUSDC held by this contract.
     */
    function totalAssets() public view override returns (uint256) {
        return convertToUsdc(cusdc.balanceOf(address(this)));
    }

    /**
     * @notice Returns the current Compound exchange rate.
     * @dev Compound does not provide a way to get this data as a view method, so we implement it ourselves.
     */
    function compoundExchangeRateCurrent() public view returns (uint256) {
        // If interest accrued in this block, we can use the stored exchange rate.
        uint256 _blockDelta = block.number - cusdc.accrualBlockNumber();
        if (_blockDelta == 0) return cusdc.exchangeRateStored();

        // Otherwise, compute it as (cash + borrows - reserves) / totalSupply. We start by getting stored data.
        uint256 _cash = cusdc.getCash();
        uint256 _borrows = cusdc.totalBorrows();
        uint256 _reserves = cusdc.totalReserves();
        uint256 _supply = cusdc.totalSupply();
        uint256 _reserveFactor = cusdc.reserveFactorMantissa();
        uint256 _borrowRate = cusdc.borrowRatePerBlock();

        // Compute accumulated interest.
        uint256 _interest = (_borrowRate * _blockDelta).mulWadDown(_borrows);

        // Update total borrows and reserves accordingly.
        _borrows += _interest;
        _reserves += _reserveFactor.mulWadDown(_interest);

        // Return the exchange rate.
        return (_cash + _borrows - _reserves).divWadDown(_supply);
    }

    /**
     * @notice Takes some amount of assets from this portfolio as assets under management fee.
     * @param _amountAssets Amount of assets to take.
     */
    function takeFees(uint256 _amountAssets) external override requiresAuth {
        uint256 _errorCode = cusdc.redeemUnderlying(_amountAssets);
        if (_errorCode != 0) revert CompoundError(_errorCode);
        ERC20(asset).safeTransfer(registry.treasury(), _amountAssets);
        // TODO Emit event? STP doesn't emit one either.
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
     * @notice Converts a quantity of cUSDC to USDC
     */
    function convertToUsdc(uint256 _cUsdcAmount) public view returns (uint256) {
        return compoundExchangeRateCurrent().mulWadDown(_cUsdcAmount);
    }

    /**
     * @inheritdoc Portfolio
     * @dev Deposit the specified number of base token assets, which are deposited into Compound. The `_data`
     * parameter is unused.
     */
    function deposit(uint256 _amountBaseToken, bytes calldata /* _data */) external override returns (uint256) {
        if(!_isEntity(Entity(msg.sender))) revert NotEntity();
        if(totalAssets() + _amountBaseToken > cap) revert ExceedsCap();
        uint256 _shares = convertToShares(_amountBaseToken);
        if (_shares == 0) revert RoundsToZero();

        usdc.safeTransferFrom(msg.sender, address(this), _amountBaseToken);
        _mint(msg.sender, _shares);
        emit Deposit(msg.sender, msg.sender, _amountBaseToken, _shares);

        uint256 _errorCode = cusdc.mint(_amountBaseToken);
        if (_errorCode != 0) revert CompoundError(_errorCode);

        return _shares;
    }

     /**
     * @inheritdoc Portfolio
     * @dev Redeem the specified number of shares to get back the underlying base token assets, which are
     * withdrawn from Compound. If the utilization of the Compound market is too high, there may be insufficient
     * funds to redeem and this method will revert. The `_data` parameter is unused.
     */
    function redeem(uint256 _amountShares, bytes calldata /* _data */) external override returns (uint256) {
        uint256 _assets = convertToAssets(_amountShares);
        if (_assets == 0) revert RoundsToZero();

        uint256 _errorCode = cusdc.redeemUnderlying(_assets);
        if (_errorCode != 0) revert CompoundError(_errorCode);

        _burn(msg.sender, _amountShares);

        uint256 _fee;
        uint256 _netAmount;
        unchecked {
            // unchecked as no possibility of overflow with baseToken precision
            _fee = _assets.zocmul(redemptionFee);
            // unchecked as the _feeMultiplier check with revert above protects against overflow
            _netAmount = _assets - _fee;
        }
        usdc.safeTransfer(registry.treasury(), _fee);
        usdc.safeTransfer(msg.sender, _netAmount);
        emit Redeem(msg.sender, msg.sender, _assets, _amountShares);
        return _netAmount;
    }

    /**
     * @notice Deposits stray USDC for the benefit of everyone else
     */
    function sync() external requiresAuth {
        // TODO Should this be public or auth'd?
        uint256 _errorCode = cusdc.mint(usdc.balanceOf(address(this)));
        if (_errorCode != 0) revert CompoundError(_errorCode);
    }
}