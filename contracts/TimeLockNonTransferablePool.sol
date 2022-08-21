// SPDX-License-Identifier: MIT
pragma solidity 0.8.7; // 指定solidity版本其他版本會導致編譯錯誤
// 版本特點block.basefee可以查看目前區塊的基本費用

// TimeLockPool(contract)
import "./TimeLockPool.sol";

// TimeLockNonTransferablePool繼承自TimeLockPool合約
contract TimeLockNonTransferablePool is TimeLockPool {
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
    ) TimeLockPool(_name, _symbol, _depositToken, _rewardToken, _escrowPool, _escrowPortion, _escrowDuration, _maxBonus, _maxLockDuration) {

    }

    /**
    * 轉移代幣函式 繼承自BasePool 覆寫 內部函式
    * @param _from address型態 被轉移代幣者
    * @param _to address型態 接收代幣者
    * @param _amount uint256型態 轉移數量
    */
    // disable transfers
    function _transfer(address _from, address _to, uint256 _amount) internal override {
        // 直接還原交易
        revert("NON_TRANSFERABLE");
    }
}