/*

    Copyright 2021 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0

*/
pragma solidity ^0.8.29;
pragma experimental ABIEncoderV2;

import {SafeERC20} from "../../lib/SafeERC20.sol";
import {IERC20} from "../../intf/IERC20.sol";
import {DecimalMath} from "../../lib/DecimalMath.sol";
import {InitializableOwnable} from "../../lib/InitializableOwnable.sol";
import {IRewardVault, RewardVault} from "./RewardVault.sol";

contract BaseMine is InitializableOwnable {
    using SafeERC20 for IERC20;

    // ============ Storage ============

    struct RewardTokenInfo {
        address rewardToken;
        uint256 startBlock;
        uint256 endBlock;
        address rewardVault;
        uint256 rewardPerBlock;
        uint256 accRewardPerShare;
        uint256 lastRewardBlock;
        mapping(address => uint256) userRewardPerSharePaid;
        mapping(address => uint256) userRewards;
    }

    RewardTokenInfo[] public rewardTokenInfos;

    uint256 internal _totalSupply;
    mapping(address => uint256) internal _balances;

    // ============ Event =============

    event Claim(uint256 indexed i, address indexed user, uint256 reward);
    event UpdateReward(uint256 indexed i, uint256 rewardPerBlock);
    event UpdateEndBlock(uint256 indexed i, uint256 endBlock);
    event NewRewardToken(uint256 indexed i, address rewardToken);
    event RemoveRewardToken(address rewardToken);
    event WithdrawLeftOver(address owner, uint256 i);

    // ============ View  ============

    function getPendingReward(address user, uint256 i) public view returns (uint256) {
        require(i < rewardTokenInfos.length, "DODOMineV2: REWARD_ID_NOT_FOUND");
        RewardTokenInfo storage rt = rewardTokenInfos[i];
        uint256 accRewardPerShare = rt.accRewardPerShare;
        if (rt.lastRewardBlock != block.number) {
            accRewardPerShare = _getAccRewardPerShare(i);
        }
        return
            DecimalMath.mulFloor(
                balanceOf(user), 
                accRewardPerShare - rt.userRewardPerSharePaid[user]
            ) + rt.userRewards[user];
    }

    function getPendingRewardByToken(address user, address rewardToken) external view returns (uint256) {
        return getPendingReward(user, getIdByRewardToken(rewardToken));
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address user) public view returns (uint256) {
        return _balances[user];
    }

    function getRewardTokenById(uint256 i) external view returns (address) {
        require(i < rewardTokenInfos.length, "DODOMineV2: REWARD_ID_NOT_FOUND");
        RewardTokenInfo storage rt = rewardTokenInfos[i];
        return rt.rewardToken;
    }

    function getIdByRewardToken(address rewardToken) public view returns(uint256) {
        uint256 len = rewardTokenInfos.length;
        for (uint256 i = 0; i < len; i++) {
            if (rewardToken == rewardTokenInfos[i].rewardToken) {
                return i;
            }
        }
        require(false, "DODOMineV2: TOKEN_NOT_FOUND");
    }

    function getRewardNum() external view returns(uint256) {
        return rewardTokenInfos.length;
    }

    // ============ Claim ============

    function claimReward(uint256 i) public {
        require(i < rewardTokenInfos.length, "DODOMineV2: REWARD_ID_NOT_FOUND");
        _updateReward(msg.sender, i);
        RewardTokenInfo storage rt = rewardTokenInfos[i];
        uint256 reward = rt.userRewards[msg.sender];
        if (reward > 0) {
            rt.userRewards[msg.sender] = 0;
            IRewardVault(rt.rewardVault).reward(msg.sender, reward);
            emit Claim(i, msg.sender, reward);
        }
    }

    function claimAllRewards() external {
        uint256 len = rewardTokenInfos.length;
        for (uint256 i = 0; i < len; i++) {
            claimReward(i);
        }
    }

    // =============== Ownable  ================

    function addRewardToken(
        address rewardToken,
        uint256 rewardPerBlock,
        uint256 startBlock,
        uint256 endBlock
    ) external onlyOwner {
        require(rewardToken != address(0), "DODOMineV2: TOKEN_INVALID");
        require(startBlock > block.number, "DODOMineV2: START_BLOCK_INVALID");
        require(endBlock > startBlock, "DODOMineV2: DURATION_INVALID");

        uint256 len = rewardTokenInfos.length;
        for (uint256 i = 0; i < len; i++) {
            require(
                rewardToken != rewardTokenInfos[i].rewardToken,
                "DODOMineV2: TOKEN_ALREADY_ADDED"
            );
        }

        RewardTokenInfo storage rt = rewardTokenInfos.push();
        rt.rewardToken = rewardToken;
        rt.startBlock = startBlock;
        rt.endBlock = endBlock;
        rt.rewardPerBlock = rewardPerBlock;
        rt.rewardVault = address(new RewardVault(rewardToken));

        emit NewRewardToken(len, rewardToken);
    }

    function removeRewardToken(address rewardToken) external onlyOwner {
        uint256 len = rewardTokenInfos.length;
        for (uint256 i = 0; i < len; i++) {
            if (rewardToken == rewardTokenInfos[i].rewardToken) {
                if (i != len - 1) {
                    // Manually copy fields from the last element to the current position
                    RewardTokenInfo storage target = rewardTokenInfos[i];
                    RewardTokenInfo storage last = rewardTokenInfos[len - 1];
                    target.rewardToken = last.rewardToken;
                    target.startBlock = last.startBlock;
                    target.endBlock = last.endBlock;
                    target.rewardVault = last.rewardVault;
                    target.rewardPerBlock = last.rewardPerBlock;
                    target.accRewardPerShare = last.accRewardPerShare;
                    target.lastRewardBlock = last.lastRewardBlock;
                    // Note: Mappings cannot be copied directly; they remain tied to their original storage slot
                }
                rewardTokenInfos.pop();
                emit RemoveRewardToken(rewardToken);
                break;
            }
        }
    }

    function setEndBlock(uint256 i, uint256 newEndBlock)
        external
        onlyOwner
    {
        require(i < rewardTokenInfos.length, "DODOMineV2: REWARD_ID_NOT_FOUND");
        _updateReward(address(0), i);
        RewardTokenInfo storage rt = rewardTokenInfos[i];

        require(block.number < newEndBlock, "DODOMineV2: END_BLOCK_INVALID");
        require(block.number > rt.startBlock, "DODOMineV2: NOT_START");
        require(block.number < rt.endBlock, "DODOMineV2: ALREADY_CLOSE");

        rt.endBlock = newEndBlock;
        emit UpdateEndBlock(i, newEndBlock);
    }

    function setReward(uint256 i, uint256 newRewardPerBlock)
        external
        onlyOwner
    {
        require(i < rewardTokenInfos.length, "DODOMineV2: REWARD_ID_NOT_FOUND");
        _updateReward(address(0), i);
        RewardTokenInfo storage rt = rewardTokenInfos[i];
        
        require(block.number < rt.endBlock, "DODOMineV2: ALREADY_CLOSE");

        rt.rewardPerBlock = newRewardPerBlock;
        emit UpdateReward(i, newRewardPerBlock);
    }

    function withdrawLeftOver(uint256 i, uint256 amount) external onlyOwner {
        require(i < rewardTokenInfos.length, "DODOMineV2: REWARD_ID_NOT_FOUND");
        
        RewardTokenInfo storage rt = rewardTokenInfos[i];
        require(block.number > rt.endBlock, "DODOMineV2: MINING_NOT_FINISHED");

        IRewardVault(rt.rewardVault).withdrawLeftOver(msg.sender, amount);

        emit WithdrawLeftOver(msg.sender, i);
    }

    // ============ Internal  ============

    function _updateReward(address user, uint256 i) internal {
        RewardTokenInfo storage rt = rewardTokenInfos[i];
        if (rt.lastRewardBlock != block.number) {
            rt.accRewardPerShare = _getAccRewardPerShare(i);
            rt.lastRewardBlock = block.number;
        }
        if (user != address(0)) {
            rt.userRewards[user] = getPendingReward(user, i);
            rt.userRewardPerSharePaid[user] = rt.accRewardPerShare;
        }
    }

    function _updateAllReward(address user) internal {
        uint256 len = rewardTokenInfos.length;
        for (uint256 i = 0; i < len; i++) {
            _updateReward(user, i);
        }
    }

    function _getUnrewardBlockNum(uint256 i) internal view returns (uint256) {
        RewardTokenInfo storage rt = rewardTokenInfos[i];
        if (block.number < rt.startBlock || rt.lastRewardBlock > rt.endBlock) {
            return 0;
        }
        uint256 start = rt.lastRewardBlock < rt.startBlock ? rt.startBlock : rt.lastRewardBlock;
        uint256 end = rt.endBlock < block.number ? rt.endBlock : block.number;
        return end - start;
    }

    function _getAccRewardPerShare(uint256 i) internal view returns (uint256) {
        RewardTokenInfo storage rt = rewardTokenInfos[i];
        if (totalSupply() == 0) {
            return rt.accRewardPerShare;
        }
        return
            rt.accRewardPerShare +
            DecimalMath.divFloor(_getUnrewardBlockNum(i) * rt.rewardPerBlock, totalSupply());
    }
}