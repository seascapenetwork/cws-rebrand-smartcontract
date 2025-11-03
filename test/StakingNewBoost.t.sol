// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/Staking.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title StakingNewBoost测试 - 测试新的档位点数boost算法
contract StakingNewBoostTest is Test {
    Staking public staking;
    MockERC20 public lpToken;
    MockERC20 public rewardToken;
    MockERC20 public checkInRewardToken;

    address public owner;
    address public alice;
    address public bob;
    address public charlie;

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");

        // 部署代币
        lpToken = new MockERC20("LP Token", "LP");
        rewardToken = new MockERC20("Reward Token", "RWD");
        checkInRewardToken = new MockERC20("CheckIn Reward", "CHK");

        // 部署staking合约
        staking = new Staking(owner);

        // 给用户mint代币
        lpToken.mint(alice, 1000 ether);
        lpToken.mint(bob, 1000 ether);
        lpToken.mint(charlie, 1000 ether);

        // 给owner mint奖励代币
        rewardToken.mint(owner, 100000 ether);
        checkInRewardToken.mint(owner, 100000 ether);
    }

    // ============================================
    // 辅助函数
    // ============================================

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

    // ============================================
    // 测试1: 档位判定测试
    // ============================================

    /// @notice 测试低于最低门槛无法签到
    function test_CheckIn_BelowMinimum() public {
        uint256 sessionId = _createSession();
        vm.warp(block.timestamp + 1 days + 1);

        // Alice质押4.9 LP (低于5 LP门槛)
        vm.startPrank(alice);
        lpToken.approve(address(staking), 4.9 ether);
        staking.deposit(sessionId, 4.9 ether);

        // 尝试签到应该失败
        vm.expectRevert("Must stake at least 5 LP to check-in");
        staking.checkIn(sessionId);
        vm.stopPrank();
    }

    /// @notice 测试各个档位边界值
    function test_CheckIn_TierBoundaries() public {
        uint256 sessionId = _createSession();
        vm.warp(block.timestamp + 1 days + 1);

        // 测试5 LP边界 (应该获得1点)
        vm.startPrank(alice);
        lpToken.approve(address(staking), 5 ether);
        staking.deposit(sessionId, 5 ether);
        staking.checkIn(sessionId);
        (, , , uint256 boost1, , ) = staking.userInfo(sessionId, alice);
        assertEq(boost1, 1, "5 LP should give 1 point");
        vm.stopPrank();

        // 测试10 LP边界 (应该获得2点)
        vm.startPrank(bob);
        lpToken.approve(address(staking), 10 ether);
        staking.deposit(sessionId, 10 ether);
        vm.warp(block.timestamp + 300);
        staking.checkIn(sessionId);
        (, , , uint256 boost2, , ) = staking.userInfo(sessionId, bob);
        assertEq(boost2, 2, "10 LP should give 2 points");
        vm.stopPrank();

        // 测试50 LP边界 (应该获得5点)
        vm.startPrank(charlie);
        lpToken.approve(address(staking), 50 ether);
        staking.deposit(sessionId, 50 ether);
        vm.warp(block.timestamp + 300);
        staking.checkIn(sessionId);
        (, , , uint256 boost3, , ) = staking.userInfo(sessionId, charlie);
        assertEq(boost3, 5, "50 LP should give 5 points");
        vm.stopPrank();
    }

    /// @notice 测试所有档位
    function test_CheckIn_AllTiers() public {
        uint256 sessionId = _createSession();
        vm.warp(block.timestamp + 1 days + 1);

        address[5] memory users = [
            makeAddr("user1"),
            makeAddr("user2"),
            makeAddr("user3"),
            makeAddr("user4"),
            makeAddr("user5")
        ];
        uint256[5] memory amounts = [
            uint256(5 ether),   // 1点
            uint256(10 ether),  // 2点
            uint256(20 ether),  // 3点
            uint256(30 ether),  // 4点
            uint256(50 ether)   // 5点
        ];
        uint256[5] memory expectedPoints = [uint256(1), 2, 3, 4, 5];

        for (uint256 i = 0; i < 5; i++) {
            lpToken.mint(users[i], amounts[i]);
            vm.startPrank(users[i]);
            lpToken.approve(address(staking), amounts[i]);
            staking.deposit(sessionId, amounts[i]);
            if (i > 0) vm.warp(block.timestamp + 300);
            staking.checkIn(sessionId);
            (, , , uint256 boost, , ) = staking.userInfo(sessionId, users[i]);
            assertEq(boost, expectedPoints[i], "Incorrect points for tier");
            vm.stopPrank();
        }
    }

    // ============================================
    // 测试2: 追加质押后档位变化
    // ============================================

    /// @notice 测试追加质押后签到获得更高档位点数
    function test_CheckIn_UpgradeTierAfterDeposit() public {
        uint256 sessionId = _createSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(alice);

        // 首次质押5 LP, 签到获得1点
        lpToken.approve(address(staking), 5 ether);
        staking.deposit(sessionId, 5 ether);
        staking.checkIn(sessionId);
        (, , , uint256 boost1, , ) = staking.userInfo(sessionId, alice);
        assertEq(boost1, 1, "First check-in should give 1 point");

        // 追加45 LP, 总共50 LP
        vm.warp(block.timestamp + 300);
        lpToken.approve(address(staking), 45 ether);
        staking.deposit(sessionId, 45 ether);

        // 再次签到应该获得5点 (现在是50 LP档位)
        vm.warp(block.timestamp + 300);
        staking.checkIn(sessionId);
        (, , , uint256 boost2, , ) = staking.userInfo(sessionId, alice);
        assertEq(boost2, 6, "Second check-in should give 5 more points (1+5=6)");

        vm.stopPrank();
    }

    // ============================================
    // 测试3: 奖励计算测试
    // ============================================

    /// @notice 测试单用户签到获得全部奖励
    function test_BoostReward_SingleUser() public {
        uint256 sessionId = _createSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(alice);
        lpToken.approve(address(staking), 10 ether);
        staking.deposit(sessionId, 10 ether);
        staking.checkIn(sessionId); // 获得2点
        vm.stopPrank();

        // session结束
        vm.warp(block.timestamp + 31 days);

        // Alice应该获得全部5000 ether boost奖励
        uint256 reward = staking.pendingBoostReward(sessionId, alice);
        assertEq(reward, 5000 ether, "Single user should get all boost rewards");
    }

    /// @notice 测试多用户按点数比例分配
    function test_BoostReward_MultipleUsers() public {
        uint256 sessionId = _createSession();
        vm.warp(block.timestamp + 1 days + 1);

        // Alice: 5 LP, 1点
        vm.startPrank(alice);
        lpToken.approve(address(staking), 5 ether);
        staking.deposit(sessionId, 5 ether);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // Bob: 10 LP, 2点
        vm.startPrank(bob);
        lpToken.approve(address(staking), 10 ether);
        staking.deposit(sessionId, 10 ether);
        vm.warp(block.timestamp + 300);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // Charlie: 20 LP, 3点
        vm.startPrank(charlie);
        lpToken.approve(address(staking), 20 ether);
        staking.deposit(sessionId, 20 ether);
        vm.warp(block.timestamp + 300);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // session结束
        vm.warp(block.timestamp + 31 days);

        // 总点数: 1+2+3=6
        // Alice: 5000 * 1/6 = 833.33...
        // Bob: 5000 * 2/6 = 1666.66...
        // Charlie: 5000 * 3/6 = 2500
        uint256 rewardAlice = staking.pendingBoostReward(sessionId, alice);
        uint256 rewardBob = staking.pendingBoostReward(sessionId, bob);
        uint256 rewardCharlie = staking.pendingBoostReward(sessionId, charlie);

        assertApproxEqRel(rewardAlice, 833333333333333333333, 0.01e18, "Alice should get ~833.33 tokens");
        assertApproxEqRel(rewardBob, 1666666666666666666666, 0.01e18, "Bob should get ~1666.66 tokens");
        assertApproxEqRel(rewardCharlie, 2500 ether, 0.01e18, "Charlie should get 2500 tokens");

        // 总和应该等于奖池
        assertApproxEqRel(rewardAlice + rewardBob + rewardCharlie, 5000 ether, 0.01e18);
    }

    /// @notice 测试多次签到累计点数
    function test_BoostReward_MultipleCheckIns() public {
        uint256 sessionId = _createSession();
        uint256 sessionStart = block.timestamp + 1 days + 1;
        vm.warp(sessionStart);

        vm.startPrank(alice);
        lpToken.approve(address(staking), 50 ether);
        staking.deposit(sessionId, 50 ether);

        // 签到3次，每次5点
        staking.checkIn(sessionId);
        vm.warp(sessionStart + 300);
        staking.checkIn(sessionId);
        vm.warp(sessionStart + 600);
        staking.checkIn(sessionId);

        (, , , uint256 totalPoints, , ) = staking.userInfo(sessionId, alice);
        assertEq(totalPoints, 15, "Should have 15 points from 3 check-ins");
        vm.stopPrank();

        // session结束
        vm.warp(sessionStart + 31 days);

        // Alice应该获得全部奖励
        uint256 reward = staking.pendingBoostReward(sessionId, alice);
        assertEq(reward, 5000 ether, "Should get all rewards");
    }

    /// @notice 测试未签到用户不获得boost奖励
    function test_BoostReward_NoCheckIn() public {
        uint256 sessionId = _createSession();
        vm.warp(block.timestamp + 1 days + 1);

        // Alice质押但不签到
        vm.startPrank(alice);
        lpToken.approve(address(staking), 50 ether);
        staking.deposit(sessionId, 50 ether);
        vm.stopPrank();

        // Bob质押并签到
        vm.startPrank(bob);
        lpToken.approve(address(staking), 10 ether);
        staking.deposit(sessionId, 10 ether);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // session结束
        vm.warp(block.timestamp + 31 days);

        // Alice没签到，应该没有boost奖励
        uint256 rewardAlice = staking.pendingBoostReward(sessionId, alice);
        assertEq(rewardAlice, 0, "No check-in should mean no boost reward");

        // Bob应该获得全部奖励
        uint256 rewardBob = staking.pendingBoostReward(sessionId, bob);
        assertEq(rewardBob, 5000 ether, "Bob should get all rewards");
    }

    // ============================================
    // 测试4: recoverUnusedBoostReward测试
    // ============================================

    /// @notice 测试无人签到时owner可以回收奖励
    function test_RecoverUnusedBoostReward_NoCheckIns() public {
        uint256 sessionId = _createSession();
        vm.warp(block.timestamp + 1 days + 1);

        // 用户质押但不签到
        vm.startPrank(alice);
        lpToken.approve(address(staking), 50 ether);
        staking.deposit(sessionId, 50 ether);
        vm.stopPrank();

        // session结束
        vm.warp(block.timestamp + 32 days);

        uint256 ownerBalanceBefore = checkInRewardToken.balanceOf(owner);

        // Owner回收boost奖励
        staking.recoverUnusedBoostReward(sessionId);

        uint256 ownerBalanceAfter = checkInRewardToken.balanceOf(owner);
        assertEq(ownerBalanceAfter - ownerBalanceBefore, 5000 ether, "Owner should recover 5000 tokens");
    }

    /// @notice 测试有人签到时不能回收
    function test_RecoverUnusedBoostReward_WithCheckIns() public {
        uint256 sessionId = _createSession();
        vm.warp(block.timestamp + 1 days + 1);

        // Alice签到
        vm.startPrank(alice);
        lpToken.approve(address(staking), 10 ether);
        staking.deposit(sessionId, 10 ether);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // session结束
        vm.warp(block.timestamp + 32 days);

        // 尝试回收应该失败
        vm.expectRevert("Boost points exist, cannot recover");
        staking.recoverUnusedBoostReward(sessionId);
    }

    /// @notice 测试非owner不能调用
    function test_RecoverUnusedBoostReward_OnlyOwner() public {
        uint256 sessionId = _createSession();
        vm.warp(block.timestamp + 32 days);

        vm.prank(alice);
        vm.expectRevert();
        staking.recoverUnusedBoostReward(sessionId);
    }

    /// @notice 测试session未结束时不能回收
    function test_RecoverUnusedBoostReward_SessionNotEnded() public {
        uint256 sessionId = _createSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.expectRevert("Session not ended yet");
        staking.recoverUnusedBoostReward(sessionId);
    }

    // ============================================
    // 测试5: 完整流程测试
    // ============================================

    /// @notice 测试完整的质押-签到-提取流程
    function test_FullFlow_StakeCheckInWithdraw() public {
        uint256 sessionId = _createSession();
        uint256 sessionStart = block.timestamp + 1 days + 1;
        vm.warp(sessionStart);

        // Alice质押并签到多次
        vm.startPrank(alice);
        lpToken.approve(address(staking), 50 ether);
        staking.deposit(sessionId, 50 ether);

        // 签到3次
        staking.checkIn(sessionId);
        vm.warp(sessionStart + 300);
        staking.checkIn(sessionId);
        vm.warp(sessionStart + 600);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // session结束
        vm.warp(sessionStart + 32 days);

        // 记录提取前余额
        uint256 lpBalanceBefore = lpToken.balanceOf(alice);
        uint256 checkInBalanceBefore = checkInRewardToken.balanceOf(alice);

        // 提取
        vm.prank(alice);
        staking.withdraw(sessionId);

        // 验证提取后余额
        uint256 lpBalanceAfter = lpToken.balanceOf(alice);
        uint256 checkInBalanceAfter = checkInRewardToken.balanceOf(alice);

        assertEq(lpBalanceAfter - lpBalanceBefore, 50 ether, "Should get back staked LP");
        assertEq(checkInBalanceAfter - checkInBalanceBefore, 5000 ether, "Should get all boost rewards");
    }

    /// @notice 测试多用户完整流程
    function test_FullFlow_MultipleUsers() public {
        uint256 sessionId = _createSession();
        vm.warp(block.timestamp + 1 days + 1);

        // Alice: 5 LP, 签到2次, 共2点
        vm.startPrank(alice);
        lpToken.approve(address(staking), 5 ether);
        staking.deposit(sessionId, 5 ether);
        staking.checkIn(sessionId);
        vm.warp(block.timestamp + 300);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // Bob: 50 LP, 签到1次, 共5点
        vm.startPrank(bob);
        lpToken.approve(address(staking), 50 ether);
        staking.deposit(sessionId, 50 ether);
        vm.warp(block.timestamp + 300);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // Charlie: 20 LP, 签到3次, 共9点
        vm.startPrank(charlie);
        lpToken.approve(address(staking), 20 ether);
        staking.deposit(sessionId, 20 ether);
        vm.warp(block.timestamp + 300);
        staking.checkIn(sessionId);
        vm.warp(block.timestamp + 300);
        staking.checkIn(sessionId);
        vm.warp(block.timestamp + 300);
        staking.checkIn(sessionId);
        vm.stopPrank();

        // session结束
        vm.warp(block.timestamp + 32 days);

        // 总点数: 2+5+9=16
        // Alice: 5000 * 2/16 = 625
        // Bob: 5000 * 5/16 = 1562.5
        // Charlie: 5000 * 9/16 = 2812.5

        uint256 checkInBalanceAliceBefore = checkInRewardToken.balanceOf(alice);
        uint256 checkInBalanceBobBefore = checkInRewardToken.balanceOf(bob);
        uint256 checkInBalanceCharlieBefore = checkInRewardToken.balanceOf(charlie);

        vm.prank(alice);
        staking.withdraw(sessionId);
        vm.prank(bob);
        staking.withdraw(sessionId);
        vm.prank(charlie);
        staking.withdraw(sessionId);

        uint256 rewardAlice = checkInRewardToken.balanceOf(alice) - checkInBalanceAliceBefore;
        uint256 rewardBob = checkInRewardToken.balanceOf(bob) - checkInBalanceBobBefore;
        uint256 rewardCharlie = checkInRewardToken.balanceOf(charlie) - checkInBalanceCharlieBefore;

        assertApproxEqRel(rewardAlice, 625 ether, 0.01e18, "Alice should get 625 tokens");
        assertApproxEqRel(rewardBob, 1562.5 ether, 0.01e18, "Bob should get 1562.5 tokens");
        assertApproxEqRel(rewardCharlie, 2812.5 ether, 0.01e18, "Charlie should get 2812.5 tokens");

        // 总和应该等于奖池
        assertApproxEqRel(rewardAlice + rewardBob + rewardCharlie, 5000 ether, 0.01e18);
    }

    // ============================================
    // 测试6: 边界条件测试
    // ============================================

    /// @notice 测试恰好5 LP边界
    function test_Boundary_Exactly5LP() public {
        uint256 sessionId = _createSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(alice);
        lpToken.approve(address(staking), 5 ether);
        staking.deposit(sessionId, 5 ether);
        staking.checkIn(sessionId); // 应该成功，获得1点
        (, , , uint256 boost, , ) = staking.userInfo(sessionId, alice);
        assertEq(boost, 1, "Exactly 5 LP should give 1 point");
        vm.stopPrank();
    }

    /// @notice 测试质押量在两个档位之间
    function test_Boundary_BetweenTiers() public {
        uint256 sessionId = _createSession();
        vm.warp(block.timestamp + 1 days + 1);

        // 15 LP (在10和20之间，应该属于10 LP档位，获得2点)
        vm.startPrank(alice);
        lpToken.approve(address(staking), 15 ether);
        staking.deposit(sessionId, 15 ether);
        staking.checkIn(sessionId);
        (, , , uint256 boost, , ) = staking.userInfo(sessionId, alice);
        assertEq(boost, 2, "15 LP should give 2 points (10 LP tier)");
        vm.stopPrank();
    }

    /// @notice 测试超过最高档位
    function test_Boundary_Above50LP() public {
        uint256 sessionId = _createSession();
        vm.warp(block.timestamp + 1 days + 1);

        // 100 LP (超过50，应该还是5点)
        vm.startPrank(alice);
        lpToken.approve(address(staking), 100 ether);
        staking.deposit(sessionId, 100 ether);
        staking.checkIn(sessionId);
        (, , , uint256 boost, , ) = staking.userInfo(sessionId, alice);
        assertEq(boost, 5, "100 LP should give 5 points (max tier)");
        vm.stopPrank();
    }

    /// @notice 测试冷却时间
    function test_CheckIn_CooldownPeriod() public {
        uint256 sessionId = _createSession();
        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(alice);
        lpToken.approve(address(staking), 10 ether);
        staking.deposit(sessionId, 10 ether);

        staking.checkIn(sessionId);

        // 立即再次签到应该失败
        vm.expectRevert("Check-in cooldown not expired");
        staking.checkIn(sessionId);

        // 299秒后应该还是失败
        vm.warp(block.timestamp + 299);
        vm.expectRevert("Check-in cooldown not expired");
        staking.checkIn(sessionId);

        // 300秒后应该成功
        vm.warp(block.timestamp + 1);
        staking.checkIn(sessionId);
        (, , , uint256 boost, , ) = staking.userInfo(sessionId, alice);
        assertEq(boost, 4, "Should have 4 points after 2 check-ins");

        vm.stopPrank();
    }
}

/// @notice Mock ERC20 for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
