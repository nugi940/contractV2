/*

    Copyright 2020 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0

*/

pragma solidity ^0.8.29;


interface ICollateralVault {
    function _OWNER_() external returns (address);

    function init(address owner, string memory name, string memory baseURI) external;

    function directTransferOwnership(address newOwner) external;
}
