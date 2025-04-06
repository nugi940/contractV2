/*

    Copyright 2020 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0

*/

pragma solidity ^0.8.29;
pragma experimental ABIEncoderV2;

interface IDPPAdmin {
    function init(address owner, address dpp,address operator, address dodoSmartApprove) external;
}
