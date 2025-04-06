/*
    Copyright 2020 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity ^0.8.29;
pragma experimental ABIEncoderV2;

import {SafeERC20} from "../../lib/SafeERC20.sol";
import {DecimalMath} from "../../lib/DecimalMath.sol";
import {IERC20} from "../../intf/IERC20.sol";
import {IDVM} from "../../DODOVendingMachine/intf/IDVM.sol";
import {IDVMFactory} from "../../Factory/DVMFactory.sol";
import {CPStorage} from "./CPStorage.sol";
import {PMMPricing} from "../../lib/PMMPricing.sol";
import {IDODOCallee} from "../../intf/IDODOCallee.sol";

contract CPFunding is CPStorage {
    using SafeERC20 for IERC20;
    
    // ============ Events ============
    
    event Bid(address to, uint256 amount, uint256 fee);
    event Cancel(address to, uint256 amount);
    event Settle();

    // ============ BID & CALM PHASE ============
    
    modifier isBidderAllow(address bidder) {
        require(_BIDDER_PERMISSION_.isAllowed(bidder), "BIDDER_NOT_ALLOWED");
        if(_IS_OVERCAP_STOP) {
            require(_QUOTE_TOKEN_.balanceOf(address(this)) <= _POOL_QUOTE_CAP_, "ALREADY_OVER_CAP");
        }
        _;
    }

    function bid(address to) external isNotForceStop phaseBid preventReentrant isBidderAllow(to) {
        uint256 input = _getQuoteInput();
        uint256 mtFee = DecimalMath.mulFloor(input, _MT_FEE_RATE_MODEL_.getFeeRate(to));
        _transferQuoteOut(_MAINTAINER_, mtFee);
        _mintShares(to, input - mtFee);
        _sync();
        emit Bid(to, input, mtFee);
    }

    function cancel(address to, uint256 amount, bytes calldata data) external phaseBidOrCalm preventReentrant {
        require(_SHARES_[msg.sender] >= amount, "SHARES_NOT_ENOUGH");
        _burnShares(msg.sender, amount);
        _transferQuoteOut(to, amount);
        _sync();

        if(data.length > 0){
            IDODOCallee(to).CPCancelCall(msg.sender, amount, data);
        }

        emit Cancel(msg.sender, amount);
    }

    function _mintShares(address to, uint256 amount) internal {
        _SHARES_[to] = _SHARES_[to] + amount;
        _TOTAL_SHARES_ = _TOTAL_SHARES_ + amount;
    }

    function _burnShares(address from, uint256 amount) internal {
        _SHARES_[from] = _SHARES_[from] - amount;
        _TOTAL_SHARES_ = _TOTAL_SHARES_ - amount;
    }

    // ============ SETTLEMENT ============

    function settle() external isNotForceStop phaseSettlement preventReentrant {
        _settle();

        (uint256 poolBase, uint256 poolQuote, uint256 poolI, uint256 unUsedBase, uint256 unUsedQuote) = getSettleResult();
        _UNUSED_BASE_ = unUsedBase;
        _UNUSED_QUOTE_ = unUsedQuote;

        address _poolBaseToken;
        address _poolQuoteToken;

        if (_UNUSED_BASE_ > poolBase) {
            _poolBaseToken = address(_QUOTE_TOKEN_);
            _poolQuoteToken = address(_BASE_TOKEN_);
        } else {
            _poolBaseToken = address(_BASE_TOKEN_);
            _poolQuoteToken = address(_QUOTE_TOKEN_);
        }

        _POOL_ = IDVMFactory(_POOL_FACTORY_).createDODOVendingMachine(
            _poolBaseToken,
            _poolQuoteToken,
            _POOL_FEE_RATE_,
            poolI,
            DecimalMath.ONE,
            _IS_OPEN_TWAP_
        );

        uint256 avgPrice = unUsedBase == 0 ? _I_ : DecimalMath.divCeil(poolQuote, unUsedBase);
        _AVG_SETTLED_PRICE_ = avgPrice;

        _transferBaseOut(_POOL_, poolBase);
        _transferQuoteOut(_POOL_, poolQuote);

        (_TOTAL_LP_AMOUNT_, ,) = IDVM(_POOL_).buyShares(address(this));

       payable(msg.sender).transfer(_SETTEL_FUND_);

        emit Settle();
    }

    // in case something wrong with base token contract
    function emergencySettle() external isNotForceStop phaseSettlement preventReentrant {
        require(block.timestamp >= _PHASE_CALM_ENDTIME_ + _SETTLEMENT_EXPIRE_, "NOT_EMERGENCY");
        _settle();
        _UNUSED_QUOTE_ = _QUOTE_TOKEN_.balanceOf(address(this));
    }

    function _settle() internal {
        require(!_SETTLED_, "ALREADY_SETTLED");
        _SETTLED_ = true;
        _SETTLED_TIME_ = block.timestamp;
    }

    // ============ Pricing ============

    function getSettleResult() public view returns (uint256 poolBase, uint256 poolQuote, uint256 poolI, uint256 unUsedBase, uint256 unUsedQuote) {
        poolQuote = _QUOTE_TOKEN_.balanceOf(address(this));
        if (poolQuote > _POOL_QUOTE_CAP_) {
            poolQuote = _POOL_QUOTE_CAP_;
        }
        (uint256 soldBase,) = PMMPricing.sellQuoteToken(_getPMMState(), poolQuote);
        poolBase = _TOTAL_BASE_ - soldBase;

        unUsedQuote = _QUOTE_TOKEN_.balanceOf(address(this)) - poolQuote;
        unUsedBase = _BASE_TOKEN_.balanceOf(address(this)) - poolBase;

        uint256 avgPrice = unUsedBase == 0 ? _I_ : DecimalMath.divCeil(poolQuote, unUsedBase);
        uint256 baseDepth = DecimalMath.mulFloor(avgPrice, poolBase);

        if (poolQuote == 0) {
            poolI = _I_;
        } else if (unUsedBase == poolBase) {
            poolI = 1;
        } else if (unUsedBase < poolBase) {
            uint256 ratio = DecimalMath.ONE - DecimalMath.divFloor(poolQuote, baseDepth);
            poolI = avgPrice * ratio * ratio / DecimalMath.ONE2;
        } else if (unUsedBase > poolBase) {
            uint256 ratio = DecimalMath.ONE - DecimalMath.divCeil(baseDepth, poolQuote);
            poolI = ratio * ratio / avgPrice;
        }
    }

    function _getPMMState() internal view returns (PMMPricing.PMMState memory state) {
        state.i = _I_;
        state.K = _K_;
        state.B = _TOTAL_BASE_;
        state.Q = 0;
        state.B0 = state.B;
        state.Q0 = 0;
        state.R = PMMPricing.RState.ONE;
    }

    function getExpectedAvgPrice() external view returns (uint256) {
        require(!_SETTLED_, "ALREADY_SETTLED");
        (uint256 poolBase, uint256 poolQuote, , , ) = getSettleResult();
        return DecimalMath.divCeil(poolQuote, _BASE_TOKEN_.balanceOf(address(this)) - poolBase);
    }

    // ============ Asset In ============

    function _getQuoteInput() internal view returns (uint256 input) {
        return _QUOTE_TOKEN_.balanceOf(address(this)) - _QUOTE_RESERVE_;
    }

    // ============ Set States ============

    function _sync() internal {
        uint256 quoteBalance = _QUOTE_TOKEN_.balanceOf(address(this));
        if (quoteBalance != _QUOTE_RESERVE_) {
            _QUOTE_RESERVE_ = quoteBalance;
        }
    }

    // ============ Asset Out ============

    function _transferBaseOut(address to, uint256 amount) internal {
        if (amount > 0) {
            _BASE_TOKEN_.safeTransfer(to, amount);
        }
    }

    function _transferQuoteOut(address to, uint256 amount) internal {
        if (amount > 0) {
            _QUOTE_TOKEN_.safeTransfer(to, amount);
        }
    }

    function getShares(address user) external view returns (uint256) {
        return _SHARES_[user];
    }
}