import { EthereumProvider } from "hardhat/types";

class TimeTraveler {
  private snapshotID: any;
  private ethereum: EthereumProvider;

  constructor(ethereum: EthereumProvider) {
    this.ethereum = ethereum;
  }

  // 快照當前區塊所有狀態
  public async snapshot() {
    const snapshot = await this.ethereum.send("evm_snapshot", []);
    await this.mine_blocks(1);
    this.snapshotID = snapshot;
    return;
  }

  // 返回指定區塊並且快照所有狀態
  public async revertSnapshot() {
    await this.ethereum.send("evm_revert", [this.snapshotID]);
    await this.mine_blocks(1);
    await this.snapshot();
    return;
  }

  // 依照輸入參數挖掘區塊
  public async mine_blocks(amount: number) {
    for (let i = 0; i < amount; i++) {
      await this.ethereum.send("evm_mine", []);
    }
  }

  // 區塊時間依照輸入參數往後調整(每個區塊挖掘時間不一定一樣所以與挖掘區塊不一樣)
  public async increaseTime(amount: number) {
    await this.ethereum.send("evm_increaseTime", [amount]);
    await this.mine_blocks(1);
  }

  // 指定區塊時間調整
  public async setNextBlockTimestamp(timestamp: number) {
    await this.ethereum.send("evm_setNextBlockTimestamp", [timestamp]);
    await this.mine_blocks(1);
  }
}

export default TimeTraveler;