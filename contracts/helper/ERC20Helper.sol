/*

    Copyright 2021 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0

*/

pragma solidity ^0.8.29;

interface IERC20ForCheck {
    function decimals() external view returns (uint);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);

    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}


contract ERC20Helper {
    function isERC20(address token, address user, address spender) external view returns(bool isOk, string memory symbol, string memory name, uint decimals, uint256 balance, uint256 allownance) {
        try this.judgeERC20(token, user, spender) returns (string memory _symbol, string memory _name, uint _decimals, uint256 _balance, uint256 _allownance) {
            symbol = _symbol;
            name = _name;
            decimals = _decimals;
            balance = _balance;
            allownance = _allownance;
            isOk = true;
        } catch {
            isOk = false;
        }      
    }

   function judgeERC20(address token, address user, address spender) external view returns(string memory symbol, string memory name, uint decimals, uint256 balance, uint256 allownance) {
        name = IERC20ForCheck(token).name();
        symbol = IERC20ForCheck(token).symbol();
        decimals = IERC20ForCheck(token).decimals();
        
        balance = IERC20ForCheck(token).balanceOf(user);
        allownance = IERC20ForCheck(token).allowance(user,spender);
   }
}
