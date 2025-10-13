// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/Staking.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Mock ERC20 Token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10**18);
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

    uint256 constant INITIAL_BALANCE = 1000000 * 10**18;
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
        uint256 totalReward = 10000 * 10**18;
        uint256 checkInReward = 5000 * 10**18;
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
            uint256 _endTime,
            ,,,,,
        ) = staking.sessions(1);

        assertEq(stakingToken, address(lpToken));
        assertEq(_rewardToken, address(rewardToken));
        assertEq(_checkInRewardToken, address(checkInRewardToken));
        assertEq(_totalReward, totalReward);
        assertEq(_checkInRewardPool, checkInReward);
        assertEq(_startTime, startTime);
        assertEq(_endTime, endTime);
    }

    function testCreateSessionWithBNB() public {
        uint256 totalReward = 10 ether;
        uint256 checkInReward = 5 ether;
        uint256 startTime = block.timestamp + 1 days;
        uint256 endTime = startTime + 30 days;

        // 创建BNB session
        staking.createSession{value: totalReward + checkInReward}(
            Staking.CreateSessionParams({
                stakingToken: address(lpToken),
                rewardToken: address(0), // BNB as reward
                checkInRewardToken: address(0), // BNB as checkIn reward
                totalReward: totalReward,
                checkInRewardPool: checkInReward,
                startTime: startTime,
                endTime: endTime
            })
        );

        assertEq(staking.currentSessionId(), 1);
    }

    function testCannotCreateSessionWithOverlappingTime() public {
        uint256 totalReward = 10000 * 10**18;
        uint256 checkInReward = 5000 * 10**18;

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
        uint256 totalReward = 10000 * 10**18;
        uint256 checkInReward = 5000 * 10**18;

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
        uint256 depositAmount = 1000 * 10**18;
        vm.startPrank(user1);
        lpToken.approve(address(staking), depositAmount);
        staking.deposit(sessionId, depositAmount);
        vm.stopPrank();

        // 验证
        (uint256 amount,,,, ) = staking.userInfo(sessionId, user1);
        assertEq(amount, depositAmount);
    }

    function testDepositBNB() public {
        // 创建BNB质押session
        uint256 sessionId = _createBNBStakingSession();

        // 时间前进到session开始
        vm.warp(block.timestamp + 1 days + 1);

        // 用户1质押BNB
        uint256 depositAmount = 1 ether;
        vm.prank(user1);
        staking.deposit{value: depositAmount}(sessionId, depositAmount);

        // 验证
        (uint256 amount,,,, ) = staking.userInfo(sessionId, user1);
        assertEq(amount, depositAmount);
    }

    function testCannotDepositBeforeSessionStarts() public {
        uint256 sessionId = _createTestSession();

        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10**18);
        vm.expectRevert("Session not started");
        staking.deposit(sessionId, 1000 * 10**18);
        vm.stopPrank();
    }

    function testCannotDepositAfterSessionEnds() public {
        uint256 sessionId = _createTestSession();

        // 时间前进到session结束后
        vm.warp(block.timestamp + 32 days);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10**18);
        vm.expectRevert("Session ended");
        staking.deposit(sessionId, 1000 * 10**18);
        vm.stopPrank();
    }

    function testMultipleDeposits() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        uint256 firstDeposit = 500 * 10**18;
        uint256 secondDeposit = 300 * 10**18;

        vm.startPrank(user1);
        lpToken.approve(address(staking), firstDeposit + secondDeposit);

        staking.deposit(sessionId, firstDeposit);
        staking.deposit(sessionId, secondDeposit);

        vm.stopPrank();

        (uint256 amount,,,, ) = staking.userInfo(sessionId, user1);
        assertEq(amount, firstDeposit + secondDeposit);
    }

    function testDepositDoesNotResetBoost() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 2000 * 10**18);

        // 第一次质押
        staking.deposit(sessionId, 1000 * 10**18);

        // 签到
        staking.checkIn(sessionId);

        // 等待5分钟后再次签到
        vm.warp(block.timestamp + 301);
        staking.checkIn(sessionId);

        // 验证boost = 2
        (, , uint256 boostBefore, , ) = staking.userInfo(sessionId, user1);
        assertEq(boostBefore, 2);

        // 第二次质押 (复存)
        staking.deposit(sessionId, 1000 * 10**18);

        // 验证boost没有被重置
        (, , uint256 boostAfter, , ) = staking.userInfo(sessionId, user1);
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
        lpToken.approve(address(staking), 1000 * 10**18);
        staking.deposit(sessionId, 1000 * 10**18);

        // 首次签到
        vm.expectEmit(true, true, false, true);
        emit CheckedIn(sessionId, user1, block.timestamp);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // 验证
        (, , uint256 boost, uint40 lastCheckInTime, ) = staking.userInfo(sessionId, user1);
        assertEq(boost, 1);
        assertEq(lastCheckInTime, block.timestamp);
    }

    function testCheckInMultipleTimes() public {
        uint256 sessionId = _createTestSession();
        uint256 startTime = block.timestamp + 1 days + 1;
        vm.warp(startTime);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10**18);
        staking.deposit(sessionId, 1000 * 10**18);

        // 第1次签到
        staking.checkIn(sessionId);
        (, , uint256 boost1, , ) = staking.userInfo(sessionId, user1);
        assertEq(boost1, 1);

        // 等待5分钟后第2次签到
        vm.warp(startTime + 300);
        staking.checkIn(sessionId);
        (, , uint256 boost2, , ) = staking.userInfo(sessionId, user1);
        assertEq(boost2, 2);

        // 等待5分钟后第3次签到
        vm.warp(startTime + 600);
        staking.checkIn(sessionId);
        (, , uint256 boost3, , ) = staking.userInfo(sessionId, user1);
        assertEq(boost3, 3);

        // 等待更长时间后第4次签到
        vm.warp(startTime + 1600);
        staking.checkIn(sessionId);
        (, , uint256 boost4, , ) = staking.userInfo(sessionId, user1);
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
        lpToken.approve(address(staking), 1000 * 10**18);
        staking.deposit(sessionId, 1000 * 10**18);

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
        lpToken.approve(address(staking), 1000 * 10**18);
        staking.deposit(sessionId, 1000 * 10**18);

        uint256 firstCheckInTime = block.timestamp;
        staking.checkIn(sessionId);

        // 等待刚好300秒
        vm.warp(firstCheckInTime + 300);
        staking.checkIn(sessionId); // 应该成功

        (, , uint256 boost, , ) = staking.userInfo(sessionId, user1);
        assertEq(boost, 2);

        vm.stopPrank();
    }

    function testMultipleUsersCheckInIndependently() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        // 用户1质押和签到
        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10**18);
        staking.deposit(sessionId, 1000 * 10**18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // 用户2在2分钟后质押和签到
        vm.warp(block.timestamp + 120);
        vm.startPrank(user2);
        lpToken.approve(address(staking), 2000 * 10**18);
        staking.deposit(sessionId, 2000 * 10**18);
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
        (, , uint256 boost1, , ) = staking.userInfo(sessionId, user1);
        (, , uint256 boost2, , ) = staking.userInfo(sessionId, user2);
        assertEq(boost1, 2);
        assertEq(boost2, 1);
    }

    function testCheckInBoostAccumulatesOverTime() public {
        uint256 sessionId = _createTestSession();
        uint256 startTime = block.timestamp + 1 days + 1;
        vm.warp(startTime);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10**18);
        staking.deposit(sessionId, 1000 * 10**18);

        // 模拟一天内多次签到 (每5分钟一次)
        for (uint256 i = 0; i < 10; i++) {
            staking.checkIn(sessionId);
            vm.warp(startTime + (300 * (i + 1)));
        }

        (, , uint256 finalBoost, , ) = staking.userInfo(sessionId, user1);
        assertEq(finalBoost, 10);

        vm.stopPrank();
    }

    // ============================================
    // 测试: withdraw
    // ============================================

    function testWithdraw() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        uint256 depositAmount = 1000 * 10**18;

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
        lpToken.approve(address(staking), 1000 * 10**18);
        staking.deposit(sessionId, 1000 * 10**18);

        vm.expectRevert("Session not ended yet");
        staking.withdraw(sessionId);
        vm.stopPrank();
    }

    function testCannotWithdrawTwice() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10**18);
        staking.deposit(sessionId, 1000 * 10**18);
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

        uint256 user1Deposit = 6000 * 10**18; // 60%
        uint256 user2Deposit = 4000 * 10**18; // 40%

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

        // 验证用户1获得了签到奖励
        assertGt(checkInRewardToken.balanceOf(user1), beforeCheckInReward);

        // 用户2提取
        uint256 user2CheckInRewardBefore = checkInRewardToken.balanceOf(user2);
        vm.prank(user2);
        staking.withdraw(sessionId);

        // 验证用户2没有签到奖励 (boost = 0)
        assertEq(checkInRewardToken.balanceOf(user2), user2CheckInRewardBefore);
    }

    function testWithdrawWithMultipleCheckIns() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        uint256 user1Deposit = 5000 * 10**18;
        uint256 user2Deposit = 5000 * 10**18;

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
        uint256 user1CheckIn = staking.pendingCheckInReward(sessionId, user1);
        uint256 user2CheckIn = staking.pendingCheckInReward(sessionId, user2);

        // 用户2的签到奖励应该是用户1的2倍 (相同质押量，但boost是2倍)
        assertApproxEqRel(user2CheckIn, user1CheckIn * 2, 0.01e18);
    }

    // ============================================
    // 测试: 奖励计算
    // ============================================

    function testRewardCalculation() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        uint256 user1Deposit = 6000 * 10**18;
        uint256 user2Deposit = 4000 * 10**18;

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
        assertApproxEqRel(user1Pending, 6000 * 10**18, 0.01e18); // 1% tolerance
        assertApproxEqRel(user2Pending, 4000 * 10**18, 0.01e18);
    }

    function testCheckInRewardCalculation() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        uint256 user1Deposit = 6000 * 10**18;
        uint256 user2Deposit = 4000 * 10**18;

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
        uint256 user1CheckIn = staking.pendingCheckInReward(sessionId, user1);
        uint256 user2CheckIn = staking.pendingCheckInReward(sessionId, user2);

        // 用户1应该获得60%的签到奖励，用户2获得40%
        assertApproxEqRel(user1CheckIn, 3000 * 10**18, 0.01e18);
        assertApproxEqRel(user2CheckIn, 2000 * 10**18, 0.01e18);
    }

    function testCheckInRewardWithDifferentBoosts() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        uint256 depositAmount = 1000 * 10**18;

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
        uint256 reward1 = staking.pendingCheckInReward(sessionId, user1);
        uint256 reward2 = staking.pendingCheckInReward(sessionId, user2);
        uint256 reward3 = staking.pendingCheckInReward(sessionId, user3);

        // 总加权 = 1000*1 + 1000*2 + 1000*3 = 6000
        // user1应得: 5000 * 1000/6000 = 833.33
        // user2应得: 5000 * 2000/6000 = 1666.66
        // user3应得: 5000 * 3000/6000 = 2500

        assertApproxEqRel(reward1, 833333333333333333333, 0.01e18);
        assertApproxEqRel(reward2, 1666666666666666666666, 0.01e18);
        assertApproxEqRel(reward3, 2500 * 10**18, 0.01e18);
    }

    function testPendingRewardBeforeSessionEnds() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10**18);
        staking.deposit(sessionId, 1000 * 10**18);
        vm.stopPrank();

        // 时间前进15天 (一半)
        vm.warp(block.timestamp + 15 days);

        uint256 pendingReward = staking.pendingReward(sessionId, user1);

        // 应该获得大约一半的奖励
        assertApproxEqRel(pendingReward, 5000 * 10**18, 0.05e18); // 5% tolerance
    }

    // ============================================
    // 测试: 暂停功能
    // ============================================

    function testPause() public {
        staking.pause();
        assertTrue(staking.paused());

        staking.unpause();
        assertFalse(staking.paused());
    }

    function testCannotDepositWhenPaused() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        staking.pause();

        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10**18);
        vm.expectRevert();
        staking.deposit(sessionId, 1000 * 10**18);
        vm.stopPrank();
    }

    function testCannotCheckInWhenPaused() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10**18);
        staking.deposit(sessionId, 1000 * 10**18);
        vm.stopPrank();

        staking.pause();

        vm.prank(user1);
        vm.expectRevert();
        staking.checkIn(sessionId);
    }

    function testCannotWithdrawWhenPaused() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10**18);
        staking.deposit(sessionId, 1000 * 10**18);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        staking.pause();

        vm.prank(user1);
        vm.expectRevert();
        staking.withdraw(sessionId);
    }

    // ============================================
    // 测试: 多session场景
    // ============================================

    function testMultipleSessions() public {
        // 创建第一个session
        uint256 session1 = _createTestSession();

        vm.warp(block.timestamp + 1 days + 1);

        // 用户在session1质押
        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10**18);
        staking.deposit(session1, 1000 * 10**18);
        vm.stopPrank();

        // 时间前进到session1结束
        vm.warp(block.timestamp + 31 days);

        // 创建第二个session (不重叠)
        uint256 totalReward = 20000 * 10**18;
        uint256 checkInReward = 10000 * 10**18;

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
        lpToken.approve(address(staking), 2000 * 10**18);
        staking.deposit(session2, 2000 * 10**18);
        vm.stopPrank();
    }

    function testUserBoostIndependentAcrossSessions() public {
        // Session 1
        uint256 session1 = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10**18);
        staking.deposit(session1, 1000 * 10**18);
        staking.checkIn(session1);
        vm.warp(block.timestamp + 300);
        staking.checkIn(session1);
        vm.stopPrank();

        // 验证session1的boost
        (, , uint256 boost1, , ) = staking.userInfo(session1, user1);
        assertEq(boost1, 2);

        // 等到session1结束
        vm.warp(block.timestamp + 31 days);

        // 创建session2
        uint256 totalReward = 20000 * 10**18;
        uint256 checkInReward = 10000 * 10**18;
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
        lpToken.approve(address(staking), 1000 * 10**18);
        staking.deposit(session2, 1000 * 10**18);
        vm.stopPrank();

        // 验证session2的boost从0开始
        (, , uint256 boost2Before, , ) = staking.userInfo(session2, user1);
        assertEq(boost2Before, 0);

        // 在session2签到
        vm.prank(user1);
        staking.checkIn(session2);

        (, , uint256 boost2After, , ) = staking.userInfo(session2, user1);
        assertEq(boost2After, 1);

        // session1的boost不受影响
        (, , uint256 boost1Final, , ) = staking.userInfo(session1, user1);
        assertEq(boost1Final, 2);
    }

    // ============================================
    // 测试: 边界情况
    // ============================================

    function testCheckInAtSessionEndTime() public {
        uint256 sessionId = _createTestSession();

        // 获取session信息
        (, , , , , , uint256 endTime, , , , , , ) = staking.sessions(sessionId);

        // 在session开始时质押
        vm.warp(block.timestamp + 1 days + 1);
        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10**18);
        staking.deposit(sessionId, 1000 * 10**18);

        // 在session结束时签到
        vm.warp(endTime);
        staking.checkIn(sessionId); // 应该成功

        vm.stopPrank();
    }

    function testCheckInAfterSessionEnds() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10**18);
        staking.deposit(sessionId, 1000 * 10**18);

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
        lpToken.approve(address(staking), 1000 * 10**18);
        staking.deposit(sessionId, 1000 * 10**18);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        // 验证没有签到奖励
        uint256 checkInReward = staking.pendingCheckInReward(sessionId, user1);
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
        assertEq(session.totalReward, 10000 * 10**18);
        assertEq(session.checkInRewardPool, 5000 * 10**18);
        assertTrue(session.active);
    }

    function testGetUserInfo() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10**18);
        staking.deposit(sessionId, 1000 * 10**18);
        staking.checkIn(sessionId);
        vm.stopPrank();

        Staking.UserInfo memory userInfo = staking.getUserInfo(sessionId, user1);

        assertEq(userInfo.amount, 1000 * 10**18);
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
        lpToken.approve(address(staking), 1000 * 10**18);
        staking.deposit(sessionId, 1000 * 10**18);

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
    // 辅助函数
    // ============================================

    function _createTestSession() internal returns (uint256) {
        uint256 totalReward = 10000 * 10**18;
        uint256 checkInReward = 5000 * 10**18;
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

    function _createBNBStakingSession() internal returns (uint256) {
        uint256 totalReward = 10000 * 10**18;
        uint256 checkInReward = 5000 * 10**18;
        uint256 startTime = block.timestamp + 1 days;
        uint256 endTime = startTime + 30 days;

        // 授权ERC20奖励代币
        rewardToken.approve(address(staking), totalReward);
        checkInRewardToken.approve(address(staking), checkInReward);

        staking.createSession(
            Staking.CreateSessionParams({
                stakingToken: address(0), // BNB staking
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
}
