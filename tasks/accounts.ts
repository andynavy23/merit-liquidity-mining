import { Signer } from "@ethersproject/abstract-signer";
import { task } from "hardhat/config";

// 任務名稱 accounts 列出設定環境中所有錢包地址
task("accounts", "Prints the list of accounts", async (_taskArgs, hre) => {
  const accounts: Signer[] = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(await account.getAddress());
  }
});
