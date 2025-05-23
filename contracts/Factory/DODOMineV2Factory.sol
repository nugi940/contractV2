/*

    Copyright 2021 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0

*/

pragma solidity ^0.8.29;
pragma experimental ABIEncoderV2;

import {InitializableOwnable} from "../lib/InitializableOwnable.sol";
import {ICloneFactory} from "../lib/CloneFactory.sol";

interface IMineV2 {
    function init(address owner, address token) external;

    function addRewardToken(
        address rewardToken,
        uint256 rewardPerBlock,
        uint256 startBlock,
        uint256 endBlock
    ) external;

    function transferOwnership(address newOwner) external;
}

/**
 * @title DODOMineV2 Factory
 * @author DODO Breeder
 *
 * @notice Create And Register DODOMineV2 Contracts 
 */
contract DODOMineV2Factory is InitializableOwnable {
    // ============ Templates ============

    address public immutable _CLONE_FACTORY_;
    address public _DEFAULT_MAINTAINER_;
    address public _MINEV2_TEMPLATE_;

    // mine -> stakeToken
    mapping(address => address) public _MINE_REGISTRY_;
    // stakeToken -> mine
    mapping(address => address) public _STAKE_REGISTRY_;

    // ============ Events ============

    event NewMineV2(address mine, address stakeToken);
    event RemoveMineV2(address mine, address stakeToken);

    constructor(
        address cloneFactory,
        address mineTemplate,
        address defaultMaintainer
    ) public {
        _CLONE_FACTORY_ = cloneFactory;
        _MINEV2_TEMPLATE_ = mineTemplate;
        _DEFAULT_MAINTAINER_ = defaultMaintainer;
    }

    // ============ Functions ============

    function createDODOMineV2(
        address stakeToken,
        address[] memory rewardTokens,
        uint256[] memory rewardPerBlock,
        uint256[] memory startBlock,
        uint256[] memory endBlock
    ) external onlyOwner returns (address newMineV2) {
        require(rewardTokens.length > 0, "REWARD_EMPTY");
        require(rewardTokens.length == rewardPerBlock.length, "REWARD_PARAM_NOT_MATCH");
        require(startBlock.length == rewardPerBlock.length, "REWARD_PARAM_NOT_MATCH");
        require(endBlock.length == rewardPerBlock.length, "REWARD_PARAM_NOT_MATCH");

        newMineV2 = ICloneFactory(_CLONE_FACTORY_).clone(_MINEV2_TEMPLATE_);

        IMineV2(newMineV2).init(address(this), stakeToken);

        for(uint i = 0; i<rewardTokens.length; i++) {
            IMineV2(newMineV2).addRewardToken(
                rewardTokens[i],
                rewardPerBlock[i],
                startBlock[i],
                endBlock[i]
            );
        }

        IMineV2(newMineV2).transferOwnership(_DEFAULT_MAINTAINER_);

        _MINE_REGISTRY_[newMineV2] = stakeToken;
        _STAKE_REGISTRY_[stakeToken] = newMineV2;

        emit NewMineV2(newMineV2, stakeToken);
    }

    // ============ Admin Operation Functions ============
    
    function updateMineV2Template(address _newMineV2Template) external onlyOwner {
        _MINEV2_TEMPLATE_ = _newMineV2Template;
    }

    function updateDefaultMaintainer(address _newMaintainer) external onlyOwner {
        _DEFAULT_MAINTAINER_ = _newMaintainer;
    }

    function addByAdmin(
        address mine,
        address stakeToken
    ) external onlyOwner {
        _MINE_REGISTRY_[mine] = stakeToken;
        _STAKE_REGISTRY_[stakeToken] = mine;

        emit NewMineV2(mine, stakeToken);
    }

    function removeByAdmin(
        address mine,
        address stakeToken
    ) external onlyOwner {
        _MINE_REGISTRY_[mine] = address(0);
        _STAKE_REGISTRY_[stakeToken] = address(0);

        emit RemoveMineV2(mine, stakeToken);
    }
}
