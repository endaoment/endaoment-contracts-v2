pragma solidity 0.8.13;

interface IYVault {
    function availableDepositLimit() external view returns (uint256);
    function balanceOf(address user) external view returns (uint256);
    function deposit(uint256 amount) external returns (uint256);
    function pricePerShare() external view returns (uint256);
    function token() external view returns (address);
    function withdraw(uint256 maxShares) external returns (uint256);
}
