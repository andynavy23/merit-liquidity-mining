import { task } from "hardhat/config";

import { LiquidityMiningManager, TimeLockNonTransferablePool, View } from "../../typechain";
import sleep from "../../utils/sleep";
import { constants, utils } from "ethers";
import { captureRejectionSymbol } from "events";

const MC = "0x949d48eca67b17269629c7194f4b727d4ef9e5d6";
const LP = "0xcCb63225a7B19dcF66717e4d40C9A72B39331d61";
const multisig = "0x7e9e4c0876b2102f33a1d82117cc73b7fddd0032";
const ONE_YEAR = 60 * 60 * 24 * 365;

// 任務名稱 deploy-liquidity-mining 將所有合約部屬
task("deploy-liquidity-mining")
    .addFlag("verify")
    .setAction(async(taskArgs, { run, ethers }) => {
    const signers = await ethers.getSigners();
    const liquidityMiningManager:LiquidityMiningManager = await run("deploy-liquidity-mining-manager", {
        rewardToken: MC,
        rewardSource: multisig, //multi sig is where the rewards will be stored. 
        verify: taskArgs.verify
    });

    // await liquidityMiningManager.deployed();

    const escrowPool:TimeLockNonTransferablePool = await run("deploy-time-lock-non-transferable-pool", {
        name: "Escrowed Merit Circle",
        symbol: "EMC",
        depositToken: MC,
        rewardToken: MC, //leaves possibility for xSushi like payouts on staked MC
        escrowPool: constants.AddressZero,
        escrowPortion: "0", //rewards from pool itself are not locked
        escrowDuration: "0", // no rewards escrowed so 0 escrow duration
        maxBonus: "0", // no bonus needed for longer locking durations
        maxLockDuration: (ONE_YEAR * 10).toString(), // Can be used to lock up to 10 years
        verify: taskArgs.verify
    });

    // await escrowPool.deployed();

    const mcPool:TimeLockNonTransferablePool = await run("deploy-time-lock-non-transferable-pool", {
        name: "Staked Merit Circle",
        symbol: "SMC",
        depositToken: MC, // users stake MC tokens
        rewardToken: MC, // rewards is MC token
        escrowPool: escrowPool.address, // Rewards are locked in the escrow pool
        escrowPortion: "1", // 100% is locked
        escrowDuration: ONE_YEAR.toString(), // locked for 1 year
        maxBonus: "1", // Bonus for longer locking is 1. When locking for longest duration you'll receive 2x vs no lock limit
        maxLockDuration: ONE_YEAR.toString(), // Users can lock up to 1 year
        verify: taskArgs.verify
    });

    // await mcPool.deployed();

    const mcLPPool:TimeLockNonTransferablePool = await run("deploy-time-lock-non-transferable-pool", {
        name: "Staked Merit Circle Uniswap LP",
        symbol: "SMCUNILP",
        depositToken: LP, // users stake LP tokens
        rewardToken: MC, // rewards is MC token
        escrowPool: escrowPool.address, // Rewards are locked in the escrow pool
        escrowPortion: "1", // 100% is locked
        escrowDuration: ONE_YEAR.toString(), // locked for 1 year
        maxBonus: "1", // Bonus for longer locking is 1. When locking for longest duration you'll receive 2x vs no lock limit
        maxLockDuration: ONE_YEAR.toString(), // Users can lock up to 1 year
        verify: taskArgs.verify
    });

    // await mcLPPool.deployed();

    const view:View = await run("deploy-view", {
        liquidityMiningManager: liquidityMiningManager.address,
        escrowPool: escrowPool.address,
        verify: taskArgs.verify
    });


    // assign gov role to deployer
    const GOV_ROLE = await liquidityMiningManager.GOV_ROLE();
    const REWARD_DISTRIBUTOR_ROLE = await liquidityMiningManager.REWARD_DISTRIBUTOR_ROLE();
    const DEFAULT_ADMIN_ROLE = await liquidityMiningManager.DEFAULT_ADMIN_ROLE();
    (await (await liquidityMiningManager.grantRole(GOV_ROLE, signers[0].address)).wait(3));
    (await (await liquidityMiningManager.grantRole(REWARD_DISTRIBUTOR_ROLE, signers[0].address)).wait(3));

    // Add pools
    console.log("Adding MC Pool");
    await (await liquidityMiningManager.addPool(mcPool.address, utils.parseEther("0.2"))).wait(3);
    console.log("Adding MC LP Pool");
    await (await liquidityMiningManager.addPool(mcLPPool.address, utils.parseEther("0.8"))).wait(3);

    // Assign GOV, DISTRIBUTOR and DEFAULT_ADMIN roles to multisig
    console.log("setting lmm roles");
    // renounce gov role from deployer
    console.log("renouncing gov role");
    await (await liquidityMiningManager.renounceRole(GOV_ROLE, signers[0].address)).wait(3);
    console.log("renouncing distributor role");
    await (await liquidityMiningManager.renounceRole(REWARD_DISTRIBUTOR_ROLE, signers[0].address)).wait(3);
    console.log("Assigning GOV_ROLE");
    await (await liquidityMiningManager.grantRole(GOV_ROLE, multisig)).wait(3);
    console.log("Assigning REWARD_DISTRIBUTOR_ROLE");
    await (await liquidityMiningManager.grantRole(REWARD_DISTRIBUTOR_ROLE, multisig)).wait(3);
    console.log("Assigning DEFAULT_ADMIN_ROLE");
    await (await liquidityMiningManager.grantRole(DEFAULT_ADMIN_ROLE, multisig)).wait(3);

    console.log("Assigning DEFAULT_ADMIN roles on pools");
    await (await escrowPool.grantRole(DEFAULT_ADMIN_ROLE, multisig)).wait(3);
    await (await mcPool.grantRole(DEFAULT_ADMIN_ROLE, multisig)).wait(3);
    await (await mcLPPool.grantRole(DEFAULT_ADMIN_ROLE, multisig)).wait(3);

    console.log("DONE");

    console.table({
        liquidityMiningManager: liquidityMiningManager.address,
        escrowPool: escrowPool.address,
        mcPool: mcPool.address,
        mcLPPool: mcLPPool.address,
        view: view.address
    });

    console.log("CHECK IF EVERYTHING IS CORRECTLY SETUP AND THEN RENOUNCE THE DEFAULT_ADMIN_ROLE and pools ON THE liquidityMiningManager CONTRACT FROM THE DEPLOYER ADDRESS");
    console.log("❤⭕");
});