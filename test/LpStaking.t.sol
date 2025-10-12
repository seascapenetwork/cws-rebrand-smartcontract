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

    // ============================================
    // 测试: checkIn
    // ============================================

    function testCheckIn() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        // 用户1质押
        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10**18);
        staking.deposit(sessionId, 1000 * 10**18);

        // 签到
        staking.checkIn(sessionId);
        vm.stopPrank();

        // 验证
        (, , uint256 boost, , bool hasCheckedIn) = staking.userInfo(sessionId, user1);
        assertTrue(hasCheckedIn);
        assertEq(boost, 1);
    }

    function testCannotCheckInWithoutStaking() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(user1);
        vm.expectRevert("Must stake before check-in");
        staking.checkIn(sessionId);
    }

    function testCannotCheckInTwice() public {
        uint256 sessionId = _createTestSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 1000 * 10**18);
        staking.deposit(sessionId, 1000 * 10**18);
        staking.checkIn(sessionId);

        vm.expectRevert("Already checked in");
        staking.checkIn(sessionId);
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

        // 验证用户2没有签到奖励
        assertEq(checkInRewardToken.balanceOf(user2), user2CheckInRewardBefore);
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
