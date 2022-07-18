pragma solidity 0.8.13;

interface ICurveExchange {
    function exchange(address pool, address from, address to, uint256 amount, uint256 expected, address receiver)
        external
        payable
        returns (uint256);
}
