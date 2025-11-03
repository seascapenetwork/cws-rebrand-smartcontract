// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/Staking.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title StakingBoostEdgeCases测试 - 测试极端情况和边界条件
contract StakingBoostEdgeCasesTest is Test {
    Staking public staking;
    MockERC20 public lpToken;
    MockERC20 public rewardToken;
    MockERC20 public checkInRewardToken;

    address public owner;
    address public user1;
    address public user2;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        lpToken = new MockERC20("LP Token", "LP");
        rewardToken = new MockERC20("Reward Token", "RWD");
        checkInRewardToken = new MockERC20("CheckIn Reward", "CHK");

        staking = new Staking(owner);

        lpToken.mint(user1, 10000 ether);
        lpToken.mint(user2, 10000 ether);

        rewardToken.mint(owner, 100000 ether);
        checkInRewardToken.mint(owner, 100000 ether);
    }

    function _createSession() internal returns (uint256) {
        uint256 totalReward = 10000 ether;
        uint256 checkInReward = 5000 ether;
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

    /// @notice 测试：质押量刚好低于5 LP (4.999999 LP)
    function test_EdgeCase_JustBelow5LP() public {
        uint256 sessionId = _createSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 4.999999 ether);
        staking.deposit(sessionId, 4.999999 ether);

        vm.expectRevert("Must stake at least 5 LP to check-in");
        staking.checkIn(sessionId);
        vm.stopPrank();
    }

    /// @notice 测试：两个用户，一个签到很多次，一个只签到一次
    function test_EdgeCase_VeryDifferentCheckInCounts() public {
        uint256 sessionId = _createSession();
        Staking.Session memory session = staking.getSessionInfo(sessionId);
        vm.warp(session.startTime);

        // User1: 5 LP, 签到50次
        vm.startPrank(user1);
        lpToken.approve(address(staking), 5 ether);
        staking.deposit(sessionId, 5 ether);
        for (uint256 i = 0; i < 50; i++) {
            vm.warp(session.startTime + i * 300);
            staking.checkIn(sessionId);
        }
        vm.stopPrank();

        // User2: 50 LP, 只签到1次
        vm.startPrank(user2);
        lpToken.approve(address(staking), 50 ether);
        staking.deposit(sessionId, 50 ether);
        vm.warp(session.startTime + 50 * 300);
        staking.checkIn(sessionId);
        vm.stopPrank();

        vm.warp(session.endTime + 1);

        // User1: 50点 (50次 × 1点)
        // User2: 5点 (1次 × 5点)
        // 总点数: 55点
        // User1应得: 5000 * 50/55 = 4545.45
        // User2应得: 5000 * 5/55 = 454.55
        uint256 reward1 = staking.pendingBoostReward(sessionId, user1);
        uint256 reward2 = staking.pendingBoostReward(sessionId, user2);

        assertApproxEqRel(reward1, 4545454545454545454545, 0.01e18);
        assertApproxEqRel(reward2, 454545454545454545454, 0.01e18);
    }

    /// @notice 测试：用户在不同时间档位变化
    function test_EdgeCase_TierChangesOverTime() public {
        uint256 sessionId = _createSession();
        uint256 sessionStart = block.timestamp + 1 days + 1;
        vm.warp(sessionStart);

        vm.startPrank(user1);

        // 第1次: 5 LP → 1点
        lpToken.approve(address(staking), 5 ether);
        staking.deposit(sessionId, 5 ether);
        staking.checkIn(sessionId);

        // 第2次: 追加5 LP, 总10 LP → 2点
        vm.warp(sessionStart + 300);
        lpToken.approve(address(staking), 5 ether);
        staking.deposit(sessionId, 5 ether);
        vm.warp(sessionStart + 600);
        staking.checkIn(sessionId);

        // 第3次: 追加10 LP, 总20 LP → 3点
        vm.warp(sessionStart + 900);
        lpToken.approve(address(staking), 10 ether);
        staking.deposit(sessionId, 10 ether);
        vm.warp(sessionStart + 1200);
        staking.checkIn(sessionId);

        // 第4次: 追加10 LP, 总30 LP → 4点
        vm.warp(sessionStart + 1500);
        lpToken.approve(address(staking), 10 ether);
        staking.deposit(sessionId, 10 ether);
        vm.warp(sessionStart + 1800);
        staking.checkIn(sessionId);

        // 第5次: 追加20 LP, 总50 LP → 5点
        vm.warp(sessionStart + 2100);
        lpToken.approve(address(staking), 20 ether);
        staking.deposit(sessionId, 20 ether);
        vm.warp(sessionStart + 2400);
        staking.checkIn(sessionId);

        // 总点数: 1+2+3+4+5=15
        (, , , uint256 totalPoints, , ) = staking.userInfo(sessionId, user1);
        assertEq(totalPoints, 15);

        vm.stopPrank();

        vm.warp(sessionStart + 31 days);

        // User1应得全部奖励
        uint256 reward = staking.pendingBoostReward(sessionId, user1);
        assertEq(reward, 5000 ether);
    }

    /// @notice 测试：精度问题 - 奖励总和应该等于奖池
    function test_EdgeCase_PrecisionCheck() public {
        uint256 sessionId = _createSession();
        uint256 sessionStart = block.timestamp + 1 days + 1;
        vm.warp(sessionStart);

        // 创建7个用户，不同档位
        address[7] memory users;
        uint256[7] memory amounts = [
            uint256(5 ether),
            uint256(7 ether),
            uint256(10 ether),
            uint256(15 ether),
            uint256(20 ether),
            uint256(30 ether),
            uint256(50 ether)
        ];

        for (uint256 i = 0; i < 7; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", i)));
            lpToken.mint(users[i], amounts[i]);

            vm.startPrank(users[i]);
            lpToken.approve(address(staking), amounts[i]);
            staking.deposit(sessionId, amounts[i]);
            vm.warp(sessionStart + i * 300);
            staking.checkIn(sessionId);
            vm.stopPrank();
        }

        vm.warp(sessionStart + 31 days);

        // 计算总奖励
        uint256 totalDistributed = 0;
        for (uint256 i = 0; i < 7; i++) {
            totalDistributed += staking.pendingBoostReward(sessionId, users[i]);
        }

        // 总和应该精确等于奖池 (允许1 wei的舍入误差)
        assertApproxEqAbs(totalDistributed, 5000 ether, 7);
    }

    /// @notice 测试：大量用户签到
    function test_EdgeCase_ManyUsers() public {
        uint256 sessionId = _createSession();
        uint256 sessionStart = block.timestamp + 1 days + 1;
        vm.warp(sessionStart);

        uint256 userCount = 20;
        address[] memory users = new address[](userCount);

        // 20个用户，每人10 LP，各签到1次
        for (uint256 i = 0; i < userCount; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", i)));
            lpToken.mint(users[i], 10 ether);

            vm.startPrank(users[i]);
            lpToken.approve(address(staking), 10 ether);
            staking.deposit(sessionId, 10 ether);
            vm.warp(sessionStart + i * 300);
            staking.checkIn(sessionId); // 每人2点
            vm.stopPrank();
        }

        vm.warp(sessionStart + 31 days);

        // 每人应得: 5000 * 2/40 = 250
        for (uint256 i = 0; i < userCount; i++) {
            uint256 reward = staking.pendingBoostReward(sessionId, users[i]);
            assertApproxEqRel(reward, 250 ether, 0.01e18);
        }
    }

    /// @notice 测试：session结束前最后一刻签到
    function test_EdgeCase_CheckInAtLastMoment() public {
        uint256 sessionId = _createSession();
        Staking.Session memory session = staking.getSessionInfo(sessionId);
        vm.warp(session.startTime);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 10 ether);
        staking.deposit(sessionId, 10 ether);

        // 在session结束前1秒签到
        vm.warp(session.endTime - 1);
        staking.checkIn(sessionId);

        (, , , uint256 points, , ) = staking.userInfo(sessionId, user1);
        assertEq(points, 2, "Should still be able to check in");
        vm.stopPrank();

        // session结束后尝试签到应该失败
        vm.warp(session.endTime + 1);
        vm.prank(user1);
        vm.expectRevert("Session ended");
        staking.checkIn(sessionId);
    }

    /// @notice 测试：提取后不能再签到
    function test_EdgeCase_CannotCheckInAfterWithdraw() public {
        uint256 sessionId = _createSession();
        uint256 sessionStart = block.timestamp + 1 days + 1;
        vm.warp(sessionStart);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 10 ether);
        staking.deposit(sessionId, 10 ether);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // session结束
        vm.warp(sessionStart + 31 days);

        // 提取
        vm.prank(user1);
        staking.withdraw(sessionId);

        // 提取后质押量为0，不能再签到
        vm.prank(user1);
        vm.expectRevert("Session ended");
        staking.checkIn(sessionId);
    }

    /// @notice 测试：recoverUnusedBoostReward不能重复调用
    function test_EdgeCase_CannotRecoverTwice() public {
        uint256 sessionId = _createSession();
        vm.warp(block.timestamp + 32 days);

        // 第一次回收成功
        staking.recoverUnusedBoostReward(sessionId);

        // 第二次应该失败(奖池已经为0)
        vm.expectRevert("No boost reward to recover");
        staking.recoverUnusedBoostReward(sessionId);
    }

    /// @notice 测试：极小的boost奖池
    function test_EdgeCase_VerySmallRewardPool() public {
        uint256 totalReward = 10000 ether;
        uint256 checkInReward = 1; // 只有1 wei
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

        uint256 sessionId = staking.currentSessionId();
        vm.warp(startTime + 1);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 10 ether);
        staking.deposit(sessionId, 10 ether);
        staking.checkIn(sessionId);
        vm.stopPrank();

        vm.warp(endTime + 1);

        uint256 reward = staking.pendingBoostReward(sessionId, user1);
        assertEq(reward, 1, "Should get 1 wei");
    }

    /// @notice 测试：极大量的签到
    function test_EdgeCase_ManyCheckIns() public {
        uint256 sessionId = _createSession();
        uint256 sessionStart = block.timestamp + 1 days + 1;
        vm.warp(sessionStart);

        vm.startPrank(user1);
        lpToken.approve(address(staking), 50 ether);
        staking.deposit(sessionId, 50 ether);

        // 签到100次
        for (uint256 i = 0; i < 100; i++) {
            vm.warp(sessionStart + i * 300);
            staking.checkIn(sessionId);
        }

        (, , , uint256 points, , ) = staking.userInfo(sessionId, user1);
        assertEq(points, 500, "Should have 500 points (100 * 5)");
        vm.stopPrank();

        vm.warp(sessionStart + 31 days);

        uint256 reward = staking.pendingBoostReward(sessionId, user1);
        assertEq(reward, 5000 ether, "Should get all rewards");
    }
}

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
