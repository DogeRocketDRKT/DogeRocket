// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract DogeRocket is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18;
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
    uint256 public constant LOCKED_VESTING_PERIODS = 10;
    uint256 public constant LOCKED_LOCK_DURATION = 10 * 365 days;

    uint256 public immutable deploymentTime;

    uint256 public rewardPool;
    uint256 public totalStaked;
    uint256 public lockedAmount;
    uint256 public lockedClaimedAmount;
    uint256 public vestedAmount;
    uint256 public vestedClaimedAmount;

    string public metadataCID = "bafkreicab7kdzy3rr4ugaesbeattgoqdhltb5ps2g6yog3c3gebtunrxf4";
    string public contractDescription = "DogeRocket (DRKT) is a sophisticated decentralized ERC20 staking token on Polygon, delivering up to 300% APY through strategic staking, with a 1 billion supply allocated for rewards and long-term stability.";

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
    event RewardClaimed(address indexed user, uint256 reward, uint256 timestamp);
    event LockedTokensClaimed(address indexed wallet, uint256 amount);
    event RewardPoolContribution(address indexed sender, uint256 amount);
    event RewardsExpired(address indexed user, uint256 amount);
    event RewardPoolModified(uint256 previousPool, uint256 newPool);
    event StakePruned(address indexed user);
    event VestedTokensClaimed(address indexed wallet, uint256 amount);
    event MetadataUpdated(string newCID, string newDescription);

    constructor() ERC20("DogeRocket", "DRKT") Ownable(msg.sender) {
        deploymentTime = block.timestamp;
        _mint(msg.sender, Math.mulDiv(MAX_SUPPLY, 10, 100));
        rewardPool = Math.mulDiv(MAX_SUPPLY, 40, 100);
        lockedAmount = Math.mulDiv(MAX_SUPPLY, 30, 100);
        vestedAmount = Math.mulDiv(MAX_SUPPLY, 20, 100);
        emit MetadataUpdated(metadataCID, contractDescription);
    }

    function setMetadata(string calldata newCID, string calldata newDescription) external onlyOwner {
        metadataCID = newCID;
        contractDescription = newDescription;
        emit MetadataUpdated(newCID, newDescription);
    }

    function renounceOwnership() public pure override {
        revert("Not allowed");
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (from == address(0)) {
            require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds max supply");
        }
        super._update(from, to, amount);
    }

    function _calculateDynamicRewardRate() internal view returns (uint256) {
        if (totalStaked == 0) return MIN_REWARD_RATE;
        require(totalStaked < type(uint256).max / MAX_REWARD_RATE, "Total staked too high");
        uint256 temp = Math.mulDiv(totalStaked, MAX_REWARD_RATE, DENOMINATOR);
        uint256 dailyRewardCost = Math.mulDiv(temp, 86400, 1);
        if (dailyRewardCost == 0) return MIN_REWARD_RATE;
        uint256 poolCoverage = Math.mulDiv(rewardPool, 1e18, dailyRewardCost);

        if (poolCoverage >= TARGET_POOL_COVERAGE) {
            return MAX_REWARD_RATE;
        } else {
            return Math.mulDiv(MAX_REWARD_RATE, poolCoverage, TARGET_POOL_COVERAGE);
        }
    }

    function currentAPY() public view returns (uint256) {
        return Math.mulDiv(_calculateDynamicRewardRate(), 365 days * 10000, DENOMINATOR);
    }

    function _harvest(address user) internal {
        if (rewardPool == 0) return;

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
        if (duration > MAX_STAKE_DURATION) {
            duration = MAX_STAKE_DURATION;
        }

        uint256 dynamicRate = _calculateDynamicRewardRate();
        if (dynamicRate > 0) {
            require(duration <= type(uint256).max / dynamicRate, "Multiplication overflow");
        }
        uint256 timeAdjustedRate = Math.mulDiv(duration, dynamicRate, 1);
        require(timeAdjustedRate <= type(uint256).max / amount, "Division overflow");
        uint256 accrued = Math.mulDiv(amount, timeAdjustedRate, DENOMINATOR);

        if (accrued > rewardPool) {
            accrued = rewardPool;
        }

        if (accrued > 0) {
            uint256 previousPool = rewardPool;
            stake.pendingRewards += accrued;
            rewardPool -= accrued;
            emit RewardPoolModified(previousPool, rewardPool);
        }

        stake.lastUpdateTime = uint64(currentTime);
    }

    function donateToPool(uint256 amount) external nonReentrant {
        require(msg.sender != address(0), "Zero address");
        require(amount >= MIN_DONATION, "Amount below minimum");
        require(block.timestamp >= dogeStakes[msg.sender].lastActionTime + STAKE_COOLDOWN, "Too frequent");

        DogeStake storage stake = dogeStakes[msg.sender];
        stake.lastActionTime = uint64(block.timestamp);
        rewardPool += amount;

        IERC20(address(this)).safeTransferFrom(msg.sender, address(this), amount);

        emit RewardPoolContribution(msg.sender, amount);
    }

    function stake(uint256 amount) external nonReentrant {
        require(msg.sender != address(0), "Zero address");
        require(amount >= MIN_STAKE, "Stake below minimum");
        require(amount <= MAX_STAKE, "Stake above maximum");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        require(allowance(msg.sender, address(this)) >= amount, "Insufficient allowance");
        require(block.timestamp >= dogeStakes[msg.sender].lastActionTime + STAKE_COOLDOWN, "Too frequent");

        DogeStake storage stake = dogeStakes[msg.sender];
        uint256 stakeableAmount = amount;
        if (stake.amount + amount > MAX_STAKE) {
            stakeableAmount = MAX_STAKE - stake.amount;
            require(stakeableAmount >= MIN_STAKE, "Adjusted stake limit exceeded");
        }

        _harvest(msg.sender);

        stake.amount += stakeableAmount;
        if (stake.amount > 0 && stake.lastUpdateTime == 0) {
            stake.lastUpdateTime = uint64(block.timestamp);
        }
        stake.lastActionTime = uint64(block.timestamp);
        if (stake.stakeStartTime == 0) {
            stake.stakeStartTime = uint64(block.timestamp);
        }
        totalStaked += stakeableAmount;
        emit TokensStaked(msg.sender, stakeableAmount);

        IERC20(address(this)).safeTransferFrom(msg.sender, address(this), stakeableAmount);
    }

    function unstake(uint256 amount) external nonReentrant {
        require(amount > 0, "Zero amount");
        require(amount <= MAX_STAKE, "Amount above maximum");
        require(balanceOf(address(this)) >= amount, "Insufficient contract balance");

        DogeStake storage stake = dogeStakes[msg.sender];
        require(stake.amount >= amount, "Insufficient staked amount");
        require(block.timestamp >= stake.lastActionTime + STAKE_COOLDOWN, "Too frequent");
        require(block.timestamp >= stake.stakeStartTime + MIN_STAKE_DURATION, "Minimum stake duration not met");

        _harvest(msg.sender);

        stake.amount -= amount;
        stake.lastActionTime = uint64(block.timestamp);
        totalStaked -= amount;
        uint256 fee = Math.mulDiv(amount, WITHDRAW_FEE, 10_000);
        uint256 transferAmount = amount - fee;
        rewardPool += fee;

        if (stake.amount == 0 && stake.pendingRewards == 0) {
            stake.lastUpdateTime = 0;
            stake.stakeStartTime = 0;
            delete dogeStakes[msg.sender];
            emit StakePruned(msg.sender);
        }
        emit TokensUnstaked(msg.sender, transferAmount, fee);

        IERC20(address(this)).safeTransfer(msg.sender, transferAmount);
    }

    function claimReward() external nonReentrant {
        DogeStake storage stake = dogeStakes[msg.sender];
        require(block.timestamp >= stake.lastActionTime + STAKE_COOLDOWN, "Too frequent");

        _harvest(msg.sender);

        uint256 reward = stake.pendingRewards;
        require(reward > 0, "No rewards to claim");
        require(reward <= balanceOf(address(this)), "Insufficient contract balance");

        stake.pendingRewards = 0;
        stake.lastActionTime = uint64(block.timestamp);
        if (stake.amount == 0 && stake.pendingRewards == 0) {
            stake.lastUpdateTime = 0;
            stake.stakeStartTime = 0;
            delete dogeStakes[msg.sender];
            emit StakePruned(msg.sender);
        }
        emit RewardClaimed(msg.sender, reward, block.timestamp);

        IERC20(address(this)).safeTransfer(msg.sender, reward);
    }

    function calculateReward(address user) public view returns (uint256) {
        require(user != address(0), "Zero address");

        if (rewardPool == 0) return dogeStakes[user].pendingRewards;

        DogeStake memory stake = dogeStakes[user];
        uint256 amount = stake.amount;
        uint256 lastUpdateTime = stake.lastUpdateTime;

        if (amount == 0 || lastUpdateTime == 0) return stake.pendingRewards;

        uint256 currentTime = block.timestamp;
        uint256 pending = stake.pendingRewards;

        if (currentTime > lastUpdateTime + MAX_CLAIM_WINDOW) {
            pending = 0;
        }

        uint256 duration = currentTime - lastUpdateTime;
        if (duration == 0) return pending;
        if (duration > MAX_STAKE_DURATION) {
            duration = MAX_STAKE_DURATION;
        }

        uint256 dynamicRate = _calculateDynamicRewardRate();
        if (dynamicRate > 0 && duration > type(uint256).max / dynamicRate) {
            return pending;
        }
        uint256 timeAdjustedRate = Math.mulDiv(duration, dynamicRate, 1);
        if (timeAdjustedRate > type(uint256).max / amount) {
            return pending;
        }
        uint256 accrued = Math.mulDiv(amount, timeAdjustedRate, DENOMINATOR);
        if (accrued > rewardPool) {
            accrued = rewardPool;
        }
        uint256 totalReward = pending + accrued;

        return totalReward > rewardPool ? rewardPool : totalReward;
    }

    function claimLockedToPool(uint256 amount) external onlyOwner nonReentrant {
        require(block.timestamp >= deploymentTime + 365 days, "Initial lock active");
        uint256 periodsElapsed = (block.timestamp - deploymentTime) / 365 days;
        require(periodsElapsed > 0, "No periods elapsed");

        uint256 totalLockedAllocation = Math.mulDiv(MAX_SUPPLY, 30, 100);
        uint256 claimable = Math.mulDiv(totalLockedAllocation, periodsElapsed, LOCKED_VESTING_PERIODS) - lockedClaimedAmount;
        require(amount <= claimable, "Amount exceeds claimable");
        require(amount <= lockedAmount, "Amount exceeds locked");
        require(amount <= balanceOf(address(this)), "Insufficient contract balance");

        lockedAmount -= amount;
        lockedClaimedAmount += amount;
        rewardPool += amount;
        emit LockedTokensClaimed(address(this), amount);
    }

    function claimVested(uint256 amount) external onlyOwner nonReentrant {
        require(block.timestamp >= deploymentTime + 365 days, "Initial lock active");
        uint256 periodsElapsed = (block.timestamp - deploymentTime) / 365 days;
        require(periodsElapsed > 0, "No periods elapsed");

        uint256 totalVestedAllocation = Math.mulDiv(MAX_SUPPLY, 20, 100);
        uint256 claimable = Math.mulDiv(totalVestedAllocation, periodsElapsed, LOCKED_VESTING_PERIODS) - vestedClaimedAmount;
        require(amount <= claimable, "Amount exceeds claimable");
        require(amount <= vestedAmount, "Amount exceeds vested");
        require(amount <= balanceOf(address(this)), "Insufficient contract balance");

        vestedAmount -= amount;
        vestedClaimedAmount += amount;
        emit VestedTokensClaimed(msg.sender, amount);

        IERC20(address(this)).safeTransfer(msg.sender, amount);
    }
}
