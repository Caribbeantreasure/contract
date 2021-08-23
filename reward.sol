// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract reward is Ownable {
    using SafeERC20 for ERC20;
    using SafeMath for uint256;

    // 两个Address   一个 poolAddress   一个rewardCoinAddress
    address immutable _poolAddress;
    address immutable _coinAddress;

    struct depositInfo {
        uint256 depositAmount;
        uint256 rewardAmount;
        uint256 startDepositBlock;
        uint256 lastRewardBlock;
    }

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    mapping(address => depositInfo) private _deposit;
    uint256 public _rewardPerCycle;
    uint256 public _blockNumPreCycle;
    uint256 private _donateRate;
    uint256 public _pubishAmount;
    uint256 public _totalDepositAmount;
    uint256 public _totalPower;
    uint256 public _unSettleAmount;
    uint256 public _lastSettleNum;

    constructor(address poolAddress, address coinAddress) public {
        _poolAddress = poolAddress;
        _coinAddress = coinAddress;
        _totalDepositAmount = 0;
        _totalPower = 0;
        _unSettleAmount = 0;
        _lastSettleNum = block.number;
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }

    function setRewardParam(
        uint256 rewardPerCycle,
        uint256 blockPerCycle,
        uint256 punishRate
    ) public onlyOwner {
        _rewardPerCycle = rewardPerCycle;
        _blockNumPreCycle = blockPerCycle;
        _donateRate = punishRate;
    }

    function getPoolAddress() public view returns (address) {
        return _poolAddress;
    }

    function getCoinAddress() public view returns (address) {
        return _coinAddress;
    }

    function getUserReward(address user) public view returns (uint256) {
        depositInfo memory tempDeposit = _deposit[user];

        if (tempDeposit.depositAmount == 0) {
            return 0;
        }
        uint256 settleAmount;
        uint256 totalPower;
        uint256 lastSettleNum;
        if (block.number >= _lastSettleNum.add(_blockNumPreCycle)) {
            uint256 blockDiff = block.number.sub(_lastSettleNum);
            uint256 cycleNum = blockDiff.div(_blockNumPreCycle);
            settleAmount = _unSettleAmount + cycleNum.mul(_rewardPerCycle);
            uint256 rewardBlockNumber = cycleNum.mul(_blockNumPreCycle);
            totalPower =
                _totalPower +
                _totalDepositAmount.mul(rewardBlockNumber);
            lastSettleNum = _lastSettleNum + rewardBlockNumber;
        }
        uint256 depositPower = tempDeposit.depositAmount.mul(
            lastSettleNum.sub(tempDeposit.lastRewardBlock)
        );
        return
            tempDeposit.rewardAmount +
            depositPower.mul(settleAmount).div(totalPower);
    }

    function settleReward() internal {
        require(_blockNumPreCycle > 0, "contract does not init");
        if (block.number >= _lastSettleNum.add(_blockNumPreCycle)) {
            uint256 blockDiff = block.number.sub(_lastSettleNum);
            uint256 cycleNum = blockDiff.div(_blockNumPreCycle);
            _unSettleAmount += cycleNum.mul(_rewardPerCycle);
            uint256 rewardBlockNumber = cycleNum.mul(_blockNumPreCycle);
            _totalPower += _totalDepositAmount.mul(rewardBlockNumber);
            _lastSettleNum += rewardBlockNumber;
        }
    }

    function settleDeposit(address user) internal {
        settleReward();
        depositInfo memory tempDeposit = _deposit[user];
        if (tempDeposit.depositAmount == 0) {
            return;
        }
        if (tempDeposit.lastRewardBlock >= _lastSettleNum) {
            return;
        }
        uint256 depositPower = tempDeposit.depositAmount.mul(
            _lastSettleNum.sub(tempDeposit.lastRewardBlock)
        );
        tempDeposit.rewardAmount += depositPower.mul(_unSettleAmount).div(
            _totalPower
        );
        tempDeposit.lastRewardBlock = _lastSettleNum;

        _deposit[user] = tempDeposit;
    }

    function deposit(uint256 amount) public {
        ERC20 poolToken = ERC20(_poolAddress);
        poolToken.safeTransferFrom(msg.sender, address(this), amount);
        settleDeposit(msg.sender);
        depositInfo memory tempDeposit = _deposit[msg.sender];
        tempDeposit.depositAmount += amount;
        _deposit[msg.sender] = tempDeposit;
        if (tempDeposit.startDepositBlock == 0) {
            tempDeposit.startDepositBlock = block.number;
        }

        if (tempDeposit.lastRewardBlock == 0) {
            tempDeposit.lastRewardBlock = block.number;
        }
        _totalDepositAmount += amount;
        _deposit[msg.sender] = tempDeposit;
    }

    function settle() public nonReentrant {
        settleDeposit(msg.sender);
        depositInfo memory tempDeposit = _deposit[msg.sender];
        ERC20 coinToken = ERC20(_coinAddress);
        uint256 balanceRest = coinToken.balanceOf(address(this));
        uint256 settleAmount = balanceRest > tempDeposit.rewardAmount
            ? tempDeposit.rewardAmount
            : balanceRest;
        require(settleAmount > 0, "no reward amount");
        coinToken.safeTransfer(msg.sender, settleAmount);
        tempDeposit.rewardAmount -= settleAmount;
        _deposit[msg.sender] = tempDeposit;
    }

    function claim() public nonReentrant {
        settleDeposit(msg.sender);
        depositInfo memory tempDeposit = _deposit[msg.sender];
        require(tempDeposit.depositAmount > 0, "no deposit");
        uint256 claimAmount = tempDeposit.depositAmount;
        claimAmount = claimAmount.mul(_donateRate).div(10000);
        ERC20 poolToken = ERC20(_poolAddress);
        poolToken.safeTransfer(msg.sender, claimAmount);
        _pubishAmount += tempDeposit.depositAmount.sub(claimAmount);

        ERC20 coinToken = ERC20(_coinAddress);
        uint256 balanceRest = coinToken.balanceOf(address(this));
        uint256 settleAmount = balanceRest > tempDeposit.rewardAmount
            ? tempDeposit.rewardAmount
            : balanceRest;
        if (settleAmount > 0) {
            coinToken.safeTransfer(msg.sender, settleAmount);
        }
        _totalDepositAmount -= tempDeposit.depositAmount;
        delete _deposit[msg.sender];
    }

    function receivePunish() public onlyOwner {
        ERC20 poolToken = ERC20(_poolAddress);
        poolToken.safeTransfer(msg.sender, _pubishAmount);
        _pubishAmount = 0;
    }

    function getTotalDeposit() public view returns (uint256) {
        return _totalDepositAmount;
    }

    function getUserDeposit(address user)
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        depositInfo memory tempDeposit = _deposit[user];
        return (
            tempDeposit.depositAmount,
            tempDeposit.rewardAmount,
            tempDeposit.startDepositBlock,
            tempDeposit.lastRewardBlock
        );
    }
}
