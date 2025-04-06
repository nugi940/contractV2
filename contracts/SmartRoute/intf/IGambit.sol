pragma solidity ^0.8.29;
pragma experimental ABIEncoderV2;

interface IGambit {
    function swap(address _tokenIn, address _tokenOut, address _receiver) external returns (uint256);
}
