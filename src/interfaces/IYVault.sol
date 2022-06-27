pragma solidity 0.8.13;

interface IYVault {
    function availableDepositLimit() view external returns (uint256);
    function balanceOf(address user) view external returns (uint256);
    function deposit(uint256 amount) external returns (uint256);
    function pricePerShare() view external returns (uint256);
    function token() view external returns (address);
    function withdraw(uint256 maxShares) external returns (uint256);
}
