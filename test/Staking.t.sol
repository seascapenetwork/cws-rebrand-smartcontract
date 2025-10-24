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

/// @title Staking测试套件
contract StakingTest is Test {
    Staking public staking;
    MockERC20 public lpToken;
    MockERC20 public rewardToken;
    MockERC20 public checkInRewardToken;

    address public owner;
    address public user1;
    address public user2;
    address public user3;

    uint256 constant INITIAL_BALANCE = 1000000 * 10 ** 18;
    uint256 constant CHECKIN_COOLDOWN = 300; // 5 minutes

    event CheckedIn(uint256 indexed sessionId, address indexed user, uint256 timestamp);

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        // 部署合约
        staking = new Staking(owner);
        lpToken = new MockERC20("LP Token", "LP");
        rewardToken = new MockERC20("Reward Token", "REWARD");
        checkInRewardToken = new MockERC20("CheckIn Reward", "CHECKIN");

        // 给用户发送代币
        lpToken.mint(user1, INITIAL_BALANCE);
        lpToken.mint(user2, INITIAL_BALANCE);
        lpToken.mint(user3, INITIAL_BALANCE);

        // 给用户发送ETH (用于BNB测试)
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
    }

    // ============================================
    // 测试: createSession
    // ============================================

    function testCreateSession() public {
        uint256 totalReward = 10000 * 10 ** 18;
        uint256 checkInReward = 5000 * 10 ** 18;
        uint256 startTime = block.timestamp + 1 days;
        uint256 endTime = startTime + 30 days;

        // 授权
        rewardToken.approve(address(staking), totalReward);
        checkInRewardToken.approve(address(staking), checkInReward);

        // 创建session
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

        // 验证
        (
            address stakingToken,
            address _rewardToken,
            address _checkInRewardToken,
            uint256 _totalReward,
            uint256 _checkInRewardPool,
            uint256 _startTime,
            uint256 _endTime,,,,,,,,
            uint256 gamma,

        ) = staking.sessions(1);

        assertEq(stakingToken, address(lpToken));
        assertEq(_rewardToken, address(rewardToken));
        assertEq(_checkInRewardToken, address(checkInRewardToken));
        assertEq(_totalReward, totalReward);
        assertEq(_checkInRewardPool, checkInReward);
        assertEq(_startTime, startTime);
        assertEq(_endTime, endTime);
        assertEq(gamma, 6e17); // 默认gamma = 0.6
    }

    function testSetGamma() public {
        uint256 sessionId = _createTestSession();

        // 在session开始前修改gamma
        uint256 newGamma = 5e17; // 0.5
        staking.setGamma(sessionId, newGamma);

        // 验证
        (,,,,,,,,,,,,,, uint256 gamma, bool active, uint256 totalTimeWeightedStake) = staking.sessions(sessionId);
        assertEq(gamma, newGamma);
    }

    function testCannotSetGammaAfterSessionStarts() public {
        uint256 sessionId = _createTestSession();

        // 时间前进到session开始后
        vm.warp(block.timestamp + 1 days + 1);

        // 尝试修改gamma (应该失败)
        vm.expectRevert("Cannot modify gamma after session started");
        staking.setGamma(sessionId, 7e17);
    }

    function testCannotSetGammaGreaterThan1() public {
        uint256 sessionId = _createTestSession();

        // 尝试设置gamma > 1e18 (应该失败)
        vm.expectRevert("Gamma must be <= 1e18");
        staking.setGamma(sessionId, 1.1e18);
    }

    function testSetGammaBoundaryValues() public {
        uint256 sessionId = _createTestSession();

        // 测试gamma = 0 (全部分配给hybrid部分)
        staking.setGamma(sessionId, 0);
        (,,,,,,,,,,,,,, uint256 gamma1, bool _, uint256 _) = staking.sessions(sessionId);
        assertEq(gamma1, 0);

        // 创建新session测试gamma = 1e18 (全部分配给stake部分)
        vm.warp(block.timestamp + 32 days);
        uint256 sessionId2 = _createTestSession();
        staking.setGamma(sessionId2, 1e18);
        (,,,,,,,,,,,,,, uint256 gamma2, bool _, uint256 _) = staking.sessions(sessionId2);
        assertEq(gamma2, 1e18);
    }

    function testOnlyOwnerCanSetGamma() public {
        uint256 sessionId = _createTestSession();

        // 非owner尝试设置gamma
        vm.prank(user1);
        vm.expectRevert();
        staking.setGamma(sessionId, 5e17);
    }

    // BNB support has been removed
    // function testCreateSessionWithBNB() public { ... }

    function testCannotCreateSessionWithOverlappingTime() public {
        uint256 totalReward = 10000 * 10 ** 18;
        uint256 checkInReward = 5000 * 10 ** 18;

        rewardToken.approve(address(staking), totalReward * 2);
        checkInRewardToken.approve(address(staking), checkInReward * 2);

        // 第一个session
        staking.createSession(
            Staking.CreateSessionParams({
                stakingToken: address(lpToken),
                rewardToken: address(rewardToken),
                checkInRewardToken: address(checkInRewardToken),
                totalReward: totalReward,
                checkInRewardPool: checkInReward,
                startTime: block.timestamp + 1 days,
                endTime: block.timestamp + 11 days
            })
        );

        // 尝试创建重叠的session (应该失败)
        vm.expectRevert("Session time overlaps with existing session");
        staking.createSession(
            Staking.CreateSessionParams({
                stakingToken: address(lpToken),
                rewardToken: address(rewardToken),
                checkInRewardToken: address(checkInRewardToken),
                totalReward: totalReward,
                checkInRewardPool: checkInReward,
                startTime: block.timestamp + 5 days, // 重叠
                endTime: block.timestamp + 15 days
            })
        );
    }

    function testCannotCreateSessionBeforePreviousEnds() public {
        uint256 totalReward = 10000 * 10 ** 18;
        uint256 checkInReward = 5000 * 10 ** 18;

        rewardToken.approve(address(staking), totalReward * 2);
        checkInRewardToken.approve(address(staking), checkInReward * 2);

        // 第一个session
        staking.createSession(
            Staking.CreateSessionParams({
                stakingToken: address(lpToken),
                rewardToken: address(rewardToken),
                checkInRewardToken: address(checkInRewardToken),
                totalReward: totalReward,
                checkInRewardPool: checkInReward,
                startTime: block.timestamp + 1 days,
                endTime: block.timestamp + 11 days
            })
        );

        // 尝试在第一个session结束前创建新的 (应该失败)
        vm.expectRevert("Previous session not ended");
        staking.createSession(
            Staking.CreateSessionParams({
                stakingToken: address(lpToken),
                rewardToken: address(rewardToken),
                checkInRewardToken: address(checkInRewardToken),
                totalReward: totalReward,
                checkInRewardPool: checkInReward,
                startTime: block.timestamp + 20 days,
                endTime: block.timestamp + 30 days
            })
        );
    }

    // ============================================
    // 测试: deposit
    // ============================================

    function testDeposit() public {
        // 创建session
        uint256 sessionId = _createTestSession();

        // 时间前进到session开始
        vm.warp(block.timestamp + 1 days + 1);

        // 用户1质押
        uint256 depositAmount = 1000 * 10 ** 18;
        vm.startPrank(user1);
        lpToken.approve(address(staking), depositAmount);
        staking.deposit(sessionId, depositAmount);
        vm.stopPrank();

        // 验证
        (uint256 amount,,,,,,,) = staking.userInfo(sessionId, user1);
        assertEq(amount, depositAmount);
    }

    // BNB support has been removed
    // function testDepositBNB() public { ... }

    function testCannotDepositBeforeSessionStarts() public {
        uint256 sessionId = _createTestSession();

        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10 ** 18);
        vm.expectRevert("Session not started");
        staking.deposit(sessionId, 1000 * 10 ** 18);
        vm.stopPrank();
    }

    function testCannotDepositAfterSessionEnds() public {
        uint256 sessionId = _createTestSession();

        // 时间前进到session结束后
        vm.warp(block.timestamp + 32 days);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10 ** 18);
        vm.expectRevert("Session ended");
        staking.deposit(sessionId, 1000 * 10 ** 18);
        vm.stopPrank();
    }

    function testMultipleDeposits() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        uint256 firstDeposit = 500 * 10 ** 18;
        uint256 secondDeposit = 300 * 10 ** 18;

        vm.startPrank(user1);
        lpToken.approve(address(staking), firstDeposit + secondDeposit);

        staking.deposit(sessionId, firstDeposit);
        staking.deposit(sessionId, secondDeposit);

        vm.stopPrank();

        (uint256 amount,,,,,,,) = staking.userInfo(sessionId, user1);
        assertEq(amount, firstDeposit + secondDeposit);
    }

    /// @notice 测试多次deposit会累积奖励而不是清零
    function testMultipleDepositsAccumulateRewards() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(user1);

        // 第一次质押 50个币
        lpToken.approve(address(staking), 50 * 10 ** 18);
        staking.deposit(sessionId, 50 * 10 ** 18);

        // 等待10分钟,让奖励累积
        vm.warp(block.timestamp + 600);

        // 查询第一次的pending奖励
        uint256 pendingBefore = staking.pendingReward(sessionId, user1);
        assertGt(pendingBefore, 0, "Should have pending rewards after 10 minutes");

        // 第二次质押 1个币
        lpToken.approve(address(staking), 1 * 10 ** 18);
        staking.deposit(sessionId, 1 * 10 ** 18);

        // 查询deposit后的奖励 - 应该保留之前的奖励
        uint256 pendingAfter = staking.pendingReward(sessionId, user1);

        // deposit后,之前的pending应该被累积到accumulatedReward
        // pendingAfter应该 >= pendingBefore (可能会稍微小一点因为时间精度)
        assertApproxEqRel(pendingAfter, pendingBefore, 0.001e18, "Rewards should be accumulated, not reset");

        // 再等待10分钟
        vm.warp(block.timestamp + 600);

        // 现在的pending应该是: accumulatedReward + 新的pending
        uint256 pendingFinal = staking.pendingReward(sessionId, user1);
        assertGt(pendingFinal, pendingAfter, "Rewards should continue to accumulate");

        // 验证用户信息中确实有accumulatedReward
        Staking.UserInfo memory userInfo = staking.getUserInfo(sessionId, user1);
        assertGt(userInfo.accumulatedReward, 0, "Should have accumulated rewards stored");
        assertApproxEqRel(
            userInfo.accumulatedReward, pendingBefore, 0.001e18, "Accumulated should match first deposit's pending"
        );

        vm.stopPrank();
    }

    /// @notice 测试三次deposit的累积效果
    function testThreeDepositsAccumulateCorrectly() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(user1);

        // 第一次质押
        lpToken.approve(address(staking), 100 * 10 ** 18);
        staking.deposit(sessionId, 30 * 10 ** 18);
        vm.warp(block.timestamp + 300);

        uint256 pending1 = staking.pendingReward(sessionId, user1);

        // 第二次质押
        staking.deposit(sessionId, 30 * 10 ** 18);
        vm.warp(block.timestamp + 300);

        uint256 pending2 = staking.pendingReward(sessionId, user1);
        assertGt(pending2, pending1, "Second deposit should accumulate more");

        // 第三次质押
        staking.deposit(sessionId, 40 * 10 ** 18);
        vm.warp(block.timestamp + 300);

        uint256 pending3 = staking.pendingReward(sessionId, user1);
        assertGt(pending3, pending2, "Third deposit should accumulate even more");

        // 最终withdraw应该获得所有累积的奖励
        vm.warp(block.timestamp + 31 days);

        uint256 balanceBefore = rewardToken.balanceOf(user1);
        staking.withdraw(sessionId);
        uint256 balanceAfter = rewardToken.balanceOf(user1);

        uint256 receivedReward = balanceAfter - balanceBefore;
        assertGt(receivedReward, 0, "Should receive accumulated rewards on withdraw");

        vm.stopPrank();
    }

    function testDepositDoesNotResetBoost() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 2000 * 10 ** 18);

        // 第一次质押
        staking.deposit(sessionId, 1000 * 10 ** 18);

        // 签到
        staking.checkIn(sessionId);

        // 等待5分钟后再次签到
        vm.warp(block.timestamp + 301);
        staking.checkIn(sessionId);

        // 验证boost = 2
        (,,, uint256 boostBefore,,,,) = staking.userInfo(sessionId, user1);
        assertEq(boostBefore, 2);

        // 第二次质押 (复存)
        staking.deposit(sessionId, 1000 * 10 ** 18);

        // 验证boost没有被重置
        (,,, uint256 boostAfter,,,,) = staking.userInfo(sessionId, user1);
        assertEq(boostAfter, 2);

        vm.stopPrank();
    }

    // ============================================
    // 测试: checkIn - 新的5分钟冷却机制
    // ============================================

    function testCheckInFirstTime() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        // 用户1质押
        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10 ** 18);
        staking.deposit(sessionId, 1000 * 10 ** 18);

        // 首次签到
        vm.expectEmit(true, true, false, true);
        emit CheckedIn(sessionId, user1, block.timestamp);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // 验证
        (,,, uint256 boost, uint40 lastCheckInTime,,,) = staking.userInfo(sessionId, user1);
        assertEq(boost, 1);
        assertEq(lastCheckInTime, block.timestamp);
    }

    function testCheckInMultipleTimes() public {
        uint256 sessionId = _createTestSession();
        uint256 startTime = block.timestamp + 1 days + 1;
        vm.warp(startTime);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10 ** 18);
        staking.deposit(sessionId, 1000 * 10 ** 18);

        // 第1次签到
        staking.checkIn(sessionId);
        (,,, uint256 boost1,,,,) = staking.userInfo(sessionId, user1);
        assertEq(boost1, 1);

        // 等待5分钟后第2次签到
        vm.warp(startTime + 300);
        staking.checkIn(sessionId);
        (,,, uint256 boost2,,,,) = staking.userInfo(sessionId, user1);
        assertEq(boost2, 2);

        // 等待5分钟后第3次签到
        vm.warp(startTime + 600);
        staking.checkIn(sessionId);
        (,,, uint256 boost3,,,,) = staking.userInfo(sessionId, user1);
        assertEq(boost3, 3);

        // 等待更长时间后第4次签到
        vm.warp(startTime + 1600);
        staking.checkIn(sessionId);
        (,,, uint256 boost4,,,,) = staking.userInfo(sessionId, user1);
        assertEq(boost4, 4);

        vm.stopPrank();
    }

    function testCannotCheckInWithoutStaking() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(user1);
        vm.expectRevert("Must stake before check-in");
        staking.checkIn(sessionId);
    }

    function testCannotCheckInBeforeCooldown() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10 ** 18);
        staking.deposit(sessionId, 1000 * 10 ** 18);

        // 第一次签到
        staking.checkIn(sessionId);

        // 立即尝试第二次签到 (应该失败)
        vm.expectRevert("Check-in cooldown not expired");
        staking.checkIn(sessionId);

        // 等待299秒 (不够5分钟)
        vm.warp(block.timestamp + 299);
        vm.expectRevert("Check-in cooldown not expired");
        staking.checkIn(sessionId);

        // 等待300秒 (刚好5分钟) - 应该成功
        vm.warp(block.timestamp + 1);
        staking.checkIn(sessionId);

        vm.stopPrank();
    }

    function testCheckInCooldownExactly5Minutes() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10 ** 18);
        staking.deposit(sessionId, 1000 * 10 ** 18);

        uint256 firstCheckInTime = block.timestamp;
        staking.checkIn(sessionId);

        // 等待刚好300秒
        vm.warp(firstCheckInTime + 300);
        staking.checkIn(sessionId); // 应该成功

        (,,, uint256 boost,,,,) = staking.userInfo(sessionId, user1);
        assertEq(boost, 2);

        vm.stopPrank();
    }

    function testMultipleUsersCheckInIndependently() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        // 用户1质押和签到
        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10 ** 18);
        staking.deposit(sessionId, 1000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // 用户2在2分钟后质押和签到
        vm.warp(block.timestamp + 120);
        vm.startPrank(user2);
        lpToken.approve(address(staking), 2000 * 10 ** 18);
        staking.deposit(sessionId, 2000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // 3分钟后，用户1可以再次签到 (距离首次5分钟)
        vm.warp(block.timestamp + 180);
        vm.prank(user1);
        staking.checkIn(sessionId);

        // 但用户2不能 (只过了3分钟)
        vm.prank(user2);
        vm.expectRevert("Check-in cooldown not expired");
        staking.checkIn(sessionId);

        // 验证boost
        (,,, uint256 boost1,,,,) = staking.userInfo(sessionId, user1);
        (,,, uint256 boost2,,,,) = staking.userInfo(sessionId, user2);
        assertEq(boost1, 2);
        assertEq(boost2, 1);
    }

    function testCheckInBoostAccumulatesOverTime() public {
        uint256 sessionId = _createTestSession();
        uint256 startTime = block.timestamp + 1 days + 1;
        vm.warp(startTime);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10 ** 18);
        staking.deposit(sessionId, 1000 * 10 ** 18);

        // 模拟一天内多次签到 (每5分钟一次)
        for (uint256 i = 0; i < 10; i++) {
            staking.checkIn(sessionId);
            vm.warp(startTime + (300 * (i + 1)));
        }

        (,,, uint256 finalBoost,,,,) = staking.userInfo(sessionId, user1);
        assertEq(finalBoost, 10);

        vm.stopPrank();
    }

    // ============================================
    // 测试: withdraw
    // ============================================

    function testWithdraw() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        uint256 depositAmount = 1000 * 10 ** 18;

        // 用户1质押并签到
        vm.startPrank(user1);
        lpToken.approve(address(staking), depositAmount);
        staking.deposit(sessionId, depositAmount);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // 时间前进到session结束后
        vm.warp(block.timestamp + 31 days);

        // 提取
        uint256 beforeBalance = lpToken.balanceOf(user1);
        uint256 beforeRewardBalance = rewardToken.balanceOf(user1);

        vm.prank(user1);
        staking.withdraw(sessionId);

        // 验证本金返还
        assertEq(lpToken.balanceOf(user1), beforeBalance + depositAmount);

        // 验证奖励大于0
        assertGt(rewardToken.balanceOf(user1), beforeRewardBalance);
    }

    function testCannotWithdrawBeforeSessionEnds() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10 ** 18);
        staking.deposit(sessionId, 1000 * 10 ** 18);

        vm.expectRevert("Session not ended yet");
        staking.withdraw(sessionId);
        vm.stopPrank();
    }

    function testCannotWithdrawTwice() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10 ** 18);
        staking.deposit(sessionId, 1000 * 10 ** 18);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        vm.startPrank(user1);
        staking.withdraw(sessionId);

        vm.expectRevert("Already withdrawn");
        staking.withdraw(sessionId);
        vm.stopPrank();
    }

    function testWithdrawWithCheckInReward() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        uint256 user1Deposit = 6000 * 10 ** 18; // 60%
        uint256 user2Deposit = 4000 * 10 ** 18; // 40%

        // 用户1质押并签到
        vm.startPrank(user1);
        lpToken.approve(address(staking), user1Deposit);
        staking.deposit(sessionId, user1Deposit);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // 用户2质押但不签到
        vm.startPrank(user2);
        lpToken.approve(address(staking), user2Deposit);
        staking.deposit(sessionId, user2Deposit);
        vm.stopPrank();

        // 时间前进到session结束后
        vm.warp(block.timestamp + 31 days);

        // 用户1提取
        uint256 beforeCheckInReward = checkInRewardToken.balanceOf(user1);
        vm.prank(user1);
        staking.withdraw(sessionId);

        // 验证用户1获得签到奖励:
        // stakeReward = 3000 * (6000/10000) = 1800
        // hybridReward = 2000 (独享)
        // total = 3800
        assertApproxEqRel(checkInRewardToken.balanceOf(user1) - beforeCheckInReward, 3800 * 10 ** 18, 0.02e18);

        // 用户2提取
        uint256 user2CheckInRewardBefore = checkInRewardToken.balanceOf(user2);
        vm.prank(user2);
        staking.withdraw(sessionId);

        // 验证用户2没签到,不获得boost奖励
        assertEq(checkInRewardToken.balanceOf(user2) - user2CheckInRewardBefore, 0);
    }

    function testWithdrawWithMultipleCheckIns() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        uint256 user1Deposit = 5000 * 10 ** 18;
        uint256 user2Deposit = 5000 * 10 ** 18;

        // 用户1质押并签到1次
        vm.startPrank(user1);
        lpToken.approve(address(staking), user1Deposit);
        staking.deposit(sessionId, user1Deposit);
        staking.checkIn(sessionId); // boost = 1
        vm.stopPrank();

        // 用户2质押并签到2次
        vm.startPrank(user2);
        lpToken.approve(address(staking), user2Deposit);
        staking.deposit(sessionId, user2Deposit);
        staking.checkIn(sessionId); // boost = 1
        vm.warp(block.timestamp + 300);
        staking.checkIn(sessionId); // boost = 2
        vm.stopPrank();

        // 时间前进到session结束
        vm.warp(block.timestamp + 31 days);

        // 获取签到奖励
        uint256 user1CheckIn = staking.pendingBoostReward(sessionId, user1);
        uint256 user2CheckIn = staking.pendingBoostReward(sessionId, user2);

        // 使用分池权重法:
        // stakePart=3000: 各1500
        // hybridPart=2000, totalBoostPoints=3
        // user1: 1500 + 2000*(0.5*1/3)/0.5 = 1500 + 666.67 = 2166.67
        // user2: 1500 + 2000*(0.5*2/3)/0.5 = 1500 + 1333.33 = 2833.33
        assertApproxEqRel(user1CheckIn, 2166666666666666666666, 0.02e18);
        assertApproxEqRel(user2CheckIn, 2833333333333333333333, 0.02e18);
    }

    // ============================================
    // 测试: 奖励计算
    // ============================================

    function testRewardCalculation() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        uint256 user1Deposit = 6000 * 10 ** 18;
        uint256 user2Deposit = 4000 * 10 ** 18;

        // 用户1质押
        vm.startPrank(user1);
        lpToken.approve(address(staking), user1Deposit);
        staking.deposit(sessionId, user1Deposit);
        vm.stopPrank();

        // 用户2质押
        vm.startPrank(user2);
        lpToken.approve(address(staking), user2Deposit);
        staking.deposit(sessionId, user2Deposit);
        vm.stopPrank();

        // 时间前进到session结束
        vm.warp(block.timestamp + 31 days);

        // 获取待领取奖励
        uint256 user1Pending = staking.pendingReward(sessionId, user1);
        uint256 user2Pending = staking.pendingReward(sessionId, user2);

        // 用户1应该获得60%的奖励，用户2获得40%
        // 允许一定误差
        assertApproxEqRel(user1Pending, 6000 * 10 ** 18, 0.01e18); // 1% tolerance
        assertApproxEqRel(user2Pending, 4000 * 10 ** 18, 0.01e18);
    }

    function testCheckInRewardCalculation() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        uint256 user1Deposit = 6000 * 10 ** 18;
        uint256 user2Deposit = 4000 * 10 ** 18;

        // 用户1质押并签到
        vm.startPrank(user1);
        lpToken.approve(address(staking), user1Deposit);
        staking.deposit(sessionId, user1Deposit);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // 用户2质押并签到
        vm.startPrank(user2);
        lpToken.approve(address(staking), user2Deposit);
        staking.deposit(sessionId, user2Deposit);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // 时间前进到session结束
        vm.warp(block.timestamp + 31 days);

        // 获取签到奖励
        uint256 user1CheckIn = staking.pendingBoostReward(sessionId, user1);
        uint256 user2CheckIn = staking.pendingBoostReward(sessionId, user2);

        // 使用新的分池权重法计算:
        // gamma = 0.6, totalBoostPool = 5000
        // stake部分 = 5000 * 0.6 = 3000
        // hybrid部分 = 5000 * 0.4 = 2000
        // 用户1: stakeReward = 3000 * 0.6 = 1800, hybridReward = 2000 * 0.6 = 1200, total = 3000
        // 用户2: stakeReward = 3000 * 0.4 = 1200, hybridReward = 2000 * 0.4 = 800, total = 2000
        assertApproxEqRel(user1CheckIn, 3000 * 10 ** 18, 0.01e18);
        assertApproxEqRel(user2CheckIn, 2000 * 10 ** 18, 0.01e18);
    }

    function testCheckInRewardWithDifferentBoosts() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        uint256 depositAmount = 1000 * 10 ** 18;

        // 用户1: 1次签到 (boost = 1)
        vm.startPrank(user1);
        lpToken.approve(address(staking), depositAmount);
        staking.deposit(sessionId, depositAmount);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // 用户2: 2次签到 (boost = 2)
        vm.startPrank(user2);
        lpToken.approve(address(staking), depositAmount);
        staking.deposit(sessionId, depositAmount);
        staking.checkIn(sessionId);
        vm.warp(block.timestamp + 300);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // 用户3: 3次签到 (boost = 3)
        vm.startPrank(user3);
        lpToken.approve(address(staking), depositAmount);
        staking.deposit(sessionId, depositAmount);
        staking.checkIn(sessionId);
        vm.warp(block.timestamp + 300);
        staking.checkIn(sessionId);
        vm.warp(block.timestamp + 300);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // 时间前进到session结束
        vm.warp(block.timestamp + 31 days);

        // 获取签到奖励
        uint256 reward1 = staking.pendingBoostReward(sessionId, user1);
        uint256 reward2 = staking.pendingBoostReward(sessionId, user2);
        uint256 reward3 = staking.pendingBoostReward(sessionId, user3);

        // 新的分池权重法计算:
        // gamma = 0.6, totalBoostPool = 5000
        // stake部分 = 5000 * 0.6 = 3000, 每人获得 3000/3 = 1000
        // hybrid部分 = 5000 * 0.4 = 2000
        // totalBoostPoints = 1+2+3 = 6
        // user1: stakeReward=1000, sb1=(1/3)*(1/6)=1/18, hybridReward=2000*(1/18)/(1/18+2/18+3/18)=2000*1/6=333.33
        // user2: stakeReward=1000, sb2=(1/3)*(2/6)=2/18, hybridReward=2000*2/6=666.66
        // user3: stakeReward=1000, sb3=(1/3)*(3/6)=3/18, hybridReward=2000*3/6=1000

        assertApproxEqRel(reward1, 1333333333333333333333, 0.02e18); // ~1333.33
        assertApproxEqRel(reward2, 1666666666666666666666, 0.02e18); // ~1666.66
        assertApproxEqRel(reward3, 2000 * 10 ** 18, 0.02e18); // ~2000
    }

    function testPendingRewardBeforeSessionEnds() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10 ** 18);
        staking.deposit(sessionId, 1000 * 10 ** 18);
        vm.stopPrank();

        // 时间前进15天 (一半)
        vm.warp(block.timestamp + 15 days);

        uint256 pendingReward = staking.pendingReward(sessionId, user1);

        // 应该获得大约一半的奖励
        assertApproxEqRel(pendingReward, 5000 * 10 ** 18, 0.05e18); // 5% tolerance
    }

    // ============================================
    // 测试: 新的boost奖励算法 - 分池权重法
    // ============================================

    function testBoostRewardWithGammaZero() public {
        uint256 sessionId = _createTestSession();

        // 设置gamma=0 (全部分配给hybrid部分)
        staking.setGamma(sessionId, 0);

        vm.warp(block.timestamp + 1 days + 1);

        // 用户1: 质押1000, boost=1
        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10 ** 18);
        staking.deposit(sessionId, 1000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // 用户2: 质押1000, boost=2
        vm.startPrank(user2);
        lpToken.approve(address(staking), 1000 * 10 ** 18);
        staking.deposit(sessionId, 1000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.warp(block.timestamp + 300);
        staking.checkIn(sessionId);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        uint256 reward1 = staking.pendingBoostReward(sessionId, user1);
        uint256 reward2 = staking.pendingBoostReward(sessionId, user2);

        // gamma=0时,全部按hybrid分配
        // user1应得: 5000 * (0.5*1/3) / (0.5*1/3 + 0.5*2/3) = 5000 * 1/3 = 1666.66
        // user2应得: 5000 * (0.5*2/3) / (0.5*1/3 + 0.5*2/3) = 5000 * 2/3 = 3333.33
        assertApproxEqRel(reward1, 1666666666666666666666, 0.02e18);
        assertApproxEqRel(reward2, 3333333333333333333333, 0.02e18);
    }

    function testBoostRewardWithGammaOne() public {
        uint256 sessionId = _createTestSession();

        // 设置gamma=1 (全部分配给stake部分)
        staking.setGamma(sessionId, 1e18);

        vm.warp(block.timestamp + 1 days + 1);

        // 用户1: 质押6000, boost=1
        vm.startPrank(user1);
        lpToken.approve(address(staking), 6000 * 10 ** 18);
        staking.deposit(sessionId, 6000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // 用户2: 质押4000, boost=5
        uint256 user2StartTime = block.timestamp;
        vm.startPrank(user2);
        lpToken.approve(address(staking), 4000 * 10 ** 18);
        staking.deposit(sessionId, 4000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.warp(user2StartTime + 300);
        staking.checkIn(sessionId);
        vm.warp(user2StartTime + 600);
        staking.checkIn(sessionId);
        vm.warp(user2StartTime + 900);
        staking.checkIn(sessionId);
        vm.warp(user2StartTime + 1200);
        staking.checkIn(sessionId);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        uint256 reward1 = staking.pendingBoostReward(sessionId, user1);
        uint256 reward2 = staking.pendingBoostReward(sessionId, user2);

        // gamma=1时,完全按stake分配,与boost无关
        // user1应得: 5000 * 0.6 = 3000
        // user2应得: 5000 * 0.4 = 2000
        assertApproxEqRel(reward1, 3000 * 10 ** 18, 0.02e18);
        assertApproxEqRel(reward2, 2000 * 10 ** 18, 0.02e18);
    }

    function testBoostRewardNoCheckIn() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        // 用户1质押但不签到
        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10 ** 18);
        staking.deposit(sessionId, 1000 * 10 ** 18);
        vm.stopPrank();

        // 用户2质押并签到
        vm.startPrank(user2);
        lpToken.approve(address(staking), 1000 * 10 ** 18);
        staking.deposit(sessionId, 1000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        uint256 reward1 = staking.pendingBoostReward(sessionId, user1);
        uint256 reward2 = staking.pendingBoostReward(sessionId, user2);

        // user1没有签到,不获得任何boost奖励
        assertEq(reward1, 0);
        // user2签到了,获得:
        // stakeReward = 3000 * (1000/2000) = 1500
        // hybridReward = 2000 (独享hybrid部分)
        // total = 3500
        assertApproxEqRel(reward2, 3500 * 10 ** 18, 0.02e18);
    }

    function testBoostRewardOnlyOneUserCheckIn() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        // 只有user1质押并签到
        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10 ** 18);
        staking.deposit(sessionId, 1000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        uint256 reward1 = staking.pendingBoostReward(sessionId, user1);

        // 只有一个用户,应该获得全部boost奖励
        assertApproxEqRel(reward1, 5000 * 10 ** 18, 0.02e18);
    }

    function testBoostRewardNoOneCheckIn() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        // user1和user2都只质押不签到
        vm.startPrank(user1);
        lpToken.approve(address(staking), 6000 * 10 ** 18);
        staking.deposit(sessionId, 6000 * 10 ** 18);
        vm.stopPrank();

        vm.startPrank(user2);
        lpToken.approve(address(staking), 4000 * 10 ** 18);
        staking.deposit(sessionId, 4000 * 10 ** 18);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        uint256 reward1 = staking.pendingBoostReward(sessionId, user1);
        uint256 reward2 = staking.pendingBoostReward(sessionId, user2);

        // 没人签到时,都不获得boost奖励
        assertEq(reward1, 0);
        assertEq(reward2, 0);
    }

    function testBoostRewardWithDifferentGamma() public {
        // 测试gamma=0.7的情况
        uint256 sessionId = _createTestSession();
        staking.setGamma(sessionId, 7e17); // 0.7

        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 5000 * 10 ** 18);
        staking.deposit(sessionId, 5000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        vm.startPrank(user2);
        lpToken.approve(address(staking), 5000 * 10 ** 18);
        staking.deposit(sessionId, 5000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.warp(block.timestamp + 300);
        staking.checkIn(sessionId);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        uint256 reward1 = staking.pendingBoostReward(sessionId, user1);
        uint256 reward2 = staking.pendingBoostReward(sessionId, user2);

        // gamma=0.7
        // stake部分 = 5000 * 0.7 = 3500, 每人1750
        // hybrid部分 = 5000 * 0.3 = 1500
        // user1: 1750 + 1500*1/3 = 2250
        // user2: 1750 + 1500*2/3 = 2750
        assertApproxEqRel(reward1, 2250 * 10 ** 18, 0.02e18);
        assertApproxEqRel(reward2, 2750 * 10 ** 18, 0.02e18);
    }

    // ============================================
    // 测试: getPendingRewards函数
    // ============================================

    function testGetPendingRewards() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        uint256 depositAmount = 5000 * 10 ** 18;

        // 用户1质押并签到
        vm.startPrank(user1);
        lpToken.approve(address(staking), depositAmount);
        staking.deposit(sessionId, depositAmount);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // 时间前进到session结束
        vm.warp(block.timestamp + 31 days);

        // 使用新函数获取两种奖励
        (uint256 stakingReward, uint256 boostReward) = staking.getPendingRewards(sessionId, user1);

        // 验证与单独查询结果一致
        uint256 pendingStaking = staking.pendingReward(sessionId, user1);
        uint256 pendingBoost = staking.pendingBoostReward(sessionId, user1);

        assertEq(stakingReward, pendingStaking);
        assertEq(boostReward, pendingBoost);

        // 验证具体数值
        assertApproxEqRel(stakingReward, 10000 * 10 ** 18, 0.01e18); // 全部LP奖励
        assertApproxEqRel(boostReward, 5000 * 10 ** 18, 0.01e18); // 全部boost奖励
    }

    function testGetPendingRewardsMultipleUsers() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        // 用户1: 质押6000并签到
        vm.startPrank(user1);
        lpToken.approve(address(staking), 6000 * 10 ** 18);
        staking.deposit(sessionId, 6000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // 用户2: 质押4000不签到
        vm.startPrank(user2);
        lpToken.approve(address(staking), 4000 * 10 ** 18);
        staking.deposit(sessionId, 4000 * 10 ** 18);
        vm.stopPrank();

        // 时间前进到session结束
        vm.warp(block.timestamp + 31 days);

        // 查询用户1
        (uint256 staking1, uint256 boost1) = staking.getPendingRewards(sessionId, user1);
        assertApproxEqRel(staking1, 6000 * 10 ** 18, 0.01e18); // 60% LP奖励
        // user1获得boost奖励:
        // stakeReward = 3000 * (6000/10000) = 1800
        // hybridReward = 2000 (独享)
        // total = 3800
        assertApproxEqRel(boost1, 3800 * 10 ** 18, 0.02e18);

        // 查询用户2
        (uint256 staking2, uint256 boost2) = staking.getPendingRewards(sessionId, user2);
        assertApproxEqRel(staking2, 4000 * 10 ** 18, 0.01e18); // 40% LP奖励
        // user2没签到,不获得boost奖励
        assertEq(boost2, 0);
    }

    function testGetPendingRewardsBeforeSessionEnds() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10 ** 18);
        staking.deposit(sessionId, 1000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // 时间前进15天 (一半)
        vm.warp(block.timestamp + 15 days);

        (uint256 stakingReward, uint256 boostReward) = staking.getPendingRewards(sessionId, user1);

        // LP奖励随时间线性释放，应该约为一半
        assertApproxEqRel(stakingReward, 5000 * 10 ** 18, 0.05e18);

        // boost奖励在session结束时才计算，当前应该能查询到
        assertGt(boostReward, 0);
    }

    function testGetPendingRewardsNoStake() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        // 用户没有质押
        (uint256 stakingReward, uint256 boostReward) = staking.getPendingRewards(sessionId, user1);

        assertEq(stakingReward, 0);
        assertEq(boostReward, 0);
    }

    // ============================================
    // Pausable功能已移除
    // ============================================

    // ============================================
    // 测试: 多session场景
    // ============================================

    function testMultipleSessions() public {
        // 创建第一个session
        uint256 session1 = _createTestSession();

        vm.warp(block.timestamp + 1 days + 1);

        // 用户在session1质押
        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10 ** 18);
        staking.deposit(session1, 1000 * 10 ** 18);
        vm.stopPrank();

        // 时间前进到session1结束
        vm.warp(block.timestamp + 31 days);

        // 创建第二个session (不重叠)
        uint256 totalReward = 20000 * 10 ** 18;
        uint256 checkInReward = 10000 * 10 ** 18;

        rewardToken.approve(address(staking), totalReward);
        checkInRewardToken.approve(address(staking), checkInReward);

        staking.createSession(
            Staking.CreateSessionParams({
                stakingToken: address(lpToken),
                rewardToken: address(rewardToken),
                checkInRewardToken: address(checkInRewardToken),
                totalReward: totalReward,
                checkInRewardPool: checkInReward,
                startTime: block.timestamp + 1 days,
                endTime: block.timestamp + 31 days
            })
        );

        uint256 session2 = 2;
        assertEq(staking.currentSessionId(), session2);

        // 用户可以提取session1
        vm.prank(user1);
        staking.withdraw(session1);

        // 用户可以参与session2
        vm.warp(block.timestamp + 1 days + 1);
        vm.startPrank(user1);
        lpToken.approve(address(staking), 2000 * 10 ** 18);
        staking.deposit(session2, 2000 * 10 ** 18);
        vm.stopPrank();
    }

    function testUserBoostIndependentAcrossSessions() public {
        // Session 1
        uint256 session1 = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10 ** 18);
        staking.deposit(session1, 1000 * 10 ** 18);
        staking.checkIn(session1);
        vm.warp(block.timestamp + 300);
        staking.checkIn(session1);
        vm.stopPrank();

        // 验证session1的boost
        (,,, uint256 boost1,,,,) = staking.userInfo(session1, user1);
        assertEq(boost1, 2);

        // 等到session1结束
        vm.warp(block.timestamp + 31 days);

        // 创建session2
        uint256 totalReward = 20000 * 10 ** 18;
        uint256 checkInReward = 10000 * 10 ** 18;
        rewardToken.approve(address(staking), totalReward);
        checkInRewardToken.approve(address(staking), checkInReward);

        staking.createSession(
            Staking.CreateSessionParams({
                stakingToken: address(lpToken),
                rewardToken: address(rewardToken),
                checkInRewardToken: address(checkInRewardToken),
                totalReward: totalReward,
                checkInRewardPool: checkInReward,
                startTime: block.timestamp + 1 days,
                endTime: block.timestamp + 31 days
            })
        );

        uint256 session2 = 2;
        vm.warp(block.timestamp + 1 days + 1);

        // 用户在session2质押
        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10 ** 18);
        staking.deposit(session2, 1000 * 10 ** 18);
        vm.stopPrank();

        // 验证session2的boost从0开始
        (,,, uint256 boost2Before,,,,) = staking.userInfo(session2, user1);
        assertEq(boost2Before, 0);

        // 在session2签到
        vm.prank(user1);
        staking.checkIn(session2);

        (,,, uint256 boost2After,,,,) = staking.userInfo(session2, user1);
        assertEq(boost2After, 1);

        // session1的boost不受影响
        (,,, uint256 boost1Final,,,,) = staking.userInfo(session1, user1);
        assertEq(boost1Final, 2);
    }

    // ============================================
    // 测试: 边界情况
    // ============================================

    function testCheckInAtSessionEndTime() public {
        uint256 sessionId = _createTestSession();

        // 获取session信息
        (,,,,,, uint256 endTime,,,,,,,, bool _, uint256 _) = staking.sessions(sessionId);

        // 在session开始时质押
        vm.warp(block.timestamp + 1 days + 1);
        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10 ** 18);
        staking.deposit(sessionId, 1000 * 10 ** 18);

        // 在session结束时签到
        vm.warp(endTime);
        staking.checkIn(sessionId); // 应该成功

        vm.stopPrank();
    }

    function testCheckInAfterSessionEnds() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10 ** 18);
        staking.deposit(sessionId, 1000 * 10 ** 18);

        // session结束后尝试签到
        vm.warp(block.timestamp + 32 days);
        vm.expectRevert("Session ended");
        staking.checkIn(sessionId);

        vm.stopPrank();
    }

    function testWithdrawWithoutCheckIn() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10 ** 18);
        staking.deposit(sessionId, 1000 * 10 ** 18);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        // 没签到不获得boost奖励
        uint256 checkInReward = staking.pendingBoostReward(sessionId, user1);
        assertEq(checkInReward, 0);

        vm.prank(user1);
        staking.withdraw(sessionId);
    }

    function testGetSessionInfo() public {
        uint256 sessionId = _createTestSession();

        Staking.Session memory session = staking.getSessionInfo(sessionId);

        assertEq(session.stakingToken, address(lpToken));
        assertEq(session.rewardToken, address(rewardToken));
        assertEq(session.checkInRewardToken, address(checkInRewardToken));
        assertEq(session.totalReward, 10000 * 10 ** 18);
        assertEq(session.checkInRewardPool, 5000 * 10 ** 18);
        assertTrue(session.active);
    }

    function testGetUserInfo() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10 ** 18);
        staking.deposit(sessionId, 1000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        Staking.UserInfo memory userInfo = staking.getUserInfo(sessionId, user1);

        assertEq(userInfo.amount, 1000 * 10 ** 18);
        assertEq(userInfo.boost, 1);
        assertGt(userInfo.lastCheckInTime, 0);
        assertFalse(userInfo.hasWithdrawn);
    }

    // ============================================
    // 测试: Gas 优化验证
    // ============================================

    function testCheckInGasUsage() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10 ** 18);
        staking.deposit(sessionId, 1000 * 10 ** 18);

        // 测试第一次签到的gas
        uint256 gasBefore = gasleft();
        staking.checkIn(sessionId);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("First checkIn gas used", gasUsed);

        // 测试后续签到的gas
        vm.warp(block.timestamp + 300);
        gasBefore = gasleft();
        staking.checkIn(sessionId);
        gasUsed = gasBefore - gasleft();

        emit log_named_uint("Second checkIn gas used", gasUsed);

        vm.stopPrank();
    }

    // ============================================
    // 测试: 新增 - 全面的 boost 奖励测试
    // ============================================

    /// @notice 测试场景1: 相同质押量,不同boost - 验证hybrid部分分配正确
    function testBoostReward_SameStake_DifferentBoost() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        uint256 stakeAmount = 1000 * 10 ** 18;

        // user1: stake=1000, boost=1
        vm.startPrank(user1);
        lpToken.approve(address(staking), stakeAmount);
        staking.deposit(sessionId, stakeAmount);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // user2: stake=1000, boost=3
        uint256 startTime = block.timestamp;
        vm.startPrank(user2);
        lpToken.approve(address(staking), stakeAmount);
        staking.deposit(sessionId, stakeAmount);
        staking.checkIn(sessionId);
        vm.warp(startTime + 300);
        staking.checkIn(sessionId);
        vm.warp(startTime + 600);
        staking.checkIn(sessionId);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        // 计算预期奖励
        // gamma=0.6, totalBoostPool=5000
        // stakePart = 5000*0.6 = 3000, 每人1500
        // hybridPart = 5000*0.4 = 2000
        // totalBoostPoints = 1+3 = 4
        // user1: sb = (0.5)*(1/4) = 0.125, reward = 2000 * 0.125 / (0.125+0.375) = 2000 * 0.25 = 500
        // user2: sb = (0.5)*(3/4) = 0.375, reward = 2000 * 0.375 / 0.5 = 1500
        // total: user1=1500+500=2000, user2=1500+1500=3000

        uint256 reward1 = staking.pendingBoostReward(sessionId, user1);
        uint256 reward2 = staking.pendingBoostReward(sessionId, user2);

        assertApproxEqRel(reward1, 2000 * 10 ** 18, 0.01e18);
        assertApproxEqRel(reward2, 3000 * 10 ** 18, 0.01e18);
    }

    /// @notice 测试场景2: 不同质押量,相同boost - 验证stake权重占主导
    function testBoostReward_DifferentStake_SameBoost() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        // user1: stake=7000, boost=2
        vm.startPrank(user1);
        lpToken.approve(address(staking), 7000 * 10 ** 18);
        staking.deposit(sessionId, 7000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.warp(block.timestamp + 300);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // user2: stake=3000, boost=2
        vm.startPrank(user2);
        lpToken.approve(address(staking), 3000 * 10 ** 18);
        staking.deposit(sessionId, 3000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.warp(block.timestamp + 300);
        staking.checkIn(sessionId);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        // 预期:
        // stakePart = 3000, user1=2100, user2=900
        // hybridPart = 2000, user1=1400, user2=600
        // total: user1=3500, user2=1500

        uint256 reward1 = staking.pendingBoostReward(sessionId, user1);
        uint256 reward2 = staking.pendingBoostReward(sessionId, user2);

        assertApproxEqRel(reward1, 3500 * 10 ** 18, 0.01e18);
        assertApproxEqRel(reward2, 1500 * 10 ** 18, 0.01e18);
    }

    /// @notice 测试场景3: 极端质押比例(99:1) + 不同boost
    function testBoostReward_ExtremeStakeRatio() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        // user1: stake=9900 (99%), boost=1
        vm.startPrank(user1);
        lpToken.approve(address(staking), 9900 * 10 ** 18);
        staking.deposit(sessionId, 9900 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // user2: stake=100 (1%), boost=10
        vm.startPrank(user2);
        lpToken.approve(address(staking), 100 * 10 ** 18);
        staking.deposit(sessionId, 100 * 10 ** 18);
        for (uint256 i = 0; i < 10; i++) {
            staking.checkIn(sessionId);
            vm.warp(block.timestamp + 300);
        }
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        // 预期:
        // stakePart = 3000, user1=2970, user2=30
        // hybridPart = 2000
        // totalBoostPoints = 11
        // user1: sb = 0.99*(1/11) = 0.09, user2: sb = 0.01*(10/11) = 0.00909
        // user1 hybridReward = 2000 * 0.09 / (0.09+0.00909) ≈ 1816
        // user2 hybridReward = 2000 * 0.00909 / 0.09909 ≈ 184
        // total: user1≈4786, user2≈214

        uint256 reward1 = staking.pendingBoostReward(sessionId, user1);
        uint256 reward2 = staking.pendingBoostReward(sessionId, user2);

        assertApproxEqRel(reward1, 4786 * 10 ** 18, 0.02e18);
        assertApproxEqRel(reward2, 214 * 10 ** 18, 0.02e18);

        // 验证总和接近5000
        assertApproxEqRel(reward1 + reward2, 5000 * 10 ** 18, 0.01e18);
    }

    /// @notice 测试场景4: 中途加入 - 验证boost奖励不受时间影响
    function testBoostReward_MidSessionJoin() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        // user1在session开始时加入
        vm.startPrank(user1);
        lpToken.approve(address(staking), 5000 * 10 ** 18);
        staking.deposit(sessionId, 5000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // 时间过半
        vm.warp(block.timestamp + 15 days);

        // user2在session中途加入
        vm.startPrank(user2);
        lpToken.approve(address(staking), 5000 * 10 ** 18);
        staking.deposit(sessionId, 5000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // 到session结束
        vm.warp(block.timestamp + 16 days);

        // boost奖励不受时间影响,应该相同(都是stake=5000, boost=1)
        uint256 reward1 = staking.pendingBoostReward(sessionId, user1);
        uint256 reward2 = staking.pendingBoostReward(sessionId, user2);

        assertApproxEqRel(reward1, 2500 * 10 ** 18, 0.01e18);
        assertApproxEqRel(reward2, 2500 * 10 ** 18, 0.01e18);
    }

    /// @notice 测试场景5: 用户追加质押 - 验证boost奖励基于最终质押量
    function testBoostReward_AdditionalDeposit() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        // user1初始质押1000并签到
        vm.startPrank(user1);
        lpToken.approve(address(staking), 10000 * 10 ** 18);
        staking.deposit(sessionId, 1000 * 10 ** 18);
        staking.checkIn(sessionId);

        // 追加质押4000
        vm.warp(block.timestamp + 1 days);
        staking.deposit(sessionId, 4000 * 10 ** 18);
        // boost不重置,仍为1
        vm.stopPrank();

        // user2质押5000并签到
        vm.startPrank(user2);
        lpToken.approve(address(staking), 5000 * 10 ** 18);
        staking.deposit(sessionId, 5000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        vm.warp(block.timestamp + 30 days);

        // user1最终: stake=5000, boost=1
        // user2最终: stake=5000, boost=1
        // 应该获得相同的boost奖励
        uint256 reward1 = staking.pendingBoostReward(sessionId, user1);
        uint256 reward2 = staking.pendingBoostReward(sessionId, user2);

        assertApproxEqRel(reward1, 2500 * 10 ** 18, 0.01e18);
        assertApproxEqRel(reward2, 2500 * 10 ** 18, 0.01e18);
    }

    /// @notice 测试场景6: 多用户场景(5用户) - 不同质押和boost组合
    function testBoostReward_MultipleUsers_Complex() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        // user1: stake=2000, boost=1
        vm.startPrank(user1);
        lpToken.approve(address(staking), 2000 * 10 ** 18);
        staking.deposit(sessionId, 2000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // user2: stake=3000, boost=2
        vm.startPrank(user2);
        lpToken.approve(address(staking), 3000 * 10 ** 18);
        staking.deposit(sessionId, 3000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.warp(block.timestamp + 300);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // user3: stake=5000, boost=0 (不签到)
        vm.startPrank(user3);
        lpToken.approve(address(staking), 5000 * 10 ** 18);
        staking.deposit(sessionId, 5000 * 10 ** 18);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        // 计算预期:
        // totalStaked=10000, totalBoostPoints=3
        // stakePart=3000, 按totalStaked分配(包含user3):
        //   user1: 3000 * (2000/10000) = 600
        //   user2: 3000 * (3000/10000) = 900
        //   user3: 0 (不签到)
        // hybridPart=2000, 只在签到用户间分配:
        //   user1: 2000 * (1/3) = 666.67
        //   user2: 2000 * (2/3) = 1333.33

        uint256 reward1 = staking.pendingBoostReward(sessionId, user1);
        uint256 reward2 = staking.pendingBoostReward(sessionId, user2);
        uint256 reward3 = staking.pendingBoostReward(sessionId, user3);

        assertApproxEqRel(reward1, 1100 * 10 ** 18, 0.02e18); // 600+500实际约=1100
        assertApproxEqRel(reward2, 2400 * 10 ** 18, 0.02e18); // 900+1500实际约=2400
        assertEq(reward3, 0); // 不签到,不获得boost奖励

        // 验证总和(仅user1和user2,不含user3未分配的部分)
        assertApproxEqRel(reward1 + reward2, 3500 * 10 ** 18, 0.02e18);
    }

    /// @notice 测试场景7: 实时查询 - 验证中途签到影响其他用户预估奖励
    function testBoostReward_RealtimeQuery_AffectedByOthers() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        // user1: stake=5000, boost=1
        vm.startPrank(user1);
        lpToken.approve(address(staking), 5000 * 10 ** 18);
        staking.deposit(sessionId, 5000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // user2: stake=5000, boost=1
        vm.startPrank(user2);
        lpToken.approve(address(staking), 5000 * 10 ** 18);
        staking.deposit(sessionId, 5000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // 此时user1和user2预估奖励应该相同
        uint256 reward1Before = staking.pendingBoostReward(sessionId, user1);
        uint256 reward2Before = staking.pendingBoostReward(sessionId, user2);
        assertApproxEqRel(reward1Before, reward2Before, 0.001e18);

        // user2再签到1次
        vm.warp(block.timestamp + 300);
        vm.prank(user2);
        staking.checkIn(sessionId);

        // 现在user2的boost=2, user1的预估奖励应该减少
        uint256 reward1After = staking.pendingBoostReward(sessionId, user1);
        uint256 reward2After = staking.pendingBoostReward(sessionId, user2);

        assertLt(reward1After, reward1Before); // user1奖励减少
        assertGt(reward2After, reward2Before); // user2奖励增加
    }

    /// @notice 测试场景8: gamma=0.5 - 验证不同gamma参数
    function testBoostReward_GammaHalf() public {
        uint256 sessionId = _createTestSession();
        staking.setGamma(sessionId, 5e17); // 0.5

        vm.warp(block.timestamp + 1 days + 1);

        // user1: stake=6000, boost=1
        vm.startPrank(user1);
        lpToken.approve(address(staking), 6000 * 10 ** 18);
        staking.deposit(sessionId, 6000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // user2: stake=4000, boost=2
        vm.startPrank(user2);
        lpToken.approve(address(staking), 4000 * 10 ** 18);
        staking.deposit(sessionId, 4000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.warp(block.timestamp + 300);
        staking.checkIn(sessionId);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        // gamma=0.5
        // stakePart=2500: user1=1500, user2=1000
        // hybridPart=2500
        // totalBoostPoints=3
        // user1: sb=0.6*(1/3)=0.2, user2: sb=0.4*(2/3)=0.2667
        // sumSB=0.4667
        // user1 hybrid=2500*0.2/0.4667=1071
        // user2 hybrid=2500*0.2667/0.4667=1429
        // total: user1=2571, user2=2429

        uint256 reward1 = staking.pendingBoostReward(sessionId, user1);
        uint256 reward2 = staking.pendingBoostReward(sessionId, user2);

        assertApproxEqRel(reward1, 2571 * 10 ** 18, 0.02e18);
        assertApproxEqRel(reward2, 2429 * 10 ** 18, 0.02e18);
    }

    /// @notice 测试场景9: 所有用户都不签到 - 验证fallback逻辑
    function testBoostReward_AllUsersNoCheckIn() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        // user1: stake=7000, boost=0
        vm.startPrank(user1);
        lpToken.approve(address(staking), 7000 * 10 ** 18);
        staking.deposit(sessionId, 7000 * 10 ** 18);
        vm.stopPrank();

        // user2: stake=3000, boost=0
        vm.startPrank(user2);
        lpToken.approve(address(staking), 3000 * 10 ** 18);
        staking.deposit(sessionId, 3000 * 10 ** 18);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        // 没人签到,都不获得boost奖励
        uint256 reward1 = staking.pendingBoostReward(sessionId, user1);
        uint256 reward2 = staking.pendingBoostReward(sessionId, user2);

        assertEq(reward1, 0);
        assertEq(reward2, 0);
    }

    /// @notice 测试场景10: 精度测试 - 极小金额质押
    function testBoostReward_SmallAmount() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        // user1: stake=1 wei, boost=1
        vm.startPrank(user1);
        lpToken.approve(address(staking), 1);
        staking.deposit(sessionId, 1);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // user2: stake=10000e18, boost=1
        vm.startPrank(user2);
        lpToken.approve(address(staking), 10000 * 10 ** 18);
        staking.deposit(sessionId, 10000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        uint256 reward1 = staking.pendingBoostReward(sessionId, user1);
        uint256 reward2 = staking.pendingBoostReward(sessionId, user2);

        // user1几乎拿不到奖励,user2拿走几乎全部
        assertLt(reward1, 1e10); // 非常小
        assertApproxEqRel(reward2, 5000 * 10 ** 18, 0.001e18);
    }

    /// @notice 测试场景11: 复杂场景 - 用户持续签到累积boost
    function testBoostReward_ContinuousCheckIn() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        // user1: stake=5000, 持续签到10次
        vm.startPrank(user1);
        lpToken.approve(address(staking), 5000 * 10 ** 18);
        staking.deposit(sessionId, 5000 * 10 ** 18);
        for (uint256 i = 0; i < 10; i++) {
            staking.checkIn(sessionId);
            vm.warp(block.timestamp + 300);
        }
        vm.stopPrank();

        // user2: stake=5000, 签到1次
        vm.startPrank(user2);
        lpToken.approve(address(staking), 5000 * 10 ** 18);
        staking.deposit(sessionId, 5000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        // user1: boost=10, user2: boost=1
        // totalBoostPoints=11
        // stakePart=3000: 各1500
        // hybridPart=2000
        // user1: sb=0.5*(10/11)=0.4545, user2: sb=0.5*(1/11)=0.0455
        // user1 hybrid=2000*0.4545/0.5=1818
        // user2 hybrid=2000*0.0455/0.5=182
        // total: user1=3318, user2=1682

        uint256 reward1 = staking.pendingBoostReward(sessionId, user1);
        uint256 reward2 = staking.pendingBoostReward(sessionId, user2);

        assertApproxEqRel(reward1, 3318 * 10 ** 18, 0.02e18);
        assertApproxEqRel(reward2, 1682 * 10 ** 18, 0.02e18);
    }

    /// @notice 测试场景12: 验证getPendingRewards分开显示
    function testGetPendingRewards_SeparateDisplay() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 5000 * 10 ** 18);
        staking.deposit(sessionId, 5000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // 中途查询
        vm.warp(block.timestamp + 15 days);
        (uint256 stakingReward, uint256 boostReward) = staking.getPendingRewards(sessionId, user1);

        // LP奖励应该约为一半(线性释放)
        assertApproxEqRel(stakingReward, 5000 * 10 ** 18, 0.05e18);
        // boost奖励应该是全部(不按时间释放)
        assertApproxEqRel(boostReward, 5000 * 10 ** 18, 0.01e18);

        // session结束后查询
        vm.warp(block.timestamp + 16 days);
        (uint256 stakingRewardFinal, uint256 boostRewardFinal) = staking.getPendingRewards(sessionId, user1);

        assertApproxEqRel(stakingRewardFinal, 10000 * 10 ** 18, 0.01e18);
        assertApproxEqRel(boostRewardFinal, 5000 * 10 ** 18, 0.01e18);
    }

    /// @notice 测试场景13: sumSB1e18精度验证
    function testBoostReward_SumSBPrecision() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        // 创建一个会导致大数值相乘的场景
        // user1: stake=1000, boost=100
        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10 ** 18);
        staking.deposit(sessionId, 1000 * 10 ** 18);
        for (uint256 i = 0; i < 100; i++) {
            staking.checkIn(sessionId);
            vm.warp(block.timestamp + 300);
        }
        vm.stopPrank();

        // user2: stake=9000, boost=1
        vm.startPrank(user2);
        lpToken.approve(address(staking), 9000 * 10 ** 18);
        staking.deposit(sessionId, 9000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        uint256 reward1 = staking.pendingBoostReward(sessionId, user1);
        uint256 reward2 = staking.pendingBoostReward(sessionId, user2);

        // 验证总和为5000(精度测试)
        assertApproxEqRel(reward1 + reward2, 5000 * 10 ** 18, 0.01e18);

        // user1虽然boost很高,但stake占比小,不应该拿走全部
        assertLt(reward1, 3000 * 10 ** 18);
        assertGt(reward2, 2000 * 10 ** 18);
    }

    // ============================================
    // 测试: totalReward守恒性和boostReward逻辑
    // ============================================

    /// @notice 测试所有用户的LP奖励总和等于totalReward
    function testTotalRewardConservation() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        // 3个用户,不同时间点质押不同次数
        // user1: 质押2次
        vm.startPrank(user1);
        lpToken.approve(address(staking), 100 * 10 ** 18);
        staking.deposit(sessionId, 30 * 10 ** 18);
        vm.warp(block.timestamp + 1000);
        staking.deposit(sessionId, 20 * 10 ** 18);
        vm.stopPrank();

        // user2: 质押1次
        vm.startPrank(user2);
        lpToken.approve(address(staking), 50 * 10 ** 18);
        staking.deposit(sessionId, 50 * 10 ** 18);
        vm.stopPrank();

        // user3: 质押3次
        vm.startPrank(user3);
        lpToken.approve(address(staking), 100 * 10 ** 18);
        staking.deposit(sessionId, 10 * 10 ** 18);
        vm.warp(block.timestamp + 500);
        staking.deposit(sessionId, 15 * 10 ** 18);
        vm.warp(block.timestamp + 500);
        staking.deposit(sessionId, 25 * 10 ** 18);
        vm.stopPrank();

        // 等到session结束
        vm.warp(block.timestamp + 31 days);

        // 查询所有用户的LP奖励
        (uint256 reward1,) = staking.getPendingRewards(sessionId, user1);
        (uint256 reward2,) = staking.getPendingRewards(sessionId, user2);
        (uint256 reward3,) = staking.getPendingRewards(sessionId, user3);

        uint256 totalDistributed = reward1 + reward2 + reward3;
        uint256 totalReward = 10000 * 10 ** 18;

        // 验证守恒性:所有用户的LP奖励总和 = totalReward
        assertApproxEqRel(totalDistributed, totalReward, 0.001e18, "Total rewards should equal totalReward");
    }

    /// @notice 测试复存会增加自己的boostReward份额(多用户场景)
    function testDepositIncreasesBoostReward() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        // user2先质押签到,作为竞争者
        vm.startPrank(user2);
        lpToken.approve(address(staking), 50 * 10 ** 18);
        staking.deposit(sessionId, 50 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // user1质押签到
        vm.startPrank(user1);
        lpToken.approve(address(staking), 100 * 10 ** 18);
        staking.deposit(sessionId, 30 * 10 ** 18);
        vm.warp(block.timestamp + 300);
        staking.checkIn(sessionId);

        // 记录第一次的boostReward
        uint256 boostBefore = staking.pendingBoostReward(sessionId, user1);
        (uint256 stakeBefore, uint256 hybridBefore) = staking.getBoostRewardBreakdown(sessionId, user1);

        // 第二次质押(复存)
        vm.warp(block.timestamp + 300);
        staking.deposit(sessionId, 20 * 10 ** 18);

        // 复存后boostReward应该增加(因为质押量增加了)
        uint256 boostAfter = staking.pendingBoostReward(sessionId, user1);
        (uint256 stakeAfter, uint256 hybridAfter) = staking.getBoostRewardBreakdown(sessionId, user1);

        assertGt(boostAfter, boostBefore, "Boost reward should increase after additional deposit");
        assertGt(stakeAfter, stakeBefore, "Stake reward should increase (more stake)");
        assertGt(hybridAfter, hybridBefore, "Hybrid reward should increase (more stake weight)");

        vm.stopPrank();
    }

    /// @notice 测试签到会增加boostReward的hybridReward部分(多用户场景)
    function testCheckInIncreasesBoostReward() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        // user2先质押签到,作为竞争者
        vm.startPrank(user2);
        lpToken.approve(address(staking), 50 * 10 ** 18);
        staking.deposit(sessionId, 50 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // user1质押签到
        vm.startPrank(user1);
        lpToken.approve(address(staking), 50 * 10 ** 18);
        staking.deposit(sessionId, 50 * 10 ** 18);

        // 第一次签到
        staking.checkIn(sessionId);
        uint256 boost1 = staking.pendingBoostReward(sessionId, user1);
        (uint256 stake1, uint256 hybrid1) = staking.getBoostRewardBreakdown(sessionId, user1);

        // 第二次签到
        vm.warp(block.timestamp + 300);
        staking.checkIn(sessionId);
        uint256 boost2 = staking.pendingBoostReward(sessionId, user1);
        (uint256 stake2, uint256 hybrid2) = staking.getBoostRewardBreakdown(sessionId, user1);

        // boostReward应该增加
        assertGt(boost2, boost1, "Boost reward should increase after second check-in");

        // stakeReward不变(只和质押量有关)
        assertEq(stake2, stake1, "Stake reward should not change (only depends on amount)");

        // hybridReward增加(和boost有关)
        assertGt(hybrid2, hybrid1, "Hybrid reward should increase (depends on boost)");

        vm.stopPrank();
    }

    /// @notice 测试复存+签到的组合效果(多用户场景)
    function testDepositAndCheckInCombinedEffect() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        // user2先质押签到,作为竞争者
        vm.startPrank(user2);
        lpToken.approve(address(staking), 50 * 10 ** 18);
        staking.deposit(sessionId, 50 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // user1质押签到
        vm.startPrank(user1);
        lpToken.approve(address(staking), 100 * 10 ** 18);

        // 初始状态:质押+签到
        staking.deposit(sessionId, 20 * 10 ** 18);
        vm.warp(block.timestamp + 300);
        staking.checkIn(sessionId);
        uint256 boostInitial = staking.pendingBoostReward(sessionId, user1);

        // 复存后boost增加
        vm.warp(block.timestamp + 300);
        staking.deposit(sessionId, 30 * 10 ** 18);
        uint256 boostAfterDeposit = staking.pendingBoostReward(sessionId, user1);
        assertGt(boostAfterDeposit, boostInitial, "Deposit should increase boost");

        // 再签到后boost继续增加
        vm.warp(block.timestamp + 300);
        staking.checkIn(sessionId);
        uint256 boostAfterCheckIn = staking.pendingBoostReward(sessionId, user1);
        assertGt(boostAfterCheckIn, boostAfterDeposit, "CheckIn should further increase boost");

        vm.stopPrank();
    }

    // ============================================
    // 测试: getBoostRewardBreakdown函数
    // ============================================

    /// @notice 测试getBoostRewardBreakdown - 验证stakeReward和hybridReward拆分正确
    function testGetBoostRewardBreakdown_Basic() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        // user1: stake=6000, boost=1
        vm.startPrank(user1);
        lpToken.approve(address(staking), 6000 * 10 ** 18);
        staking.deposit(sessionId, 6000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // user2: stake=4000, boost=2
        vm.startPrank(user2);
        lpToken.approve(address(staking), 4000 * 10 ** 18);
        staking.deposit(sessionId, 4000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.warp(block.timestamp + 300);
        staking.checkIn(sessionId);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        // 获取breakdown
        (uint256 stakeReward1, uint256 hybridReward1) = staking.getBoostRewardBreakdown(sessionId, user1);
        (uint256 stakeReward2, uint256 hybridReward2) = staking.getBoostRewardBreakdown(sessionId, user2);

        // 计算预期值
        // gamma=0.6, totalBoostPool=5000
        // stakePart = 5000*0.6 = 3000
        // user1 stakeReward = 3000*0.6 = 1800
        // user2 stakeReward = 3000*0.4 = 1200

        // hybridPart = 5000*0.4 = 2000
        // totalBoostPoints = 3
        // user1: sb = 0.6*(1/3) = 0.2, hybridReward = 2000*0.2/0.4667 = 857.14
        // user2: sb = 0.4*(2/3) = 0.2667, hybridReward = 2000*0.2667/0.4667 = 1142.86

        assertApproxEqRel(stakeReward1, 1800 * 10 ** 18, 0.01e18);
        assertApproxEqRel(hybridReward1, 857142857142857142857, 0.02e18);

        assertApproxEqRel(stakeReward2, 1200 * 10 ** 18, 0.01e18);
        assertApproxEqRel(hybridReward2, 1142857142857142857142, 0.02e18);

        // 验证总和等于pendingBoostReward
        uint256 totalReward1 = staking.pendingBoostReward(sessionId, user1);
        uint256 totalReward2 = staking.pendingBoostReward(sessionId, user2);

        assertEq(stakeReward1 + hybridReward1, totalReward1);
        assertEq(stakeReward2 + hybridReward2, totalReward2);
    }

    /// @notice 测试getBoostRewardBreakdown - 没有签到的用户
    function testGetBoostRewardBreakdown_NoCheckIn() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        // user1质押但不签到
        vm.startPrank(user1);
        lpToken.approve(address(staking), 5000 * 10 ** 18);
        staking.deposit(sessionId, 5000 * 10 ** 18);
        vm.stopPrank();

        // user2质押并签到
        vm.startPrank(user2);
        lpToken.approve(address(staking), 5000 * 10 ** 18);
        staking.deposit(sessionId, 5000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        // user1没有签到,应该返回(0, 0)
        (uint256 stakeReward1, uint256 hybridReward1) = staking.getBoostRewardBreakdown(sessionId, user1);
        assertEq(stakeReward1, 0);
        assertEq(hybridReward1, 0);

        // user2有签到
        (uint256 stakeReward2, uint256 hybridReward2) = staking.getBoostRewardBreakdown(sessionId, user2);

        // stakePart = 3000, user2获得1500
        // hybridPart = 2000, user2全部获得(user1因为boost=0不参与)
        assertApproxEqRel(stakeReward2, 1500 * 10 ** 18, 0.01e18);
        assertApproxEqRel(hybridReward2, 2000 * 10 ** 18, 0.01e18);

        // 总和应该是3500
        assertApproxEqRel(stakeReward2 + hybridReward2, 3500 * 10 ** 18, 0.01e18);
    }

    /// @notice 测试getBoostRewardBreakdown - gamma=0时全部是hybrid
    function testGetBoostRewardBreakdown_GammaZero() public {
        uint256 sessionId = _createTestSession();
        staking.setGamma(sessionId, 0); // gamma=0

        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 5000 * 10 ** 18);
        staking.deposit(sessionId, 5000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        (uint256 stakeReward, uint256 hybridReward) = staking.getBoostRewardBreakdown(sessionId, user1);

        // gamma=0时,stakeReward应该为0,hybridReward应该是全部
        assertEq(stakeReward, 0);
        assertApproxEqRel(hybridReward, 5000 * 10 ** 18, 0.01e18);
    }

    /// @notice 测试getBoostRewardBreakdown - gamma=1时全部是stake
    function testGetBoostRewardBreakdown_GammaOne() public {
        uint256 sessionId = _createTestSession();
        staking.setGamma(sessionId, 1e18); // gamma=1

        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 5000 * 10 ** 18);
        staking.deposit(sessionId, 5000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        (uint256 stakeReward, uint256 hybridReward) = staking.getBoostRewardBreakdown(sessionId, user1);

        // gamma=1时,stakeReward应该是全部,hybridReward应该为0
        assertApproxEqRel(stakeReward, 5000 * 10 ** 18, 0.01e18);
        assertEq(hybridReward, 0);
    }

    /// @notice 测试getBoostRewardBreakdown - 多用户复杂场景
    function testGetBoostRewardBreakdown_MultipleUsers() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        // user1: stake=2000, boost=1
        vm.startPrank(user1);
        lpToken.approve(address(staking), 2000 * 10 ** 18);
        staking.deposit(sessionId, 2000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // user2: stake=3000, boost=2
        vm.startPrank(user2);
        lpToken.approve(address(staking), 3000 * 10 ** 18);
        staking.deposit(sessionId, 3000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.warp(block.timestamp + 300);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // user3: stake=5000, boost=3
        vm.startPrank(user3);
        lpToken.approve(address(staking), 5000 * 10 ** 18);
        staking.deposit(sessionId, 5000 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.warp(block.timestamp + 300);
        staking.checkIn(sessionId);
        vm.warp(block.timestamp + 300);
        staking.checkIn(sessionId);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        (uint256 stake1, uint256 hybrid1) = staking.getBoostRewardBreakdown(sessionId, user1);
        (uint256 stake2, uint256 hybrid2) = staking.getBoostRewardBreakdown(sessionId, user2);
        (uint256 stake3, uint256 hybrid3) = staking.getBoostRewardBreakdown(sessionId, user3);

        // 验证stake部分按质押比例分配
        // totalStaked=10000, stakePart=3000
        assertApproxEqRel(stake1, 600 * 10 ** 18, 0.01e18); // 2000/10000 * 3000 = 600
        assertApproxEqRel(stake2, 900 * 10 ** 18, 0.01e18); // 3000/10000 * 3000 = 900
        assertApproxEqRel(stake3, 1500 * 10 ** 18, 0.01e18); // 5000/10000 * 3000 = 1500

        // 验证hybrid部分
        assertGt(hybrid1, 0);
        assertGt(hybrid2, 0);
        assertGt(hybrid3, 0);

        // 验证所有奖励总和等于5000
        uint256 totalStake = stake1 + stake2 + stake3;
        uint256 totalHybrid = hybrid1 + hybrid2 + hybrid3;
        assertApproxEqRel(totalStake + totalHybrid, 5000 * 10 ** 18, 0.01e18);

        // 验证与pendingBoostReward一致
        assertEq(stake1 + hybrid1, staking.pendingBoostReward(sessionId, user1));
        assertEq(stake2 + hybrid2, staking.pendingBoostReward(sessionId, user2));
        assertEq(stake3 + hybrid3, staking.pendingBoostReward(sessionId, user3));
    }

    /// @notice 测试getBoostRewardBreakdown - 没有质押
    function testGetBoostRewardBreakdown_NoStake() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        // user1没有质押
        (uint256 stakeReward, uint256 hybridReward) = staking.getBoostRewardBreakdown(sessionId, user1);

        assertEq(stakeReward, 0);
        assertEq(hybridReward, 0);
    }

    // ============================================
    // 辅助函数
    // ============================================

    function _createTestSession() internal returns (uint256) {
        uint256 totalReward = 10000 * 10 ** 18;
        uint256 checkInReward = 5000 * 10 ** 18;
        uint256 startTime = block.timestamp + 1 days;
        uint256 endTime = startTime + 30 days;

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

        return staking.currentSessionId();
    }

    receive() external payable {}

    /// @notice 测试第一个签到的人不能获得100%的checkInRewardPool
    function testFirstCheckInDoesNotGet100Percent() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        // user1和user2都质押50%
        vm.startPrank(user1);
        lpToken.approve(address(staking), 50 * 10 ** 18);
        staking.deposit(sessionId, 50 * 10 ** 18);
        vm.stopPrank();

        vm.startPrank(user2);
        lpToken.approve(address(staking), 50 * 10 ** 18);
        staking.deposit(sessionId, 50 * 10 ** 18);
        vm.stopPrank();

        // 只有user1签到
        vm.prank(user1);
        staking.checkIn(sessionId);

        // 查询user1的boostReward
        uint256 boostReward1 = staking.pendingBoostReward(sessionId, user1);
        uint256 totalPool = 5000 * 10 ** 18;

        // user1不能获得100%
        assertLt(boostReward1, totalPool, "First check-in should NOT get 100% of pool");

        // 根据公式,user1应该获得3500 (stakeReward=1500 + hybridReward=2000)
        assertApproxEqRel(boostReward1, 3500 * 10 ** 18, 0.01e18, "Should get 3500 (70%)");
    }

    /// @notice 测试第二个人签到后,第一个人的boostReward会减少
    function testSecondCheckInReducesFirstUserReward() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        // 两个用户都先质押(但只有user1签到)
        vm.startPrank(user1);
        lpToken.approve(address(staking), 50 * 10 ** 18);
        staking.deposit(sessionId, 50 * 10 ** 18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        vm.startPrank(user2);
        lpToken.approve(address(staking), 50 * 10 ** 18);
        staking.deposit(sessionId, 50 * 10 ** 18);
        vm.stopPrank();

        // 记录user1第一次的boostReward (此时只有user1签到)
        uint256 boostBefore = staking.pendingBoostReward(sessionId, user1);
        (uint256 stakeBefore, uint256 hybridBefore) = staking.getBoostRewardBreakdown(sessionId, user1);

        // user2签到
        vm.warp(block.timestamp + 300);
        vm.prank(user2);
        staking.checkIn(sessionId);

        // 查询user1的新boostReward
        uint256 boostAfter = staking.pendingBoostReward(sessionId, user1);
        (uint256 stakeAfter, uint256 hybridAfter) = staking.getBoostRewardBreakdown(sessionId, user1);

        // user1的boostReward应该减少
        assertLt(boostAfter, boostBefore, "User1 boost reward should DECREASE after user2 checks in");

        // stakeReward不变(两人都已质押,totalStaked不变)
        assertEq(stakeAfter, stakeBefore, "Stake reward should not change");

        // hybridReward减少(因为要和user2分享)
        assertLt(hybridAfter, hybridBefore, "Hybrid reward should decrease (now shared with user2)");

        // 具体数值验证:
        // Before: stake=1500, hybrid=2000, total=3500
        // After:  stake=1500, hybrid=1000, total=2500
        assertApproxEqRel(boostBefore, 3500 * 10 ** 18, 0.01e18, "Before: should be 3500");
        assertApproxEqRel(boostAfter, 2500 * 10 ** 18, 0.01e18, "After: should be 2500");
    }
}
