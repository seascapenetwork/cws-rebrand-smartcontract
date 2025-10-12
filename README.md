# LP质押与签到奖励智能合约

一个功能完整的LP代币质押合约，支持线性释放奖励和基于签到的额外激励机制。

## 功能特性

### 核心功能

1. **灵活的质押支持**
   - 支持LP代币、ERC20代币和BNB原生代币质押
   - 支持多种奖励代币类型（ERC20/BNB）
   - 锁定期质押，活动结束后一次性提取

2. **线性奖励释放**
   - 根据用户质押占TVL的比例分配奖励
   - 奖励按时间线性释放
   - Session结束后统一领取

3. **签到激励系统**
   - 每个session仅可签到一次
   - 基于TVL占比和boost点数计算签到奖励
   - 公式：`签到奖励 = 签到奖池 × (用户质押×boost) / Σ(所有用户质押×boost)`

4. **Session管理**
   - 支持多个独立session
   - 全局时间不重叠检查
   - 新session需等前一session结束

5. **安全机制**
   - 重入保护（ReentrancyGuard）
   - 暂停功能（Pausable）
   - 防重复提取检查
   - Owner权限管理

## 技术规范

- **Solidity版本**: 0.8.20
- **编译器优化**: via-ir enabled, 200 runs
- **依赖库**: OpenZeppelin Contracts v5.0.2
- **目标网络**: BNB Chain (BSC)

## 合约架构

### 主要数据结构

```solidity
struct Session {
    address stakingToken;           // 质押代币
    address rewardToken;            // 奖励代币
    address checkInRewardToken;     // 签到奖励代币
    uint256 totalReward;            // 总奖励
    uint256 checkInRewardPool;      // 签到奖励池
    uint256 startTime;              // 开始时间
    uint256 endTime;                // 结束时间
    uint256 totalStaked;            // 总质押量
    uint256 rewardPerSecond;        // 每秒奖励
    uint256 accRewardPerShare;      // 累积每份额奖励
    uint256 lastRewardTime;         // 上次更新时间
    uint256 totalWeightedStake;     // 加权质押总量
    bool active;                    // 是否激活
}

struct UserInfo {
    uint256 amount;                 // 用户质押量
    uint256 rewardDebt;             // 奖励债务
    uint256 boost;                  // boost点数(0或1)
    bool hasWithdrawn;              // 是否已提取
    bool hasCheckedIn;              // 是否已签到
}
```

### 核心函数

#### Owner函数

- `createSession()` - 创建新的质押session
- `pause()` / `unpause()` - 暂停/恢复合约

#### 用户函数

- `deposit(sessionId, amount)` - 质押代币
- `checkIn(sessionId)` - 签到获取boost
- `withdraw(sessionId)` - 提取本金和奖励

#### 查询函数

- `pendingReward(sessionId, user)` - 查询待领取LP奖励
- `pendingCheckInReward(sessionId, user)` - 查询签到奖励
- `getSessionInfo(sessionId)` - 获取session信息
- `getUserInfo(sessionId, user)` - 获取用户信息

## 使用指南

### 部署合约

```bash
# 编译
forge build

# 部署到BSC测试网
forge create --rpc-url $BSC_TESTNET_RPC \
  --private-key $PRIVATE_KEY \
  --constructor-args $OWNER_ADDRESS \
  src/LpStaking.sol:LpStaking

# 验证合约
forge verify-contract \
  --chain-id 97 \
  --num-of-optimizations 200 \
  --constructor-args $(cast abi-encode "constructor(address)" $OWNER_ADDRESS) \
  $CONTRACT_ADDRESS \
  src/LpStaking.sol:LpStaking
```

### 创建Session

```solidity
// 示例：创建一个30天的LP质押活动
uint256 startTime = block.timestamp + 1 days;
uint256 endTime = startTime + 30 days;
uint256 totalReward = 10000 * 1e18;      // 10,000 ASTER
uint256 checkInReward = 5000 * 1e18;     // 5,000 ASTER

// 授权奖励代币
rewardToken.approve(stakingContract, totalReward);
checkInRewardToken.approve(stakingContract, checkInReward);

// 创建session
lpStaking.createSession(
    lpTokenAddress,           // LP代币地址
    rewardTokenAddress,       // 奖励代币
    checkInRewardAddress,     // 签到奖励代币
    totalReward,
    checkInReward,
    startTime,
    endTime
);
```

### 用户参与流程

```solidity
// 1. 用户质押LP
lpToken.approve(stakingContract, amount);
lpStaking.deposit(sessionId, amount);

// 2. 签到获取boost点数(可选，但能获得额外奖励)
lpStaking.checkIn(sessionId);

// 3. Session结束后提取
lpStaking.withdraw(sessionId);
```

## 测试

```bash
# 运行所有测试
forge test

# 运行特定测试
forge test --match-test testDeposit

# 详细输出
forge test -vvv

# Gas报告
forge test --gas-report
```

### 测试覆盖

- ✅ Session创建和验证
- ✅ 质押功能（ERC20和BNB）
- ✅ 签到机制
- ✅ 提取功能
- ✅ 奖励计算准确性
- ✅ 签到奖励分配
- ✅ 暂停功能
- ✅ 边界条件和错误处理
- ✅ 多session场景

## 安全考虑

### 已实施的安全措施

1. **重入保护**: 所有状态变更函数使用`nonReentrant`修饰符
2. **整数溢出**: Solidity 0.8.x内置溢出检查
3. **访问控制**: Owner专属函数使用`onlyOwner`
4. **防重复提取**: `hasWithdrawn`标记防止重复提取
5. **时间检查**: Session时间范围验证
6. **余额检查**: 奖励代币充足性验证

### 注意事项

- 🔴 Session一旦创建无法修改参数
- 🔴 质押期间资金完全锁定
- 🔴 每个session只能签到一次
- 🔴 只能在session结束后提取
- 🔴 新session必须等前一session结束且时间不重叠

## 示例场景

### 场景1: 标准LP质押

```
Session配置:
- 质押代币: CWS-BNB LP
- 奖励代币: ASTER
- 总奖励: 10,000 ASTER
- 持续时间: 30天

用户A: 质押60% TVL，签到 → 获得6,000 ASTER + 签到奖励
用户B: 质押40% TVL，不签到 → 获得4,000 ASTER + 0签到奖励
```

### 场景2: BNB质押

```
Session配置:
- 质押代币: BNB (address(0))
- 奖励代币: ASTER
- 签到奖励: ASTER

用户通过msg.value发送BNB进行质押
```

## 部署地址

### BSC主网
- 待部署

### BSC测试网
- 待部署

## License

MIT

## 联系方式

- Website: [seascape.network](https://seascape.network)
- Twitter: [@SeascapeNetwork](https://twitter.com/SeascapeNetwork)
