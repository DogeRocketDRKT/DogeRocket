// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract DogeRocket is ERC20, Ownable, ReentrancyGuard {
    using Math for uint256;

    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18;
    uint256 public constant DEPLOYER_ALLOCATION = 100_000_000 * 10**18;
    uint256 public constant STAKING_REWARDS_ALLOCATION = 400_000_000 * 10**18;
    uint256 public constant LOCKED_ALLOCATION = 300_000_000 * 10**18;
    uint256 public constant VESTED_ALLOCATION = 200_000_000 * 10**18;

    uint256 public constant VESTING_PERIODS = 10;
    uint256 public constant INITIAL_LOCK_DURATION = 365 days;

    uint256 public immutable deploymentTime;

    address public stakingContract;
    address public teamWallet;

    uint256 public lockedRemaining = LOCKED_ALLOCATION;
    uint256 public lockedClaimed;
    uint256 public vestedRemaining = VESTED_ALLOCATION;
    uint256 public vestedClaimed;

    string public metadataCID = "bafkreicab7kdzy3rr4ugaesbeattgoqdhltb5ps2g6yog3c3gebtunrxf4";
    string public contractDescription = "DogeRocket (DRKT) is a sophisticated decentralized ERC20 staking token on Polygon, delivering up to 300% APY through strategic staking, with a 1 billion supply allocated for rewards and long-term stability.";

    event StakingContractUpdated(address indexed oldStaking, address indexed newStaking);
    event TeamWalletUpdated(address indexed oldWallet, address indexed newWallet);
    event MetadataUpdated(string newCID, string newDescription);
    event LockedTokensReleasedToPool(uint256 amount);
    event VestedTokensClaimed(address indexed wallet, uint256 amount);

    constructor(address initialStaking) ERC20("DogeRocket", "DRKT") Ownable(msg.sender) {
        require(initialStaking != address(0), "Invalid staking address");

        stakingContract = initialStaking;
        teamWallet = msg.sender;
        deploymentTime = block.timestamp;

        _mint(msg.sender, DEPLOYER_ALLOCATION);
        _mint(address(this), LOCKED_ALLOCATION + VESTED_ALLOCATION);
        _mint(initialStaking, STAKING_REWARDS_ALLOCATION);
    }

    function setStakingContract(address newStaking) external onlyOwner {
        require(newStaking != address(0), "Zero address");
        emit StakingContractUpdated(stakingContract, newStaking);
        stakingContract = newStaking;
    }

    function setTeamWallet(address newTeam) external onlyOwner {
        require(newTeam != address(0), "Zero address");
        emit TeamWalletUpdated(teamWallet, newTeam);
        teamWallet = newTeam;
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

    function releaseLockedToPool(uint256 amount) external onlyOwner nonReentrant {
        require(block.timestamp >= deploymentTime + INITIAL_LOCK_DURATION, "Initial lock active");

        uint256 periodsElapsed = (block.timestamp - deploymentTime) / 365 days;
        uint256 claimable = Math.mulDiv(LOCKED_ALLOCATION, periodsElapsed, VESTING_PERIODS) - lockedClaimed;

        require(amount <= claimable, "Exceeds claimable");
        require(amount <= lockedRemaining, "Exceeds remaining");

        lockedRemaining -= amount;
        lockedClaimed += amount;

        _transfer(address(this), stakingContract, amount);

        (bool success, ) = stakingContract.call(
            abi.encodeWithSignature("addRewardsFromVesting(uint256)", amount)
        );
        require(success, "Failed to notify staking");

        emit LockedTokensReleasedToPool(amount);
    }

    function claimVested(uint256 amount) external onlyOwner nonReentrant {
        require(block.timestamp >= deploymentTime + INITIAL_LOCK_DURATION, "Initial lock active");

        uint256 periodsElapsed = (block.timestamp - deploymentTime) / 365 days;
        uint256 claimable = Math.mulDiv(VESTED_ALLOCATION, periodsElapsed, VESTING_PERIODS) - vestedClaimed;

        require(amount <= claimable, "Exceeds claimable");
        require(amount <= vestedRemaining, "Exceeds remaining");

        vestedRemaining -= amount;
        vestedClaimed += amount;

        _transfer(address(this), teamWallet, amount);
        emit VestedTokensClaimed(teamWallet, amount);
    }
}
