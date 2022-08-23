// SPDX-License-Identifier: MIT
pragma solidity 0.8.7; // 指定solidity版本其他版本會導致編譯錯誤
// 版本特點block.basefee可以查看目前區塊的基本費用

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
// TimeLockPool添加外部函數來存入代幣並作為回報接收TimeLockPool份額。更長鎖定持續時間的獎勵是可配置的。
contract TimeLockPool is BasePool, ITimeLockPool {
    // Math是以更標準的方式實現數學運算
    // 將名為Math的library裡面撰寫的函式使用在uint256型態的變數上，將uint256型態的變數作為函式第一個參數傳入
    using Math for uint256;
    // SafeERC20是以更安全的方式實現Transfer/Approve，當低級調用失敗時發出錯誤訊息並將transaction revert
    // 將名為SafeERC20的library裡面撰寫的函式使用在IERC20型態的變數上，將IERC20型態的變數作為函式第一個參數傳入
    using SafeERC20 for IERC20;

    // 宣告 公共 uint256型態 名為maxBonus的不可變量
    // maxBonus 最大獎勵數量
    uint256 public immutable maxBonus;
    // 宣告 公共 uint256型態 名為maxLockDuration的不可變量
    // maxLockDuration 最長鎖倉期限
    uint256 public immutable maxLockDuration;
    // 宣告 公共 uint256型態 名為MIN_LOCK_DURATION的不可變量
    // MIN_LOCK_DURATION 最少鎖倉期限
    uint256 public constant MIN_LOCK_DURATION = 10 minutes;
    
    // 宣告 公共 mapping型態 名為depositsOf的動態大小的字典
    // key為 address型態
    // value為 Deposit陣列型態 
    // 每個錢包地址存入的代幣記錄
    mapping(address => Deposit[]) public depositsOf;

    // 枚舉名為Deposit的資料結構
    // 包含uint256型態的amount變數 質押數量
    // 包含uint64型態的start變數 質押開始時間
    // 包含uint64型態的end變數 鎖倉結束時間
    struct Deposit {
        uint256 amount;
        uint64 start;
        uint64 end;
    }
    // 構造函式, 創建合約時首先執行的函式
    // 繼承的父合約的構造函式需要填入參數時也需要在這邊填入
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
        // _maxLockDuration(最長鎖倉期限)變量狀態檢查不能小於十分鐘
        require(_maxLockDuration >= MIN_LOCK_DURATION, "TimeLockPool.constructor: max lock duration must be greater or equal to mininmum lock duration");
        // 透過構造函式中填入的uint256型態參數_maxBonus, 設定給公共 uint256型態 名為maxBonus的不可變量
        maxBonus = _maxBonus;
        // 透過構造函式中填入的uint256型態參數_maxLockDuration, 設定給公共 uint256型態 名為maxLockDuration的不可變量
        maxLockDuration = _maxLockDuration;
    }

    // 宣告 名為Deposited事件 顯示在日誌上的參數為
    // uint256型態 amount參數內容 寫在data裡
    // uint256型態 duration參數內容 寫在data裡
    // address型態 receiver參數內容 寫在topics裡
    // address型態 from參數內容 寫在topics裡
    // Example => https://etherscan.io/tx/0xc95e3ce67beeefd36b6c20f5d619e1552e7a11349823a9f6693245a9e0a6f345
    // topics 有索引可以分開decode
    // data 全部hax會合在一起, 需要另外處理分開不同數值
    event Deposited(uint256 amount, uint256 duration, address indexed receiver, address indexed from);
    // 宣告 名為Withdrawn事件 顯示在日誌上的參數為
    // uint256型態 depositId參數內容 寫在topics裡
    // address型態 receiver參數內容 寫在topics裡
    // address型態 from參數內容 寫在topics裡
    // uint256型態 amount參數內容 寫在data裡
    // Example => https://etherscan.io/tx/0xd4690796d6fe7aeebc809bc27a991f9ebda3b0b4ce2571be7ad79c097a9ab01c
    // topics 有索引可以分開decode
    // data 全部hax會合在一起, 需要另外處理分開不同數值
    event Withdrawn(uint256 indexed depositId, address indexed receiver, address indexed from, uint256 amount);

    /**
    * 質押代幣函式 繼承自ITimeLockPool 覆寫 外部函式(不對內呼叫)
    * @param _amount uint256型態 質押數量
    * @param _duration uint256型態 鎖倉時間
    * @param _receiver address型態 接收獎勵者
    */
    function deposit(uint256 _amount, uint256 _duration, address _receiver) external override {
        // _amount(質押數量)變量狀態檢查不能小於等於0
        require(_amount > 0, "TimeLockPool.deposit: cannot deposit 0");
        // duration(鎖倉期限)
        // 輸入參數的_duration(鎖倉時間)與maxLockDuration(最長鎖倉期限)做比較選擇較低者
        // Don't allow locking > maxLockDuration
        uint256 duration = _duration.min(maxLockDuration);
        // 輸入參數的duration(鎖倉時間)與MIN_LOCK_DURATION(最短鎖倉期限)做比較選擇較高者
        // Enforce min lockup duration to prevent flash loan or MEV transaction ordering
        duration = duration.max(MIN_LOCK_DURATION);

        // 質押代幣執行safeTransferFrom(安全轉移函式)
        // 將質押代幣從呼叫deposit函式者轉移至目前合約
        depositToken.safeTransferFrom(_msgSender(), address(this), _amount);

        // 將此次質押記錄到對應地址的陣列
        depositsOf[_receiver].push(Deposit({
            amount: _amount,
            start: uint64(block.timestamp),
            end: uint64(block.timestamp) + uint64(duration)
        }));

        // mintAmount(質押產生的代幣數量)
        uint256 mintAmount = _amount * getMultiplier(duration) / 1e18;

        // 執行鑄造代幣函式
        _mint(_receiver, mintAmount);
        // 記錄Deposited事件
        emit Deposited(_amount, duration, _receiver, _msgSender());
    }

    /**
    * 提取質押代幣函式 繼承自ITimeLockPool 覆寫 外部函式(不對內呼叫)
    * @param _depositId uint256型態 質押ID
    * @param _receiver address型態 接收質押代幣者
    */
    function withdraw(uint256 _depositId, address _receiver) external {
        // _depositId(質押ID)變量狀態檢查不能小於等於depositsOf(每個錢包地址存入的代幣記錄)長度
        require(_depositId < depositsOf[_msgSender()].length, "TimeLockPool.withdraw: Deposit does not exist");
        // 將_depositId(質押ID)對應的記錄取出存到userDeposit
        Deposit memory userDeposit = depositsOf[_msgSender()][_depositId];
        // block.timestamp(當前區塊時間)檢查不能小於鎖倉結束時間
        require(block.timestamp >= userDeposit.end, "TimeLockPool.withdraw: too soon");

        // shareAmount(燃燒代幣數量)
        // 燃燒代幣數量 = 質押代幣數量 * (鎖倉應得到權重乘數 / 基數)
        // No risk of wrapping around on casting to uint256 since deposit end always > deposit start and types are 64 bits
        uint256 shareAmount = userDeposit.amount * getMultiplier(uint256(userDeposit.end - userDeposit.start)) / 1e18;

        // 將最後一筆質押記錄取代至_depositId(質押ID)位置
        // remove Deposit
        depositsOf[_msgSender()][_depositId] = depositsOf[_msgSender()][depositsOf[_msgSender()].length - 1];
        // 丟棄最後一筆質押記錄
        depositsOf[_msgSender()].pop();

        // 執行燃燒代幣函式
        // burn pool shares
        _burn(_msgSender(), shareAmount);
        
        // 質押代幣執行safeTransferFrom(安全轉移函式)
        // 將質押代幣從目前合約轉移至_receiver
        // return tokens
        depositToken.safeTransfer(_receiver, userDeposit.amount);
        // 記錄Withdrawn事件
        emit Withdrawn(_depositId, _receiver, _msgSender(), userDeposit.amount);
    }

    /**
    * 查詢鎖倉區間應得到權重乘數函式 只讀 公共外部函式
    * @param _lockDuration uint256型態 鎖倉區間
    */
    function getMultiplier(uint256 _lockDuration) public view returns(uint256) {
        // 基數 + (最大獎勵數 * 鎖倉區間 / 最大鎖倉期限)
        return 1e18 + (maxBonus * _lockDuration / maxLockDuration);
    }

    /**
    * 查詢特定錢包地址總共質押代幣數量函式 只讀 公共外部函式
    * @param _account address型態 錢包地址
    */
    function getTotalDeposit(address _account) public view returns(uint256) {
        // total(總共質押代幣數量)
        uint256 total;
        // 迭代每筆質押記錄計算總共數量
        // Q: 是否在每次質押中就去記錄總共質押數量比較好?
        for(uint256 i = 0; i < depositsOf[_account].length; i++) {
            total += depositsOf[_account][i].amount;
        }

        return total;
    }

    /**
    * 查詢特定錢包地址全部質押記錄函式 只讀 公共外部函式
    * @param _account address型態 錢包地址
    */
    function getDepositsOf(address _account) public view returns(Deposit[] memory) {
        return depositsOf[_account];
    }

    /**
    * 查詢特定錢包地址質押次數函式 只讀 公共外部函式
    * @param _account address型態 錢包地址
    */
    function getDepositsOfLength(address _account) public view returns(uint256) {
        return depositsOf[_account].length;
    }
}