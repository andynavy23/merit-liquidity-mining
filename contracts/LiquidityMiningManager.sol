// SPDX-License-Identifier: MIT
pragma solidity 0.8.7; // 指定solidity版本其他版本會導致編譯錯誤
// 版本特點block.basefee可以查看目前區塊的基本費用

// npm i @openzeppelin/contracts
// IERC20(interface): Interface of the ERC20 standard as defined in the EIP.
// SafeERC20(library): Wrappers around ERC20 operations that throw on failure (when the token contract returns false).
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// IBasePool(interface)
// TokenSaver(contract)
import "./interfaces/IBasePool.sol";
import "./base/TokenSaver.sol";

// TimeLockPool繼承自BasePool抽象合約, 以及ITimeLockPool接口
contract LiquidityMiningManager is TokenSaver {
    // SafeERC20是以更安全的方式實現Transfer/Approve，當低級調用失敗時發出錯誤訊息並將transaction revert
    // 將名為SafeERC20的library裡面撰寫的函式使用在IERC20型態的變數上，將IERC20型態的變數作為函式第一個參數傳入
    using SafeERC20 for IERC20;

    // 宣告 公共 bytes32型態 名為GOV_ROLE的不可變量 治理角色
    // 將GOV_ROLE字串使用keccak256 hash function 加密
    bytes32 public constant GOV_ROLE = keccak256("GOV_ROLE");
    // 宣告 公共 bytes32型態 名為REWARD_DISTRIBUTOR_ROLE的不可變量 分發獎勵角色
    // 將REWARD_DISTRIBUTOR_ROLE字串使用keccak256 hash function 加密
    bytes32 public constant REWARD_DISTRIBUTOR_ROLE = keccak256("REWARD_DISTRIBUTOR_ROLE");
    // 宣告 公共 uint256型態 名為MAX_POOL_COUNT的不可變量
    // MAX_POOL_COUNT 最大質押池數
    uint256 public MAX_POOL_COUNT = 10;

    // 宣告 公共 IERC20型態 名為reward的不可變量 獎勵代幣
    IERC20 immutable public reward;
    // 宣告 公共 address型態 名為rewardSource的不可變量 獎勵來源地址
    address immutable public rewardSource;
    // 宣告 公共 uint256型態 名為rewardPerSecond的變量 每秒分發的獎勵數量
    uint256 public rewardPerSecond; //total reward amount per second
    // 宣告 公共 uint256型態 名為lastDistribution的變量 最後分發時間
    uint256 public lastDistribution; //when rewards were last pushed
    // 宣告 公共 uint256型態 名為totalWeight的變量 總共質押池權重
    uint256 public totalWeight;

    // 宣告 公共 mapping型態 名為poolAdded的動態大小的字典
    // key為 address型態
    // value為 bool型態 
    // 每個質押池地址的是否已經加入管理記錄
    mapping(address => bool) public poolAdded;
    // 宣告 公共 Pool型態 名為pools的陣列
    Pool[] public pools;

    // 枚舉名為Pool的資料結構
    // 包含IBasePool型態的poolContract變數 質押池合約
    // 包含uint256型態的weight變數 質押池權重
    struct Pool {
        IBasePool poolContract;
        uint256 weight;
    }

    // 函式修改器 只有擁有GOV_ROLE角色的錢包地址可以呼叫函式
    modifier onlyGov {
        require(hasRole(GOV_ROLE, _msgSender()), "LiquidityMiningManager.onlyGov: permission denied");
        _;
    }

    // 函式修改器 只有擁有REWARD_DISTRIBUTOR_ROLE角色的錢包地址可以呼叫函式
    modifier onlyRewardDistributor {
        require(hasRole(REWARD_DISTRIBUTOR_ROLE, _msgSender()), "LiquidityMiningManager.onlyRewardDistributor: permission denied");
        _;
    }

    // 宣告 名為PoolAdded事件 顯示在日誌上的參數為
    // address型態 pool參數內容 寫在topics裡
    // uint256型態 weight參數內容 寫在data裡
    event PoolAdded(address indexed pool, uint256 weight);
    // 宣告 名為PoolRemoved事件 顯示在日誌上的參數為
    // uint256型態 poolId參數內容 寫在topics裡
    // address型態 pool參數內容 寫在topics裡
    event PoolRemoved(uint256 indexed poolId, address indexed pool);
    // 宣告 名為WeightAdjusted事件 顯示在日誌上的參數為
    // uint256型態 poolId參數內容 寫在topics裡
    // address型態 pool參數內容 寫在topics裡
    // uint256型態 newWeight參數內容 寫在data裡
    event WeightAdjusted(uint256 indexed poolId, address indexed pool, uint256 newWeight);
    // 宣告 名為RewardsPerSecondSet事件 顯示在日誌上的參數為
    // uint256型態 rewardsPerSecond參數內容 寫在data裡
    event RewardsPerSecondSet(uint256 rewardsPerSecond);
    // 宣告 名為RewardsDistributed事件 顯示在日誌上的參數為
    // address型態 _from參數內容 寫在data裡
    // uint256型態 _amount參數內容 寫在topics裡
    event RewardsDistributed(address _from, uint256 indexed _amount);

    // 構造函式, 創建合約時首先執行的函式
    constructor(address _reward, address _rewardSource) {
        // 檢查_reward參數的地址不能為0x0000000000000000000000000000000000000000, 否則發出錯誤訊息
        require(_reward != address(0), "LiquidityMiningManager.constructor: reward token must be set");
        // 檢查_rewardSource參數的地址不能為0x0000000000000000000000000000000000000000, 否則發出錯誤訊息
        require(_rewardSource != address(0), "LiquidityMiningManager.constructor: rewardSource token must be set");
        // 透過構造函式中填入的address型態參數_reward置IERC20型態的變數, 設定給公共 IERC20型態 名為reward的不可變量
        reward = IERC20(_reward);
        // 透過構造函式中填入的address型態參數_rewardSource, 設定給公共 address型態 名為rewardSource的不可變量
        rewardSource = _rewardSource;
    }

    /**
    * 添加質押池函式 外部函式(不對內呼叫) 只有擁有GOV_ROLE角色的錢包地址可以呼叫函式
    * @param _poolContract address型態 質押池地址
    * @param _weight uint256型態 鑄造代幣數量
    */
    function addPool(address _poolContract, uint256 _weight) external onlyGov {
        // 添加質押池前先執行分發獎勵函式
        distributeRewards();
        // 檢查_poolContract參數的地址不能為0x0000000000000000000000000000000000000000, 否則發出錯誤訊息
        require(_poolContract != address(0), "LiquidityMiningManager.addPool: pool contract must be set");
        // 檢查不能重複添加相同質押池, 否則發出錯誤訊息
        require(!poolAdded[_poolContract], "LiquidityMiningManager.addPool: Pool already added");
        // 檢查目前質押池數量不能大於等於MAX_POOL_COUNT(最大質押池數), 否則發出錯誤訊息
        require(pools.length < MAX_POOL_COUNT, "LiquidityMiningManager.addPool: Max amount of pools reached");
        // 將此次質押池地址與權重記錄下來
        // add pool
        pools.push(Pool({
            poolContract: IBasePool(_poolContract),
            weight: _weight
        }));
        // 將此次質押池記錄已添加
        poolAdded[_poolContract] = true;
        
        // 將此次質押池權重加在總質押池權重變量上
        // increase totalWeight
        totalWeight += _weight;

        // 將目前合約的獎勵代幣的轉移權限批准最大數量給此次添加的質押池
        // Q: 這邊批准後續沒有再批准的動作是否會造成數量不夠?
        // Approve max token amount
        reward.safeApprove(_poolContract, type(uint256).max);

        // 記錄PoolAdded事件
        emit PoolAdded(_poolContract, _weight);
    }

    /**
    * 移除質押池函式 外部函式(不對內呼叫) 只有擁有GOV_ROLE角色的錢包地址可以呼叫函式
    * @param _poolId uint256型態 質押池ID
    */
    function removePool(uint256 _poolId) external onlyGov {
        // 檢查_poolId參數不能大於等於總質押池數量, 否則發出錯誤訊息
        require(_poolId < pools.length, "LiquidityMiningManager.removePool: Pool does not exist");
        // 移除質押池前先執行分發獎勵函式
        distributeRewards();
        // poolAddress(質押池地址)
        address poolAddress = address(pools[_poolId].poolContract);

        // 將質押池權重在總質押池權重變量上扣掉
        // decrease totalWeight
        totalWeight -= pools[_poolId].weight;
        
        // 將最後一筆質押池記錄取代至_poolId(質押池ID)位置
        // remove pool
        pools[_poolId] = pools[pools.length - 1];
        // 丟棄最後一筆質押池記錄
        pools.pop();
        // 將此次質押池記錄未添加
        poolAdded[poolAddress] = false;
        // Q: 移除質押池後沒有修改批准獎勵轉移權限是否會造成漏洞產生?

        // 記錄PoolRemoved事件
        emit PoolRemoved(_poolId, poolAddress);
    }

    /**
    * 更新質押池權重函式 外部函式(不對內呼叫) 只有擁有GOV_ROLE角色的錢包地址可以呼叫函式
    * @param _poolId uint256型態 質押池ID
    * @param _newWeight uint256型態 新權重
    */
    function adjustWeight(uint256 _poolId, uint256 _newWeight) external onlyGov {
        // 檢查_poolId參數不能大於等於總質押池數量, 否則發出錯誤訊息
        require(_poolId < pools.length, "LiquidityMiningManager.adjustWeight: Pool does not exist");
        // 更新質押池權重前先執行分發獎勵函式
        distributeRewards();
        // 取得_poolId(質押池ID)對應的質押池狀態
        Pool storage pool = pools[_poolId];

        // 將舊的質押池權重在總質押池權重變量上扣掉
        totalWeight -= pool.weight;
        // 將新的質押池權重加在總質押池權重變量上
        totalWeight += _newWeight;

        // 將新的質押池權重取代舊的質押池權重
        pool.weight = _newWeight;

        // 記錄WeightAdjusted事件
        emit WeightAdjusted(_poolId, address(pool.poolContract), _newWeight);
    }

    /**
    * 設定每秒分發獎勵數量函式 外部函式(不對內呼叫) 只有擁有GOV_ROLE角色的錢包地址可以呼叫函式
    * @param _rewardPerSecond uint256型態 每秒分發獎勵數量
    */
    function setRewardPerSecond(uint256 _rewardPerSecond) external onlyGov {
        // 設定每秒分發獎勵數量前先執行分發獎勵函式
        distributeRewards();
        // 將新的每秒分發獎勵數量取代舊的每秒分發獎勵數量
        rewardPerSecond = _rewardPerSecond;

        // 記錄RewardsPerSecondSet事件
        emit RewardsPerSecondSet(_rewardPerSecond);
    }

    /**
    * 分發獎勵數量函式 公共函式 只有擁有REWARD_DISTRIBUTOR_ROLE角色的錢包地址可以呼叫函式
    */
    // Example => https://etherscan.io/tx/0x037d1c82d0cc945df6a65a9639a04a6bfc4b20a8ff39ed68defd0f0235494b5a
    function distributeRewards() public onlyRewardDistributor {
        // timePassed(經過多少時間)
        // 經過多少時間 = 當前區塊時間 - 最後分發獎勵時間
        uint256 timePassed = block.timestamp - lastDistribution;
        // totalRewardAmount(總共需要分發的獎勵)
        // 總共需要分發的獎勵 = 每秒分發的獎勵數量 * 經過多少時間
        uint256 totalRewardAmount = rewardPerSecond * timePassed;

        // 更新最後分發獎勵時間
        lastDistribution = block.timestamp;

        // 判斷總質押池數量為0就結束函式
        // return if pool length == 0
        if(pools.length == 0) {
            return;
        }

        // 判斷總共需要分發的獎勵為0就結束函式
        // return if accrued rewards == 0
        if(totalRewardAmount == 0) {
            return;
        }

        // 獎勵代幣執行safeTransferFrom(安全轉移函式)
        // 將獎勵代幣從獎勵分發來源轉移至目前合約
        reward.safeTransferFrom(rewardSource, address(this), totalRewardAmount);

        // 迭代每個質押池
        for(uint256 i = 0; i < pools.length; i ++) {
            // 取得i(質押池位置)對應的質押池資訊
            Pool memory pool = pools[i];
            // poolRewardAmount(質押池獎勵數量)
            // 總共需要分發的獎勵 = 總共需要分發的獎勵 * 質押池權重 / 總共質押池權重
            uint256 poolRewardAmount = totalRewardAmount * pool.weight / totalWeight;
            // 執行質押池的distributeRewards函示
            // 質押池distributeRewards函式執行時發生錯誤也不會讓整個transaction失敗
            // encodeWithSelector允許在不知道其確切返回值類型的情況下調用函數
            // Ignore tx failing to prevent a single pool from halting reward distribution
            address(pool.poolContract).call(abi.encodeWithSelector(pool.poolContract.distributeRewards.selector, poolRewardAmount));
        }

        // leftOverReward(目前合約的獎勵代幣餘額)
        uint256 leftOverReward = reward.balanceOf(address(this));

        // 判斷目前合約的獎勵代幣餘額大於1就執行 獎勵代幣的safeTransferFrom函式
        // 將分發完後剩餘的獎勵代幣轉移給獎勵代幣來源
        // send back excess but ignore dust
        if(leftOverReward > 1) {
            reward.safeTransfer(rewardSource, leftOverReward);
        }

        // 記錄RewardsDistributed事件
        emit RewardsDistributed(_msgSender(), totalRewardAmount);
    }

    /**
    * 取得所有質押池資訊函式 只讀 外部函式(不對內呼叫)
    */
    function getPools() external view returns(Pool[] memory result) {
        return pools;
    }
}