/*

    Copyright 2021 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0

*/

pragma solidity ^0.8.29;
pragma experimental ABIEncoderV2;

interface IDPPOracle {
    function init(
        address owner,
        address maintainer,
        address baseTokenAddress,
        address quoteTokenAddress,
        uint256 lpFeeRate,
        address mtFeeRateModel,
        uint256 k,
        uint256 i,
        address o,
        bool isOpenTWAP,
        bool isOracleEnabled
    ) external;

    function _MT_FEE_RATE_MODEL_() external returns (address);

    //=========== admin ==========
    function ratioSync() external;

    function retrieve(
        address payable to,
        address token,
        uint256 amount
    ) external;

    function reset(
        address assetTo,
        uint256 newLpFeeRate,
        uint256 newI,
        uint256 newK,
        uint256 baseOutAmount,
        uint256 quoteOutAmount,
        uint256 minBaseReserve,
        uint256 minQuoteReserve
    ) external returns (bool);


    function tuneParameters(
        uint256 newLpFeeRate,
        uint256 newI,
        uint256 newK,
        uint256 minBaseReserve,
        uint256 minQuoteReserve
    ) external returns (bool);

    function tunePrice(
        uint256 newI,
        uint256 minBaseReserve,
        uint256 minQuoteReserve
    ) external returns (bool);

    function changeOracle(address newOracle) external;

    function enableOracle() external;

    function disableOracle(uint256 newI) external;
}
