/*

    Copyright 2020 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0

*/

pragma solidity ^0.8.29;
pragma experimental ABIEncoderV2;


interface IOracle {
    function getPrice() external view returns (uint256);
}
