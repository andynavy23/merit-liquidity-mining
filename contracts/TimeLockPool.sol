// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./base/BasePool.sol";
import "./interfaces/ITimeLockPool.sol";

contract TimeLockPool is BasePool, ITimeLockPool {
    // TODO implement reward tracking

    using Math for uint256;
    using SafeERC20 for IERC20;

    uint256 public immutable maxBonus;
    uint256 public immutable maxLockDuration;
    
    mapping(address => Deposit[]) public depositsOf;

    struct Deposit {
        uint256 amount;
        uint64 start;
        uint64 end;
    }
    constructor(
        string memory _name,
        string memory _symbol,
        address _depositToken,
        address _rewardToken,
        address _escrowPool,
        uint256 _escrowPortion,
        uint256 _escrowDuration,
        uint256 _maxBonus,
        uint256 _maxLockDuration
    ) BasePool(_name, _symbol, _depositToken, _rewardToken, _escrowPool, _escrowPortion, _escrowDuration) {
        maxBonus = _maxBonus;
        maxLockDuration = _maxLockDuration;
    }

    function deposit(uint256 _amount, uint256 _duration, address _receiver) external override {
        // Don't allow locking > maxLockDuration
        uint256 duration = _duration.min(maxLockDuration);
        depositToken.safeTransferFrom(_msgSender(), address(this), _amount);

        depositsOf[_receiver].push(Deposit({
            amount: _amount,
            start: uint64(block.timestamp),
            end: uint64(block.timestamp) + uint64(duration)
        }));

        uint256 mintAmount = _amount * getMultiplier(duration) / 1e18;

        _mint(_receiver, mintAmount);
    }

    function withdraw(uint256 _depositId, address _receiver) external {
        Deposit memory userDeposit = depositsOf[_msgSender()][_depositId];
        require(block.timestamp >= userDeposit.end, "TimeLockPool.withdraw: too soon");

        uint256 shareAmount = userDeposit.amount * getMultiplier(uint256(userDeposit.end - userDeposit.start)) / 1e18;

        // remove Deposit
        depositsOf[_msgSender()][_depositId] = depositsOf[_msgSender()][depositsOf[_msgSender()].length - 1];
        depositsOf[_msgSender()].pop();

        // burn pool shares
        _burn(_msgSender(), shareAmount);
        
        // return tokens
        depositToken.safeTransfer(_receiver, userDeposit.amount);
    }

    function getMultiplier(uint256 _lockDuration) public view returns(uint256) {
        return 1e18 + (maxBonus * _lockDuration / maxLockDuration);
    }

    function getTotalDeposit(address _account) public view returns(uint256) {
        uint256 total;
        for(uint256 i = 0; i < depositsOf[_account].length; i++) {
            total += depositsOf[_account][i].amount;
        }

        return total;
    }

    function getDepositsOf(address _account) public view returns(Deposit[] memory) {
        return depositsOf[_account];
    }

    function getDepositsOfLength(address _account) public view returns(uint256) {
        return depositsOf[_account].length;
    }
}