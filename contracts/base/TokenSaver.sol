// SPDX-License-Identifier: MIT
pragma solidity 0.8.7; // 指定solidity版本其他版本會導致編譯錯誤
// 版本特點block.basefee可以查看目前區塊的基本費用

// npm i @openzeppelin/contracts
// IERC20(interface): Interface of the ERC20 standard as defined in the EIP.
// SafeERC20(library): Wrappers around ERC20 operations that throw on failure (when the token contract returns false).
// AccessControlEnumerable(abstract contract): allows enumerating the members of each role.
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

// TokenSaver繼承自AccessControlEnumerable抽象合約
// 它允許白名單地址從繼承自它的合約中轉出任何代幣，以防出現緊急情況或代幣放錯位置。
contract TokenSaver is AccessControlEnumerable {
    // SafeERC20是以更安全的方式實現Transfer/Approve，當低級調用失敗時發出錯誤訊息並將transaction revert
    // 將名為SafeERC20的library裡面撰寫的函式使用在IERC20型態的變數上，將IERC20型態的變數作為函式第一個參數傳入
    using SafeERC20 for IERC20;

    // 宣告 公共 bytes32型態 名為TOKEN_SAVER_ROLE的不可變量 代幣保護角色
    // 將TOKEN_SAVER_ROLE字串使用keccak256 hash function 加密
    bytes32 public constant TOKEN_SAVER_ROLE = keccak256("TOKEN_SAVER_ROLE");

    // 宣告 名為RewardsClaimed事件 顯示在日誌上的參數為
    // address型態 by參數內容 寫在topics裡
    // address型態 receiver參數內容 寫在topics裡
    // address型態 token參數內容 寫在topics裡
    // uint256型態 amount參數內容 寫在data裡
    // topics 有索引可以分開decode
    // data 全部hax會合在一起, 需要另外處理分開不同數值
    event TokenSaved(address indexed by, address indexed receiver, address indexed token, uint256 amount);

    // 函式修改器 只有擁有TOKEN_SAVER_ROLE角色的錢包地址可以呼叫函式
    modifier onlyTokenSaver() {
        // AccessControl.hasRole
        // 檢查呼叫函式者的地址是否擁有TOKEN_SAVER_ROLE的角色, 否則發出錯誤訊息
        require(hasRole(TOKEN_SAVER_ROLE, _msgSender()), "TokenSaver.onlyTokenSaver: permission denied");
        // _ = 被修改的函式主體
        _;
    }

    // 構造函式, 創建合約時首先執行的函式
    constructor() {
        // DEFAULT_ADMIN_ROLE繼承自AccessControl = 0x00
        // _setupRole設定錢包地址對應的角色的函式
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /**
    * 白名單轉移代幣函式 外部函式(不對內呼叫)
    * @param _token address型態 被轉移的代幣
    * @param _receiver address型態 接收代幣者
    * @param _amount uint256型態 轉移代幣數量
    */
    function saveToken(address _token, address _receiver, uint256 _amount) external onlyTokenSaver {
        // 轉移IERC20型態的_token進行安全轉移, 接收者為_receiver, 轉移數量為_amount
        IERC20(_token).safeTransfer(_receiver, _amount);
        // 記錄TokenSaved事件
        emit TokenSaved(_msgSender(), _receiver, _token, _amount);
    }

}