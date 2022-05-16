pragma solidity ^0.8.12;

interface ICurveExchange {
   function exchange(address pool, address from, address to, uint256 amount, uint256 expected, address receiver) external payable returns (uint256);
}
