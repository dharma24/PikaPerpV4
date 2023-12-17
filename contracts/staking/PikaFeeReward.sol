// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../perp/IPikaPerp.sol";
import "./IPikaStaking.sol";
import "../access/Governable.sol"; // Ensure this provides ownership functionality.

contract PikaFeeReward is Governable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    address public pikaPerp;
    address public pikaStaking;
    address public rewardToken;
    uint256 public tokenBase;

    uint256 public cumulativeRewardPerTokenStored;
    mapping(address => uint256) private claimableReward;
    mapping(address => uint256) private previousRewardPerToken;

    uint256 public constant PRECISION = 10**18;

    event ClaimedReward(address user, address rewardToken, uint256 amount);

    constructor(address _pikaStaking, address _rewardToken, uint256 _tokenBase) {
        pikaStaking = _pikaStaking;
        rewardToken = _rewardToken;
        tokenBase = _tokenBase;
    }

    function setPikaPerp(address _pikaPerp) external onlyOwner {
        require(_pikaPerp != address(0), "PikaPerp address cannot be zero");
        pikaPerp = _pikaPerp;
    }

    function setPikaStaking(address _pikaStaking) external onlyOwner {
        require(_pikaStaking != address(0), "PikaStaking address cannot be zero");
        pikaStaking = _pikaStaking;
    }

    function updateReward(address account) public whenNotPaused {
        if (account == address(0)) return;
        uint256 pikaReward = IPikaPerp(pikaPerp).distributePikaReward() * PRECISION / tokenBase;
        uint256 _totalSupply = IPikaStaking(pikaStaking).totalSupply();
        if (_totalSupply > 0) {
            cumulativeRewardPerTokenStored += pikaReward * PRECISION / _totalSupply;
        }
        if (previousRewardPerToken[account] > 0) {
            claimableReward[account] += IPikaStaking(pikaStaking).balanceOf(account) * (cumulativeRewardPerTokenStored - previousRewardPerToken[account]) / PRECISION;
        }
        previousRewardPerToken[account] = cumulativeRewardPerTokenStored;
    }

    function claimReward(address user) external nonReentrant whenNotPaused {
        updateReward(user);
        uint256 rewardToSend = claimableReward[user] * tokenBase / PRECISION;
        claimableReward[user] = 0;
        if (rewardToSend > 0) {
            _transferOut(user, rewardToSend);
            emit ClaimedReward(user, rewardToken, rewardToSend);
        }
    }

    function getClaimableReward(address account) external view returns (uint256) {
        uint256 currentClaimableReward = claimableReward[account];
        uint256 totalSupply = IPikaStaking(pikaStaking).totalSupply();
        if (totalSupply == 0) return currentClaimableReward;

        uint256 _pendingReward = IPikaPerp(pikaPerp).getPendingPikaReward() * PRECISION / tokenBase;
        uint256 _rewardPerTokenStored = cumulativeRewardPerTokenStored + _pendingReward * PRECISION / totalSupply;
        return currentClaimableReward + IPikaStaking(pikaStaking).balanceOf(account) * (_rewardPerTokenStored - previousRewardPerToken[account]) / PRECISION;
    }

    function _transferOut(address to, uint256 amount) internal {
        require(to != address(0), "Cannot transfer to zero address");
        require(amount > 0, "Amount must be greater than zero");
        if (rewardToken == address(0)) {
            payable(to).sendValue(amount);
        } else {
            IERC20(rewardToken).safeTransfer(to, amount);
        }
    }
}
