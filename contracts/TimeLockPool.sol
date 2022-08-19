// SPDX-License-Identifier: MIT
pragma solidity 0.8.7; // 指定solidity版本其他版本會導致編譯錯誤

// npm i @openzeppelin/contracts
// IERC20(interface): Interface of the ERC20 standard as defined in the EIP.
// SafeERC20(library): Wrappers around ERC20 operations that throw on failure (when the token contract returns false).
// Math(library): Standard math utilities missing in the Solidity language.
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// BasePool(abstract contract)
// ITimeLockPool(interface)
import "./base/BasePool.sol";
import "./interfaces/ITimeLockPool.sol";

// TimeLockPool繼承自BasePool抽象合約, 以及ITimeLockPool接口
contract TimeLockPool is BasePool, ITimeLockPool {
    // Math是以更標準的方式實現數學運算
    // 將名為Math的library裡面撰寫的函式使用在uint256型態的變數上，將uint256型態的變數作為函式第一個參數傳入
    using Math for uint256;
    // SafeERC20是以更安全的方式實現Transfer/Approve，當低級調用失敗時發出錯誤訊息並將transaction revert
    // 將名為SafeERC20的library裡面撰寫的函式使用在IERC20型態的變數上，將IERC20型態的變數作為函式第一個參數傳入
    using SafeERC20 for IERC20;

    // 宣告 公共 uint256型態 名為maxBonus的不可變量
    uint256 public immutable maxBonus;
    // 宣告 公共 uint256型態 名為maxLockDuration的不可變量
    uint256 public immutable maxLockDuration;
    // 宣告 公共 uint256型態 名為MIN_LOCK_DURATION的不可變量
    // MIN_LOCK_DURATION 最少鎖倉期限
    uint256 public constant MIN_LOCK_DURATION = 10 minutes;
    
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
        require(_maxLockDuration >= MIN_LOCK_DURATION, "TimeLockPool.constructor: max lock duration must be greater or equal to mininmum lock duration");
        maxBonus = _maxBonus;
        maxLockDuration = _maxLockDuration;
    }

    event Deposited(uint256 amount, uint256 duration, address indexed receiver, address indexed from);
    event Withdrawn(uint256 indexed depositId, address indexed receiver, address indexed from, uint256 amount);

    function deposit(uint256 _amount, uint256 _duration, address _receiver) external override {
        require(_amount > 0, "TimeLockPool.deposit: cannot deposit 0");
        // Don't allow locking > maxLockDuration
        uint256 duration = _duration.min(maxLockDuration);
        // Enforce min lockup duration to prevent flash loan or MEV transaction ordering
        duration = duration.max(MIN_LOCK_DURATION);

        depositToken.safeTransferFrom(_msgSender(), address(this), _amount);

        depositsOf[_receiver].push(Deposit({
            amount: _amount,
            start: uint64(block.timestamp),
            end: uint64(block.timestamp) + uint64(duration)
        }));

        uint256 mintAmount = _amount * getMultiplier(duration) / 1e18;

        _mint(_receiver, mintAmount);
        emit Deposited(_amount, duration, _receiver, _msgSender());
    }

    function withdraw(uint256 _depositId, address _receiver) external {
        require(_depositId < depositsOf[_msgSender()].length, "TimeLockPool.withdraw: Deposit does not exist");
        Deposit memory userDeposit = depositsOf[_msgSender()][_depositId];
        require(block.timestamp >= userDeposit.end, "TimeLockPool.withdraw: too soon");

        //                      No risk of wrapping around on casting to uint256 since deposit end always > deposit start and types are 64 bits
        uint256 shareAmount = userDeposit.amount * getMultiplier(uint256(userDeposit.end - userDeposit.start)) / 1e18;

        // remove Deposit
        depositsOf[_msgSender()][_depositId] = depositsOf[_msgSender()][depositsOf[_msgSender()].length - 1];
        depositsOf[_msgSender()].pop();

        // burn pool shares
        _burn(_msgSender(), shareAmount);
        
        // return tokens
        depositToken.safeTransfer(_receiver, userDeposit.amount);
        emit Withdrawn(_depositId, _receiver, _msgSender(), userDeposit.amount);
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