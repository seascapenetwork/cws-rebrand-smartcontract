// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/Staking.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Mock ERC20 Token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title 测试 rewardDebt 修复的测试套件
/// @notice 这个测试重现审计报告 STA-1 中描述的场景
contract StakingRewardDebtFixTest is Test {
    Staking public staking;
    MockERC20 public lpToken;
    MockERC20 public rewardToken;
    MockERC20 public checkInRewardToken;

    address public owner;
    address public alice;
    address public bob;

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // 部署合约
        staking = new Staking(owner);
        lpToken = new MockERC20("LP Token", "LP");
        rewardToken = new MockERC20("Reward Token", "REWARD");
        checkInRewardToken = new MockERC20("CheckIn Reward", "CHECKIN");

        // 给用户发送代币
        lpToken.mint(alice, 1000 * 10 ** 18);
        lpToken.mint(bob, 1000 * 10 ** 18);
    }

    /// @notice 测试审计报告中的场景: 多次追加质押后奖励计算
    /// @dev 重现审计报告 STA-1 的例子
    function testMultipleDepositRewardCalculation() public {
        // 场景设置:
        // - 总奖励: 1000 tokens
        // - 持续时间: 100 秒
        // - rewardPerSecond = 10
        uint256 totalReward = 1000 * 10 ** 18;
        uint256 checkInReward = 100 * 10 ** 18;
        uint256 startTime = block.timestamp + 100; // 给足够的时间
        uint256 duration = 100;
        uint256 endTime = startTime + duration;

        // 授权和创建session
        rewardToken.approve(address(staking), totalReward);
        checkInRewardToken.approve(address(staking), checkInReward);

        staking.createSession(
            Staking.CreateSessionParams({
                stakingToken: address(lpToken),
                rewardToken: address(rewardToken),
                checkInRewardToken: address(checkInRewardToken),
                totalReward: totalReward,
                checkInRewardPool: checkInReward,
                startTime: startTime,
                endTime: endTime
            })
        );

        uint256 sessionId = 1;

        // 打印当前时间和 session 时间
        console.log("Current block.timestamp:", block.timestamp);
        console.log("Session start time variable:", startTime);
        console.log("Session end time variable:", endTime);
        console.log("Duration:", duration);

        // 获取实际的 session 信息
        Staking.Session memory sessionInfo = staking.getSessionInfo(sessionId);
        console.log("Actual session start:", sessionInfo.startTime);
        console.log("Actual session end:", sessionInfo.endTime);

        // 跳到session开始
        vm.warp(sessionInfo.startTime);

        // Bob 在 t=0 质押 100 tokens
        vm.startPrank(bob);
        lpToken.approve(address(staking), 100 * 10 ** 18);
        staking.deposit(sessionId, 100 * 10 ** 18);
        vm.stopPrank();

        // 跳到 t=50
        vm.warp(sessionInfo.startTime + 50);

        // Alice 在 t=50 质押 100 tokens
        vm.startPrank(alice);
        lpToken.approve(address(staking), 200 * 10 ** 18);
        staking.deposit(sessionId, 100 * 10 ** 18);
        vm.stopPrank();

        // 检查 Alice 的状态
        (uint256 aliceAmount1, uint256 aliceRewardDebt1,,,,) = staking.userInfo(sessionId, alice);
        console.log("After first deposit:");
        console.log("  Alice amount:", aliceAmount1 / 10 ** 18);
        console.log("  Alice rewardDebt:", aliceRewardDebt1 / 10 ** 18);

        // 跳到 t=80 (确保还在 session 期间)
        vm.warp(sessionInfo.startTime + 80);
        require(block.timestamp <= sessionInfo.endTime, "Should still be in session");

        // Alice 在 t=80 再质押 100 tokens
        vm.startPrank(alice);
        staking.deposit(sessionId, 100 * 10 ** 18);
        vm.stopPrank();

        // 检查 Alice 的状态
        (uint256 aliceAmount2, uint256 aliceRewardDebt2, uint256 aliceAccumulated2,,,) =
            staking.userInfo(sessionId, alice);
        console.log("\nAfter second deposit:");
        console.log("  Alice amount:", aliceAmount2 / 10 ** 18);
        console.log("  Alice rewardDebt:", aliceRewardDebt2 / 10 ** 18);
        console.log("  Alice accumulated:", aliceAccumulated2 / 10 ** 18);

        // 跳到 session 结束后
        vm.warp(sessionInfo.endTime + 1);

        // 查询 Alice 和 Bob 的待领取奖励
        uint256 alicePending = staking.pendingReward(sessionId, alice);
        uint256 bobPending = staking.pendingReward(sessionId, bob);

        console.log("\nAt t=100 (session end):");
        console.log("  Alice pending reward:", alicePending / 10 ** 18);
        console.log("  Bob pending reward:", bobPending / 10 ** 18);

        // Alice 应该得到的奖励:
        // t=50-80: 30秒, 质押100/200 → 30*10*(100/200) = 150 tokens
        // t=80-100: 20秒, 质押200/300 → 20*10*(200/300) = 133.33 tokens
        // 总计: 150 + 133.33 = 283.33 tokens
        //
        // 使用当前代码逻辑计算:
        // - t=50时 accRewardPerShare = 5 (Bob产生的500奖励/100质押)
        // - Alice 第一次存款: rewardDebt = 100×5 = 500, accumulatedReward = 0
        // - t=80时 accRewardPerShare = 5 + 1.5 = 6.5
        // - Alice 在 t=50到t=80 期间: pending = 100×6.5 - 500 = 150 → 存入 accumulatedReward
        // - Alice 第二次存款: amount=200, rewardDebt = 200×6.5 = 1300, accumulatedReward = 150
        // - t=100时 accRewardPerShare = 6.5 + 200/300 ≈ 7.167
        // - Alice 最终: 150 + (200×7.167 - 1300) = 150 + 133.33 = 283.33 ✅
        uint256 expectedAliceReward = 283333333333333333333; // 283.33... tokens

        // Bob 应该得到的奖励:
        // t=0-50: 50秒, 质押100/100 → 50*10 = 500 tokens
        // t=50-80: 30秒, 质押100/200 → 30*10*(100/200) = 150 tokens
        // t=80-100: 20秒, 质押100/300 → 20*10*(100/300) = 66.67 tokens
        // 总计: 716.67 tokens
        uint256 expectedBobReward = 716666666666666666666; // 716.66... tokens

        // 验证奖励计算 (允许极小的精度误差)
        assertApproxEqRel(alicePending, expectedAliceReward, 0.01e18, "Alice reward should be ~283.33 tokens");
        assertApproxEqRel(bobPending, expectedBobReward, 0.01e18, "Bob reward should be ~716.67 tokens");

        // 验证总奖励不超过 totalReward
        assertLe(alicePending + bobPending, totalReward, "Total rewards should not exceed totalReward");

        // Alice 提取
        vm.prank(alice);
        staking.withdraw(sessionId);

        // Bob 提取
        vm.prank(bob);
        staking.withdraw(sessionId);

        // 验证实际收到的奖励代币
        uint256 aliceRewardBalance = rewardToken.balanceOf(alice);
        uint256 bobRewardBalance = rewardToken.balanceOf(bob);

        console.log("\nAfter withdrawal:");
        console.log("  Alice reward balance:", aliceRewardBalance / 10 ** 18);
        console.log("  Bob reward balance:", bobRewardBalance / 10 ** 18);
        console.log("  Total distributed:", (aliceRewardBalance + bobRewardBalance) / 10 ** 18);
        console.log("  Locked in contract:", (totalReward - aliceRewardBalance - bobRewardBalance) / 10 ** 18);

        assertApproxEqRel(aliceRewardBalance, expectedAliceReward, 0.01e18, "Alice should receive ~283.33 tokens");
        assertApproxEqRel(bobRewardBalance, expectedBobReward, 0.01e18, "Bob should receive ~716.67 tokens");

        // 验证没有大量代币被锁定在合约中
        uint256 lockedAmount = totalReward - aliceRewardBalance - bobRewardBalance;
        assertLe(lockedAmount, 1e18, "Locked amount should be minimal (< 1 token due to rounding)");
    }

    /// @notice 测试单次质押的基准情况
    function testSingleDepositRewardCalculation() public {
        uint256 totalReward = 1000 * 10 ** 18;
        uint256 checkInReward = 100 * 10 ** 18;
        uint256 startTime = block.timestamp + 1;
        uint256 duration = 100;
        uint256 endTime = startTime + duration;

        rewardToken.approve(address(staking), totalReward);
        checkInRewardToken.approve(address(staking), checkInReward);

        staking.createSession(
            Staking.CreateSessionParams({
                stakingToken: address(lpToken),
                rewardToken: address(rewardToken),
                checkInRewardToken: address(checkInRewardToken),
                totalReward: totalReward,
                checkInRewardPool: checkInReward,
                startTime: startTime,
                endTime: endTime
            })
        );

        uint256 sessionId = 1;
        vm.warp(startTime);

        // Alice 单次质押 100 tokens
        vm.startPrank(alice);
        lpToken.approve(address(staking), 100 * 10 ** 18);
        staking.deposit(sessionId, 100 * 10 ** 18);
        vm.stopPrank();

        // 跳到 session 结束
        vm.warp(endTime + 1);

        uint256 alicePending = staking.pendingReward(sessionId, alice);

        // Alice 应该得到全部 1000 tokens
        assertEq(alicePending, totalReward, "Alice should receive all rewards");

        vm.prank(alice);
        staking.withdraw(sessionId);

        uint256 aliceBalance = rewardToken.balanceOf(alice);
        assertEq(aliceBalance, totalReward, "Alice should receive all reward tokens");
    }
}
