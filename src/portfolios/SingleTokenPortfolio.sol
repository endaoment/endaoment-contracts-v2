//SPDX-License-Identifier: BSD 3-Clause
pragma solidity ^0.8.12;

import { Registry } from "../Registry.sol";
import { Entity } from "../Entity.sol";
import { Portfolio } from "../Portfolio.sol";
import { ISwapWrapper } from "../interfaces/ISwapWrapper.sol";
import { Auth, Authority } from "../lib/auth/Auth.sol";
import { Math } from "../lib/Math.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

contract SingleTokenPortfolio is Portfolio {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    uint256 public exchangeRate;
    uint256 public override totalAssets;

    /**
     * @param _registry Endaoment registry.
     * @param _asset Underlying ERC20 asset token for portfolio.
     * @param _shareTokenName Name of ERC20 portfolio share token.
     * @param _shareTokenSymbol Symbol of ERC20 portfolio share token.
     * @param _cap Amount of baseToken that this portfolio's asset balance should not exceed.
     * @param _redemptionFee Percentage fee as ZOC that should go to treasury on redemption. (100 = 1%).
     */
    constructor(
        Registry _registry,
        address _asset,
        string memory _shareTokenName,
        string memory _shareTokenSymbol,
        uint256 _cap,
        uint256 _redemptionFee
    ) Portfolio(_registry, _asset, _shareTokenName, _shareTokenSymbol, _cap, _redemptionFee) {
        exchangeRate = Math.WAD;
    }

    /**
     * @notice Takes some amount of assets from this portfolio as assets under management fee.
     * @dev Importantly, updates exchange rate to change the shares/assets calculations.
     * @param _amountAssets Amount of assets to take.
     */
    function takeFees(uint256 _amountAssets) external override requiresAuth {
        totalAssets -= _amountAssets;
        exchangeRate = Math.WAD * totalAssets / totalSupply;
        ERC20(asset).safeTransfer(registry.treasury(), _amountAssets);
    }

    /**
     * @inheritdoc Portfolio
     * @dev Rounding down in both of these favors the portfolio, so the user gets slightly less and the portfolio gets slightly more,
     * that way it prevents a situation where the user is owed x but the vault only has x - epsilon, where epsilon is some tiny number
     * due to rounding error.
     */ 
    function convertToShares(uint256 _amount) public view override returns (uint256) {
        return _amount.divWadDown(exchangeRate);
    }

    /**
     * @inheritdoc Portfolio
     * @dev Rounding down in both of these favors the portfolio, so the user gets slightly less and the portfolio gets slightly more,
     * that way it prevents a situation where the user is owed x but the vault only has x - epsilon, where epsilon is some tiny number
     * due to rounding error.
     */ 
    function convertToAssets(uint256 _amount) public view override returns (uint256) {
        return _amount.mulWadDown(exchangeRate);
    }

    /**
     * @inheritdoc Portfolio
     * @dev We convert `baseToken` to `asset` via a swap wrapper.
     * `_data` should be a packed swap wrapper address concatenated with the bytes payload your swap wrapper expects.
     * i.e. `bytes.concat(abi.encodePacked(address swapWrapper), SWAP_WRAPPER_BYTES)`.
     * To determine if this deposit exceeds the cap, we get the asset/baseToken exchange rate and multiply it by `totalAssets`.
     */ 
    function deposit(uint256 _amountBaseToken, bytes calldata _data) external override returns (uint256) {
        if(!_isEntity(Entity(msg.sender))) revert NotEntity();
        ISwapWrapper _swapWrapper = ISwapWrapper(address(bytes20(_data[:20])));
        ERC20 _baseToken = registry.baseToken();
        _baseToken.safeTransferFrom(msg.sender, address(this), _amountBaseToken);
        _baseToken.safeApprove(address(_swapWrapper), 0);
        _baseToken.safeApprove(address(_swapWrapper), _amountBaseToken);
        uint256 _assets = registry.swap(address(_baseToken), asset, address(this), address(this), _amountBaseToken, ISwapWrapper(_swapWrapper), _data[20:]);
        totalAssets += _assets;
        // Convert totalAssets to baseToken unit to measure against cap.
        if(totalAssets * _amountBaseToken / _assets > cap) revert ExceedsCap();
        uint256 _shares = convertToShares(_assets);
        _mint(msg.sender, _shares);
        emit Deposit(msg.sender, msg.sender, _assets, _shares);
        return _shares;
    }

     /**
     * @inheritdoc Portfolio
     * @dev After converting `shares` to `assets`, we convert `assets` to `baseToken` via a swap wrapper.
     * `_data` should be a packed swap wrapper address concatenated with the bytes payload your swap wrapper expects.
     * i.e. `bytes.concat(abi.encodePacked(address swapWrapper), SWAP_WRAPPER_BYTES)`.
     */ 
    function redeem(uint256 _amountShares, bytes calldata _data) external override returns (uint256) {
        ERC20 _baseToken = registry.baseToken();
        ISwapWrapper _swapWrapper = ISwapWrapper(address(bytes20(_data[:20])));
        _burn(msg.sender, _amountShares);
        uint256 _assetsOut = convertToAssets(_amountShares);
        totalAssets -= _assetsOut;
        ERC20(asset).approve(address(_swapWrapper), _assetsOut);
        uint256 _baseTokenOut = registry.swap(asset, address(_baseToken), address(this), address(this), _assetsOut, _swapWrapper, _data[32:]);
        uint256 _fee;
        uint256 _netAmount;
        unchecked {
            // unchecked as no possibility of overflow with baseToken precision
            _fee = _baseTokenOut.zocmul(redemptionFee);
            // unchecked as the _feeMultiplier check with revert above protects against overflow
            _netAmount = _baseTokenOut - _fee;
        }
        _baseToken.safeTransfer(registry.treasury(), _fee);
        _baseToken.safeTransfer(msg.sender, _netAmount);
        emit Redeem(msg.sender, msg.sender, _assetsOut, _amountShares);
        return _netAmount;
    }
}
