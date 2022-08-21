// SPDX-License-Identifier: MIT
pragma solidity 0.8.7; // 指定solidity版本其他版本會導致編譯錯誤
// 版本特點block.basefee可以查看目前區塊的基本費用

// Note: total share = total supply

// npm i @openzeppelin/contracts
// IERC20(interface): Interface of the ERC20 standard as defined in the EIP.
// SafeERC20(library): Wrappers around ERC20 operations that throw on failure (when the token contract returns false).
// ERC20Votes(abstract contract): Extension of ERC20 to support Compound-like voting and delegation.
// SafeCast(library): Wrappers over Solidity's uintXX/intXX casting operators with added overflow checks.
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

// IBasePool(interface)
// ITimeLockPool(interface)
import "../interfaces/IBasePool.sol";
import "../interfaces/ITimeLockPool.sol";

// AbstractRewards(abstract contract)
// TokenSaver(contract)
import "./AbstractRewards.sol";
import "./TokenSaver.sol";

// 抽象合約, 僅定義函式, 至少有一個定義的函式無法實現, 即為抽象合約
// 如果合約繼承抽象合約後, 並沒有實現所有未實現的函式, 那麼自己也會是一個抽象合約
// BasePool繼承自TokenSaver合約, 以及ERC20Votes, AbstractRewards等抽象合約與IBasePool接口
// BasePool是一個通用的 ERC20 兼容合約，並添加了用於分配和領取獎勵的外部函數。
// 此外，與內部 _transfer、burn 和 mint 掛鉤，以便在帳戶餘額發生變化時正確跟踪獎勵。
abstract contract BasePool is ERC20Votes, AbstractRewards, IBasePool, TokenSaver {
    // SafeERC20是以更安全的方式實現Transfer/Approve，當低級調用失敗時發出錯誤訊息並將transaction revert
    // 將名為SafeERC20的library裡面撰寫的函式使用在IERC20型態的變數上，將IERC20型態的變數作為函式第一個參數傳入
    using SafeERC20 for IERC20;
    // SafeCast是以更安全的方式實現uint256/int256向下轉換，當溢出錯誤發生時發出錯誤訊息並將transaction revert
    // 將名為SafeCast的library裡面撰寫的函式使用在uint256型態的變數上，將uint256型態的變數作為函式第一個參數傳入
    using SafeCast for uint256;
    // 將名為SafeCast的library裡面撰寫的函式使用在int256型態的變數上，將int256型態的變數作為函式第一個參數傳入
    using SafeCast for int256;

    // immutable與constant都是不可變量的關鍵字, 差別在於constant需要在編譯前設置, immutable可於構造函式中設置
    // 宣告 公共 IERC20型態 名為depositToken的不可變量 質押代幣
    IERC20 public immutable depositToken;
    // 宣告 公共 IERC20型態 名為rewardToken的不可變量 獎勵代幣
    IERC20 public immutable rewardToken;
    // 宣告 公共 ITimeLockPool型態 名為escrowPool的不可變量 託管池
    ITimeLockPool public immutable escrowPool;
    // 宣告 公共 uint256型態 名為escrowPortion的不可變量 託管數量(1e18即為全部託管)
    uint256 public immutable escrowPortion; // how much is escrowed 1e18 == 100%
    // 宣告 公共 uint256型態 名為escrowDuration的不可變量 託管期限
    uint256 public immutable escrowDuration; // escrow duration in seconds

    // 宣告 名為RewardsClaimed事件 顯示在日誌上的參數為
    // address型態 _from參數內容 寫在topics裡
    // address型態 _receiver參數內容 寫在topics裡
    // uint256型態 _escrowedAmount參數內容 寫在data裡
    // uint256型態 _nonEscrowedAmount參數內容 寫在data裡
    // Example => https://etherscan.io/tx/0x68895e6c1bde9dbf20a1c1469b22218efbd1e5f1a3b577b12a1496bcf90566fc
    // topics 有索引可以分開decode
    // data 全部hax會合在一起, 需要另外處理分開不同數值
    event RewardsClaimed(address indexed _from, address indexed _receiver, uint256 _escrowedAmount, uint256 _nonEscrowedAmount);

    // 構造函式, 創建合約時首先執行的函式
    // 繼承的父合約的構造函式需要填入參數時也需要在這邊填入
    constructor(
        string memory _name,
        string memory _symbol,
        address _depositToken,
        address _rewardToken,
        address _escrowPool,
        uint256 _escrowPortion,
        uint256 _escrowDuration
    ) ERC20Permit(_name) ERC20(_name, _symbol) AbstractRewards(balanceOf, totalSupply) {
        // require 用來檢查較不嚴重的錯誤, 可以退回使用到的 gas
        // assert 用來檢查較嚴重的錯誤, 會拿走所有 gas fee
        // _escrowPortion(託管部分)變量狀態檢查需要小於等於1e18(1 * 10**18)
        require(_escrowPortion <= 1e18, "BasePool.constructor: Cannot escrow more than 100%");
        // _depositToken(存入的代幣地址)變量狀態檢查不能等於0x0000000000000000000000000000000000000000
        require(_depositToken != address(0), "BasePool.constructor: Deposit token must be set");
        // 透過構造函式中填入的address型態參數_depositToken設置IERC20型態的變數, 設定給公共 IERC20型態 名為depositToken的不可變量
        depositToken = IERC20(_depositToken);
        // 透過構造函式中填入的address型態參數_rewardToken設置IERC20型態的變數, 設定給公共 IERC20型態 名為rewardToken的不可變量
        rewardToken = IERC20(_rewardToken);
        // 透過構造函式中填入的address型態參數_escrowPool設置ITimeLockPool型態的變數, 設定給公共 ITimeLockPool型態 名為escrowPool的不可變量
        escrowPool = ITimeLockPool(_escrowPool);
        // 透過構造函式中填入的uint256型態參數_escrowPortion, 設定給公共 uint256型態 名為escrowPortion的不可變量
        escrowPortion = _escrowPortion;
        // 透過構造函式中填入的uint256型態參數_escrowDuration, 設定給公共 uint256型態 名為escrowDuration的不可變量
        escrowDuration = _escrowDuration;

        // 判斷_rewardToken與_escrowPool地址不能為0x0000000000000000000000000000000000000000
        if(_rewardToken != address(0) && _escrowPool != address(0)) {
            // 呼叫IERC20型態且地址為_rewardToken的safeApprove函示
            // type(uint256).max = 115792089237316195423570985008687907853269984665640564039457584007913129639935
            // BasePool批准_escrowPool轉移特定數量的_rewardToken的權利
            IERC20(_rewardToken).safeApprove(_escrowPool, type(uint256).max);
        }
    }

    /**
    * 鑄造代幣函式 繼承自ERC20Votes 覆寫 隱式 內部函式
    * @param _account address型態 被給予鑄造代幣者(先mint再transfer)
    * @param _amount uint256型態 鑄造代幣數量
    */
    function _mint(address _account, uint256 _amount) internal virtual override {
		super._mint(_account, _amount);
        // 鑄造後執行繼承自AbstractRewards的_correctPoints函式
        // 對_account的correctpoint進行校正
        // Q:correctpoint作用?(進行獎勵分配所需要的計算子)
        _correctPoints(_account, -(_amount.toInt256()));
	}
	
    /**
    * 燃燒代幣函式 繼承自ERC20Votes 覆寫 隱式 內部函式
    * @param _account address型態 被燃燒代幣者
    * @param _amount uint256型態 燃燒代幣數量
    */
	function _burn(address _account, uint256 _amount) internal virtual override {
		super._burn(_account, _amount);
        // 燃燒後執行繼承自AbstractRewards的_correctPoints函式
        // 對_account的correctpoint進行校正
        // Q:correctpoint作用?(進行獎勵分配所需要的計算子)
        _correctPoints(_account, _amount.toInt256());
	}

    /**
    * 轉移代幣函式 繼承自ERC20Votes 覆寫 隱式 內部函式
    * @param _from address型態 被轉移代幣者
    * @param _to address型態 接收代幣者
    * @param _value uint256型態 轉移代幣數量
    */
    function _transfer(address _from, address _to, uint256 _value) internal virtual override {
		super._transfer(_from, _to, _value);
        // 轉移後執行繼承自AbstractRewards的_correctPointsForTransfer函式
        // 對被轉移代幣者與接收代幣者的correctpoint進行校正
        // Q:correctpoint作用?(進行獎勵分配所需要的計算子)
        _correctPointsForTransfer(_from, _to, _value);
	}

    /**
    * 分發獎勵代幣函式 繼承自IBasePool 覆寫 外部函式(不對內呼叫)
    * @param _amount uint256型態 分發數量
    */
    function distributeRewards(uint256 _amount) external override {
        // 將要分發的數量轉移至Pool
        rewardToken.safeTransferFrom(_msgSender(), address(this), _amount);
        // 執行繼承自AbstractRewards的_distributeRewards函式
        // 對pointsPerShare進行調整(會影響獎勵數量)
        _distributeRewards(_amount);
    }

    /**
    * 領取獎勵代幣函式 外部函式(不對內呼叫)
    * @param _receiver address型態 接收獎勵者
    */
    function claimRewards(address _receiver) external {
        // 執行繼承自AbstractRewards的_prepareCollect函式
        // rewardAmount(提取的獎勵數量)
        uint256 rewardAmount = _prepareCollect(_msgSender());
        // escrowedRewardAmount(託管獎勵數量) = 提取的獎勵數量 * 託管數量 / 1e18(1 * 10**18)
        uint256 escrowedRewardAmount = rewardAmount * escrowPortion / 1e18;
        // nonEscrowedRewardAmount(未託管獎勵數量) = 提取的獎勵數量 - 託管獎勵數量
        uint256 nonEscrowedRewardAmount = rewardAmount - escrowedRewardAmount;

        // 判斷託管獎勵數量不為0同時託管池地址不為空地址的話
        if(escrowedRewardAmount != 0 && address(escrowPool) != address(0)) {
            // 將託管獎勵數量存入託管池
            escrowPool.deposit(escrowedRewardAmount, escrowDuration, _receiver);
        }

        // ignore dust
        // 判斷未託管獎勵數量大於1的話
        if(nonEscrowedRewardAmount > 1) {
            // 按照未託管獎勵數量將獎勵代幣轉移到接收者(_receiver)
            rewardToken.safeTransfer(_receiver, nonEscrowedRewardAmount);
        }

        // 記錄RewardsClaimed事件
        emit RewardsClaimed(_msgSender(), _receiver, escrowedRewardAmount, nonEscrowedRewardAmount);
    }

}