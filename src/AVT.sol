// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./GAVT.sol";
import "./interfaces/IV3Aggregator.sol";

import "forge-std/console.sol";



contract AVT is ReentrancyGuard, ERC20 {

    using SafeERC20 for ERC20;

    ERC20 pairToken; // Token to pay
    GAVT gavt; // Rewards token
    IV3Aggregator priceFeed;

    bool public vaultActive;

    address admin;

    uint256 avtMinted = 0;
    uint256 collateralDeposited = 0;
    uint256 updateThreshold = 1 hours;
    uint256 avaRatio = 800; // 80% to start with, 1000 == 100% to 1dp percent
    uint256 rewardCap = 10 ether;

    mapping(address => uint256) public userRewards;
    mapping(address => uint256) public userRewardsDebt;


    event Deposited(address, uint256);
    event Withdrawn(address, uint256);
    event GAVTDeposited(uint256);
    event Liquidated(address, uint256);

    error Vault_BadPriceFeed();

    struct Position {
        uint256 collat;
        uint256 avt;
        uint256 timeDeposited;
    }

    mapping(address => Position) public positions;


    constructor(
        address _pairToken, 
        address _avaGovToken,
        address _wethUsdPriceFeed
    ) ERC20("AVA Coin", "AVA") {
        
        admin = msg.sender;
        pairToken = ERC20(_pairToken);
        gavt = GAVT(_avaGovToken);
        priceFeed = IV3Aggregator(_wethUsdPriceFeed);

        vaultActive = true;

    }

    modifier onlyActive() {
        require(vaultActive == true, "Vault Inactive!");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == admin, "Unauthorized!");
        _;
    }

    function setActive(bool _active) external onlyOwner {
        vaultActive = _active;
    }

    function setUpdateThreshold(uint256 _newThreshold) external onlyOwner {
        updateThreshold = _newThreshold;
    }

    function setAvaRatio(uint256 _newRatio) external onlyOwner {
        require(_newRatio <= 1000, "New ratio is too high!");
        avaRatio = _newRatio;

    }

    function setRewardCap(uint256 _newRewardCap) external onlyOwner {
        rewardCap = _newRewardCap;
    }

    function depositRewardTokens(uint256 _amount) external onlyOwner {
        gavt.transferFrom(msg.sender, address(this), _amount);
        emit GAVTDeposited(_amount);
    }

    function deposit(uint256 _amount, address _receiver) external onlyActive nonReentrant {

        uint256 avtValue = valueCollateral(_amount);
        uint256 avtToBorrow = (avtValue * avaRatio) / 1000;

        pairToken.safeTransferFrom(msg.sender, address(this), _amount);
        _borrow(_receiver, avtToBorrow);

        avtMinted += avtToBorrow;
        collateralDeposited += _amount;

        Position memory userPosition = Position({
            collat: _amount,
            avt: avtToBorrow,
            timeDeposited: block.timestamp
        });
        positions[msg.sender] = userPosition;

        uint256 _rewardCap = rewardCap;
        if(userRewards[msg.sender] < _rewardCap) {
            uint256 currentReward = userRewards[msg.sender];
            uint256 rewardAccumulation = _rewardCap - currentReward;
            userRewards[msg.sender] += rewardAccumulation;
        }
        emit Deposited(msg.sender, _amount);

    }


    function liquidate(address _user) external {

        Position memory userPosition = positions[_user];
        uint256 avt = userPosition.avt;
        uint256 userCollat = userPosition.collat;

        uint256 avtValue = valueCollateral(userCollat);

        require(avtValue < avt, "User is not liquidatable!");

        _burn(_user, avt);
        uint256 avtToMint = (avtValue * avaRatio) / 1000;
        _mint(msg.sender, avtToMint); // Ensures x percent of the value of the position to meet the threshold

        Position memory newPosition = Position({
            collat: userCollat,
            avt: avtValue,
            timeDeposited: 0
        });
        positions[msg.sender] = newPosition;
        delete positions[_user];

        emit Liquidated(_user, avt);

    }


    function withdraw(uint256 _amount, address _receiver, bool _claim) external nonReentrant onlyActive {

        uint256 collatToReturn = valueAvt(_amount);

        _repay(msg.sender, _amount);

        avtMinted -= _amount;
        collateralDeposited -= collatToReturn;

        Position memory userPosition = positions[msg.sender];
        userPosition.collat -= collatToReturn;
        userPosition.avt -= _amount;
        if(userPosition.avt == 0) {
            userPosition.timeDeposited = 0;
            delete positions[msg.sender];
        } else {
            positions[msg.sender] = userPosition;
        }

        if(_claim) {
            gavt.transfer(msg.sender, userRewards[msg.sender]);
        } else {
            _withdrawUpdateRewardState(userRewards[msg.sender], false);
        }

        pairToken.safeTransfer(_receiver, collatToReturn);
        emit Withdrawn(msg.sender, _amount);

    }

    function claimRewards() external {
        uint256 reward = userRewards[msg.sender];
        uint256 rewardsDebt = userRewardsDebt[msg.sender];
        if(reward > 0) {
            userRewards[msg.sender] -= reward;
            gavt.transfer(msg.sender, reward);
        }
        else if(rewardsDebt > 0) {
            userRewardsDebt[msg.sender] -= rewardsDebt;
            gavt.transfer(msg.sender, rewardsDebt);
        } 
    }

    function transfer(address to, uint256 value) public override returns(bool) {
        Position memory userPosition = positions[msg.sender];
        uint256 tokenValue = valueAvt(value);
        userPosition.avt -= value;
        userPosition.collat -= tokenValue;

        Position memory toPosition = positions[to];
        toPosition.avt += value;
        toPosition.collat += tokenValue;

        positions[to] = toPosition;
        positions[msg.sender] = userPosition;
        super.transfer(to, value);
        return true;
    }


    function transferFrom(address from, address to, uint256 value) public override returns(bool) {
        Position memory userPosition = positions[from];
        uint256 tokenValue = valueAvt(value);
        userPosition.avt -= value;
        userPosition.collat -= tokenValue; 

        Position memory toPosition = positions[to];
        toPosition.avt += value;
        toPosition.collat += tokenValue;

        positions[to] = toPosition;
        positions[from] = userPosition;
        super.transferFrom(from, to, value);
        return true;
    }

    function _withdrawUpdateRewardState(uint256 _amount, bool _claim) internal {
        uint256 rewards = userRewards[msg.sender];
        if(rewards > 0) {
            userRewards[msg.sender] -= _amount;
        }
        if(!_claim) {
            userRewardsDebt[msg.sender] += _amount;
        }
    }

    function _borrow(address _user, uint256 _amountToBorrow) internal {
        _mint(_user, _amountToBorrow);
    }

    function _repay(address _user, uint256 _amountToRepay) internal {
        uint256 approval = allowance(msg.sender, address(this));
        require(approval > 0, "Tokens not approved!");
        _burn(_user, _amountToRepay);
    }


    function valueCollateral(uint256 _amount) public view returns(uint256) {
        uint256 avtPrice = _getPrice();
        uint256 price = (avtPrice * _amount) / (10 ** 18);
        return price * (10 ** 10);
    }

    function valueAvt(uint256 _amount) public view returns(uint256) {
        uint256 avtPrice = _getPrice();
        return (_amount * (10 ** 8)) / avtPrice; 
    }

    function _getPrice() internal view returns(uint256) {
        (
            uint80 roundId,
            int256 priceInt,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        // Validate chainlink price feed data
        // 1. Price should be greater than 0
        // 2. Updated at timestamp should be within the update threshold
        // 3. Answered in round ID should be the same as round ID
        if (
            priceInt <= 0 ||
            updatedAt < block.timestamp - updateThreshold ||
            answeredInRound != roundId
        ) revert Vault_BadPriceFeed();

        return uint256(priceInt);
    }

}