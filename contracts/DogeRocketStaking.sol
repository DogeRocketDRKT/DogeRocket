// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract DogeRocketStaking is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    IERC20 public token;

    uint256 public constant STAKING_REWARDS_ALLOCATION = 400_000_000 * 10**18;
    uint256 public constant MIN_STAKE = 100 * 10**18;
    uint256 public constant MAX_STAKE = 1_000_000 * 10**18;
    uint256 public constant MAX_STAKE_DURATION = 365 days;
    uint256 public constant MIN_STAKE_DURATION = 14 days;
    uint256 public constant STAKE_COOLDOWN = 24 hours;
    uint256 public constant MIN_REWARD_RATE = 159;
    uint256 public constant MAX_REWARD_RATE = 95130;
    uint256 public constant TARGET_POOL_COVERAGE = 3650 * 1e18;
    uint256 private constant DENOMINATOR = 1_000_000_000_000;
    uint256 public constant MAX_CLAIM_WINDOW = 1095 days;
    uint256 public constant WITHDRAW_FEE = 200;
    uint256 public constant MIN_DONATION = 100 * 10**18;

    uint256 public rewardPool;
    uint256 public totalStaked;

    struct DogeStake {
        uint256 amount;
        uint256 pendingRewards;
        uint64 lastUpdateTime;
        uint64 lastActionTime;
        uint64 stakeStartTime;
    }

    mapping(address => DogeStake) public dogeStakes;

    event TokensStaked(address indexed user, uint256 amount);
    event TokensUnstaked(address indexed user, uint256 amount, uint256 fee);
    event RewardClaimed(address indexed user, uint256 reward);
    event RewardPoolContribution(address indexed sender, uint256 amount);
    event RewardsExpired(address indexed user, uint256 amount);
    event RewardPoolModified(uint256 previousPool, uint256 newPool);
    event StakePruned(address indexed user);
    event TokenSet(address token);

    constructor() Ownable(msg.sender) {}

    modifier tokenSet() {
        require(address(token) != address(0), "Token not set");
        _;
    }

    function setToken(address token_) external onlyOwner {
        require(address(token) == address(0), "Token already set");
        token = IERC20(token_);
        
        require(
            token.balanceOf(address(this)) == STAKING_REWARDS_ALLOCATION,
            "Must have exactly 400M DRKT"
        );

        rewardPool = STAKING_REWARDS_ALLOCATION;

        emit TokenSet(token_);
    }

    function addRewardsFromVesting(uint256 amount) external tokenSet {
        require(msg.sender == address(token), "Only DRKT token contract");
        uint256 previousPool = rewardPool;
        rewardPool += amount;
        emit RewardPoolModified(previousPool, rewardPool);
    }

    function _calculateDynamicRewardRate() internal view returns (uint256) {
        if (totalStaked == 0) return MIN_REWARD_RATE;
        uint256 temp = Math.mulDiv(totalStaked, MAX_REWARD_RATE, DENOMINATOR);
        uint256 dailyRewardCost = Math.mulDiv(temp, 86400, 1);
        if (dailyRewardCost == 0) return MIN_REWARD_RATE;
        uint256 poolCoverage = Math.mulDiv(rewardPool, 1e18, dailyRewardCost);
        return poolCoverage >= TARGET_POOL_COVERAGE ? MAX_REWARD_RATE : Math.mulDiv(MAX_REWARD_RATE, poolCoverage, TARGET_POOL_COVERAGE);
    }

    function currentAPY() public view tokenSet returns (uint256) {
        return Math.mulDiv(_calculateDynamicRewardRate(), 365 days * 10000, DENOMINATOR);
    }

    function _harvest(address user) internal {
        DogeStake storage stake = dogeStakes[user];
        uint256 amount = stake.amount;
        uint64 lastUpdateTime = stake.lastUpdateTime;
        if (amount == 0 || lastUpdateTime == 0) return;

        uint256 currentTime = block.timestamp;
        if (currentTime > lastUpdateTime + MAX_CLAIM_WINDOW) {
            uint256 expired = stake.pendingRewards;
            if (expired > 0) {
                uint256 previousPool = rewardPool;
                stake.pendingRewards = 0;
                rewardPool += expired;
                emit RewardsExpired(user, expired);
                emit RewardPoolModified(previousPool, rewardPool);
            }
        }

        uint256 duration = currentTime - lastUpdateTime;
        if (duration == 0) return;
        if (duration > MAX_STAKE_DURATION) duration = MAX_STAKE_DURATION;

        uint256 dynamicRate = _calculateDynamicRewardRate();
        uint256 timeAdjustedRate = Math.mulDiv(duration, dynamicRate, 1);
        uint256 accrued = Math.mulDiv(amount, timeAdjustedRate, DENOMINATOR);

        if (accrued > rewardPool) accrued = rewardPool;

        if (accrued > 0) {
            uint256 previousPool = rewardPool;
            stake.pendingRewards += accrued;
            rewardPool -= accrued;
            emit RewardPoolModified(previousPool, rewardPool);
        }

        stake.lastUpdateTime = uint64(currentTime);
    }

    function donateToPool(uint256 amount) external nonReentrant tokenSet {
        require(amount >= MIN_DONATION, "Below minimum");
        DogeStake storage stake = dogeStakes[msg.sender];
        require(block.timestamp >= stake.lastActionTime + STAKE_COOLDOWN, "Too frequent");

        stake.lastActionTime = uint64(block.timestamp);
        rewardPool += amount;
        token.safeTransferFrom(msg.sender, address(this), amount);
        emit RewardPoolContribution(msg.sender, amount);
    }

    function stake(uint256 amount) external nonReentrant tokenSet {
        require(amount >= MIN_STAKE, "Below minimum");
        require(amount <= MAX_STAKE, "Above maximum");

        DogeStake storage stake = dogeStakes[msg.sender];
        require(block.timestamp >= stake.lastActionTime + STAKE_COOLDOWN, "Too frequent");

        uint256 stakeableAmount = amount;
        if (stake.amount + amount > MAX_STAKE) {
            stakeableAmount = MAX_STAKE - stake.amount;
            require(stakeableAmount >= MIN_STAKE, "Adjusted stake limit exceeded");
        }

        _harvest(msg.sender);

        stake.amount += stakeableAmount;
        if (stake.lastUpdateTime == 0) stake.lastUpdateTime = uint64(block.timestamp);
        stake.lastActionTime = uint64(block.timestamp);
        if (stake.stakeStartTime == 0) stake.stakeStartTime = uint64(block.timestamp);

        totalStaked += stakeableAmount;

        emit TokensStaked(msg.sender, stakeableAmount);
        token.safeTransferFrom(msg.sender, address(this), stakeableAmount);
    }

    function unstake(uint256 amount) external nonReentrant tokenSet {
        require(amount > 0, "Zero amount");
        DogeStake storage stake = dogeStakes[msg.sender];
        require(stake.amount >= amount, "Insufficient staked");
        require(block.timestamp >= stake.lastActionTime + STAKE_COOLDOWN, "Too frequent");
        require(block.timestamp >= stake.stakeStartTime + MIN_STAKE_DURATION, "Min duration not met");

        _harvest(msg.sender);

        stake.amount -= amount;
        stake.lastActionTime = uint64(block.timestamp);
        totalStaked -= amount;

        uint256 fee = Math.mulDiv(amount, WITHDRAW_FEE, 10_000);
        uint256 transferAmount = amount - fee;
        rewardPool += fee;

        if (stake.amount == 0 && stake.pendingRewards == 0) {
            delete dogeStakes[msg.sender];
            emit StakePruned(msg.sender);
        }

        emit TokensUnstaked(msg.sender, transferAmount, fee);
        token.safeTransfer(msg.sender, transferAmount);
    }

    function claimReward() external nonReentrant tokenSet {
        DogeStake storage stake = dogeStakes[msg.sender];
        require(block.timestamp >= stake.lastActionTime + STAKE_COOLDOWN, "Too frequent");

        _harvest(msg.sender);

        uint256 reward = stake.pendingRewards;
        require(reward > 0, "No rewards");

        stake.pendingRewards = 0;
        stake.lastActionTime = uint64(block.timestamp);

        if (stake.amount == 0 && stake.pendingRewards == 0) {
            delete dogeStakes[msg.sender];
            emit StakePruned(msg.sender);
        }

        emit RewardClaimed(msg.sender, reward);
        token.safeTransfer(msg.sender, reward);
    }

    function calculateReward(address user) public view tokenSet returns (uint256) {
        DogeStake memory stake = dogeStakes[user];
        if (stake.amount == 0 || stake.lastUpdateTime == 0) return stake.pendingRewards;

        uint256 pending = stake.pendingRewards;
        uint256 currentTime = block.timestamp;

        if (currentTime > stake.lastUpdateTime + MAX_CLAIM_WINDOW) {
            pending = 0;
        }

        uint256 duration = currentTime - stake.lastUpdateTime;
        if (duration == 0) return pending;
        if (duration > MAX_STAKE_DURATION) duration = MAX_STAKE_DURATION;

        uint256 dynamicRate = _calculateDynamicRewardRate();
        uint256 timeAdjustedRate = Math.mulDiv(duration, dynamicRate, 1);
        uint256 accrued = Math.mulDiv(stake.amount, timeAdjustedRate, DENOMINATOR);

        if (accrued > rewardPool) accrued = rewardPool;

        return pending + accrued;
    }
}
