// SPDX-License-Identifier: MIT
pragma solidity 0.8.7; // 指定solidity版本其他版本會導致編譯錯誤
// 版本特點block.basefee可以查看目前區塊的基本費用

// IAbstractRewards(interface)
import "../interfaces/IAbstractRewards.sol";
// npm i @openzeppelin/contracts
// SafeCast(library): Wrappers over Solidity's uintXX/intXX casting operators with added overflow checks.
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @dev Based on: https://github.com/indexed-finance/dividends/blob/master/contracts/base/AbstractDividends.sol
 * Renamed dividends to rewards.
 * @dev (OLD) Many functions in this contract were taken from this repository:
 * https://github.com/atpar/funds-distribution-token/blob/master/contracts/FundsDistributionToken.sol
 * which is an example implementation of ERC 2222, the draft for which can be found at
 * https://github.com/atpar/funds-distribution-token/blob/master/EIP-DRAFT.md
 *
 * This contract has been substantially modified from the original and does not comply with ERC 2222.
 * Many functions were renamed as "rewards" rather than "funds" and the core functionality was separated
 * into this abstract contract which can be inherited by anything tracking ownership of reward shares.
 */

// 抽象合約, 僅定義函式, 至少有一個定義的函式無法實現, 即為抽象合約
// 如果合約繼承抽象合約後, 並沒有實現所有未實現的函式, 那麼自己也會是一個抽象合約
// AbstractRewards繼承自IAbstractRewards接口
// 用於在任意數量的“股東”之間分配按比例獎勵，其中繼承合同定義了股東是什麼以及他們擁有多少股份。
abstract contract AbstractRewards is IAbstractRewards {
  // SafeCast是以更安全的方式實現uint/int進行向下/向上轉換，當溢出錯誤發生時發出錯誤訊息並將transaction revert
  // 將名為SafeCast的library裡面撰寫的函式使用在uint128型態的變數上，將uint128型態的變數作為函式第一個參數傳入
  using SafeCast for uint128;
  // 將名為SafeCast的library裡面撰寫的函式使用在uint256型態的變數上，將uint256型態的變數作為函式第一個參數傳入
  using SafeCast for uint256;
  // 將名為SafeCast的library裡面撰寫的函式使用在int256型態的變數上，將int256型態的變數作為函式第一個參數傳入
  using SafeCast for int256;

/* ========  Constants  ======== */
  // 宣告 公共 uint128型態 名為POINTS_MULTIPLIER的不可變量
  // POINTS_MULTIPLIER = 340282366920938463463374607431768211455
  uint128 public constant POINTS_MULTIPLIER = type(uint128).max;

/* ========  Internal Function References  ======== */
  // 取得 公共變量的內部函式(繼承合約也無法呼叫) 會在構造函式設置
  function(address) view returns (uint256) private immutable getSharesOf;
  // 取得 公共變量的內部函式(繼承合約也無法呼叫) 會在構造函式中設置
  function() view returns (uint256) private immutable getTotalShares;

/* ========  Storage  ======== */
  // 宣告 公共 uint256型態 名為pointsPerShare的變量
  // pointsPerShare = 0
  // 每LP能得到的point數量
  uint256 public pointsPerShare;
  // 宣告 公共 mapping型態 名為pointsCorrection的動態大小的字典
  // key為 address型態
  // value為 int256型態
  // 每個錢包地址的校正後point
  mapping(address => int256) public pointsCorrection;
  // 宣告 公共 mapping型態 名為withdrawnRewards的動態大小的字典
  // key為 address型態
  // value為 uint256型態
  // 每個錢包地址已提取的獎勵數量
  mapping(address => uint256) public withdrawnRewards;

  // 構造函式, 創建合約時首先執行的函式
  constructor(
    // Q:沒理解這邊用這樣的寫法好處?
    function(address) view returns (uint256) getSharesOf_,
    function() view returns (uint256) getTotalShares_
  ) {
    // 透過構造函式中填入的參數getSharesOf_, 設定給私有 名為getSharesOf的函式
    // getSharesOf => balanceOf 查看餘額函式
    getSharesOf = getSharesOf_;
    // 透過構造函式中填入的參數getTotalShares_, 設定給私有 名為getTotalShares的函式
    // getTotalShares => totalSupply 查看現在總供應量
    getTotalShares = getTotalShares_;
  }

/* ========  Public View Functions  ======== */
  /**
   * @dev Returns the total amount of rewards a given address is able to withdraw.
   * @param _account Address of a reward recipient
   * @return A uint256 representing the rewards `account` can withdraw
   */
  // 查看目前能提取多少獎勵的函式 繼承自IAbstractRewards 覆寫 公共 只讀
  function withdrawableRewardsOf(address _account) public view override returns (uint256) {
    // 賺取的獎勵數量 - 已提取的獎勵數量
    return cumulativeRewardsOf(_account) - withdrawnRewards[_account];
  }

  /**
   * @notice View the amount of rewards that an address has withdrawn.
   * @param _account The address of a token holder.
   * @return The amount of rewards that `account` has withdrawn.
   */
  // 查看目前已提取多少獎勵的函式 繼承自IAbstractRewards 覆寫 公共 只讀
  function withdrawnRewardsOf(address _account) public view override returns (uint256) {
    // 已提取的獎勵數量
    return withdrawnRewards[_account];
  }

  /**
   * @notice View the amount of rewards that an address has earned in total.
   * @dev accumulativeFundsOf(account) = withdrawableRewardsOf(account) + withdrawnRewardsOf(account)
   * = (pointsPerShare * balanceOf(account) + pointsCorrection[account]) / POINTS_MULTIPLIER
   * @param _account The address of a token holder.
   * @return The amount of rewards that `account` has earned in total.
   */
  // 查看目前已賺取多少獎勵的函式 繼承自IAbstractRewards 覆寫 公共 只讀
  function cumulativeRewardsOf(address _account) public view override returns (uint256) {
    // pointsPerShare = 每LP能得到的point數量
    // getSharesOf(_account) = _account擁有的pool point
    // pointsCorrection[_account] = _account擁有的校正後pool point
    // POINTS_MULTIPLIER = 340282366920938463463374607431768211455
    return ((pointsPerShare * getSharesOf(_account)).toInt256() + pointsCorrection[_account]).toUint256() / POINTS_MULTIPLIER;
  }

/* ========  Dividend Utility Functions  ======== */

  /** 
   * @notice Distributes rewards to token holders.
   * @dev It reverts if the total shares is 0.
   * It emits the `RewardsDistributed` event if the amount to distribute is greater than 0.
   * About undistributed rewards:
   *   In each distribution, there is a small amount which does not get distributed,
   *   which is `(amount * POINTS_MULTIPLIER) % totalShares()`.
   *   With a well-chosen `POINTS_MULTIPLIER`, the amount of funds that are not getting
   *   distributed in a distribution can be less than 1 (base unit).
   */
  // 分配獎勵的函式 內部(繼承合約依然可以使用)
  function _distributeRewards(uint256 _amount) internal {
    // shares 總供應量
    uint256 shares = getTotalShares();
    // 判斷總供應量要大於0, 否則發出錯誤訊息
    require(shares > 0, "AbstractRewards._distributeRewards: total share supply is zero");

    // 判斷_amount要大於0
    if (_amount > 0) {
      // 更新每LP能得到的point數量(pointsPerShare)這個變量的狀態
      // 更新後的pointsPerShare = 原本的pointsPerShare狀態值 + (要分配的獎勵數量 * POINTS_MULTIPLIER / 總供應量)
      pointsPerShare = pointsPerShare + (_amount * POINTS_MULTIPLIER / shares);
      // 記錄RewardsDistributed事件
      // Example => https://etherscan.io/tx/0x037d1c82d0cc945df6a65a9639a04a6bfc4b20a8ff39ed68defd0f0235494b5a
      emit RewardsDistributed(msg.sender, _amount);
    }
  }

  /**
   * @notice Prepares collection of owed rewards
   * @dev It emits a `RewardsWithdrawn` event if the amount of withdrawn rewards is
   * greater than 0.
   */
  // 提取獎勵前呼叫的函式 內部(繼承合約依然可以使用)
  function _prepareCollect(address _account) internal returns (uint256) {
    // _withdrawableDividend 可提取的獎勵數量
    uint256 _withdrawableDividend = withdrawableRewardsOf(_account);
    // 判斷_withdrawableDividend要大於0
    if (_withdrawableDividend > 0) {
      // 記錄已經提取的獎勵數量(累積)
      withdrawnRewards[_account] = withdrawnRewards[_account] + _withdrawableDividend;
      // 記錄RewardsWithdrawn事件
      // Example => https://etherscan.io/tx/0x68895e6c1bde9dbf20a1c1469b22218efbd1e5f1a3b577b12a1496bcf90566fc
      emit RewardsWithdrawn(_account, _withdrawableDividend);
    }
    return _withdrawableDividend;
  }

  // 轉移LP後呼叫的函式 內部(繼承合約依然可以使用)
  function _correctPointsForTransfer(address _from, address _to, uint256 _shares) internal {
    // _magCorrection 需要校正的point數量
    // 需要校正的point數量 = (每LP能得到的point數量 * LP數量)
    int256 _magCorrection = (pointsPerShare * _shares).toInt256();
    // pointsCorrection[_from] 被轉移LP者擁有的校正後point
    // 更新後的被轉移LP者擁有的校正後point = 原始的被轉移LP者擁有的校正後point + 需要校正的point數量
    pointsCorrection[_from] = pointsCorrection[_from] + _magCorrection;
    // pointsCorrection[_to] 接收LP者擁有的校正後point
    // 更新後的接收LP者擁有的校正後point = 原始的接收LP者擁有的校正後point - 需要校正的point數量
    pointsCorrection[_to] = pointsCorrection[_to] - _magCorrection;
  }

  /**
   * @dev Increases or decreases the points correction for `account` by
   * `shares*pointsPerShare`.
   */
  // 燃燒/鑄造LP後呼叫的函式 內部(繼承合約依然可以使用)
  function _correctPoints(address _account, int256 _shares) internal {
    // pointsCorrection[_account] 鑄造/燃燒LP者擁有的校正後point
    // 更新後的鑄造/燃燒LP者擁有的校正後point = 原始的鑄造/燃燒LP者擁有的校正後point + (LP數量 * 每LP能得到的point數量)
    pointsCorrection[_account] = pointsCorrection[_account] + (_shares * (int256(pointsPerShare)));
  }
}