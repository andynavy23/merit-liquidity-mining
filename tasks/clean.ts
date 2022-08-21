import fsExtra from "fs-extra";
import { TASK_CLEAN } from "hardhat/builtin-tasks/task-names";
import { task } from "hardhat/config";

// 任務名稱 clean 複寫文件
task(TASK_CLEAN, "Overrides the standard clean task", async function (_taskArgs, _hre, runSuper) {
  await fsExtra.remove("./coverage");
  await fsExtra.remove("./coverage.json");
  // 複寫任務運行
  await runSuper();
});
