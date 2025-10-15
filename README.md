# LP质押与签到奖励智能合约

[![zread](https://img.shields.io/badge/Ask_Zread-_.svg?style=flat&color=00b0aa&labelColor=000000&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB3aWR0aD0iMTYiIGhlaWdodD0iMTYiIHZpZXdCb3g9IjAgMCAxNiAxNiIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KPHBhdGggZD0iTTQuOTYxNTYgMS42MDAxSDIuMjQxNTZDMS44ODgxIDEuNjAwMSAxLjYwMTU2IDEuODg2NjQgMS42MDE1NiAyLjI0MDFWNC45NjAxQzEuNjAxNTYgNS4zMTM1NiAxLjg4ODEgNS42MDAxIDIuMjQxNTYgNS42MDAxSDQuOTYxNTZDNS4zMTUwMiA1LjYwMDEgNS42MDE1NiA1LjMxMzU2IDUuNjAxNTYgNC45NjAxVjIuMjQwMUM1LjYwMTU2IDEuODg2NjQgNS4zMTUwMiAxLjYwMDEgNC45NjE1NiAxLjYwMDFaIiBmaWxsPSIjZmZmIi8%2BCjxwYXRoIGQ9Ik00Ljk2MTU2IDEwLjM5OTlIMi4yNDE1NkMxLjg4ODEgMTAuMzk5OSAxLjYwMTU2IDEwLjY4NjQgMS42MDE1NiAxMS4wMzk5VjEzLjc1OTlDMS42MDE1NiAxNC4xMTM0IDEuODg4MSAxNC4zOTk5IDIuMjQxNTYgMTQuMzk5OUg0Ljk2MTU2QzUuMzE1MDIgMTQuMzk5OSA1LjYwMTU2IDE0LjExMzQgNS42MDE1NiAxMy43NTk5VjExLjAzOTlDNS42MDE1NiAxMC42ODY0IDUuMzE1MDIgMTAuMzk5OSA0Ljk2MTU2IDEwLjM5OTlaIiBmaWxsPSIjZmZmIi8%2BCjxwYXRoIGQ9Ik0xMy43NTg0IDEuNjAwMUgxMS4wMzg0QzEwLjY4NSAxLjYwMDEgMTAuMzk4NCAxLjg4NjY0IDEwLjM5ODQgMi4yNDAxVjQuOTYwMUMxMC4zOTg0IDUuMzEzNTYgMTAuNjg1IDUuNjAwMSAxMS4wMzg0IDUuNjAwMUgxMy43NTg0QzE0LjExMTkgNS42MDAxIDE0LjM5ODQgNS4zMTM1NiAxNC4zOTg0IDQuOTYwMVYyLjI0MDFDMTQuMzk4NCAxLjg4NjY0IDE0LjExMTkgMS42MDAxIDEzLjc1ODQgMS42MDAxWiIgZmlsbD0iI2ZmZiIvPgo8cGF0aCBkPSJNNCAxMkwxMiA0TDQgMTJaIiBmaWxsPSIjZmZmIi8%2BCjxwYXRoIGQ9Ik00IDEyTDEyIDQiIHN0cm9rZT0iI2ZmZiIgc3Ryb2tlLXdpZHRoPSIxLjUiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIvPgo8L3N2Zz4K&logoColor=ffffff)](https://zread.ai/seascapenetwork/cws-rebrand-smartcontract)

一个功能完整的LP代币质押合约，支持线性释放奖励和基于签到的额外激励机制。

## 功能特性

### 核心功能

1. **灵活的质押支持**
   - 支持ERC20代币质押
   - 支持多种奖励代币类型（ERC20）
   - 锁定期质押，活动结束后一次性提取

2. **线性奖励释放**
   - 根据用户质押占TVL的比例分配奖励
   - 奖励按时间线性释放
   - Session结束后统一领取

3. **Boost奖励系统(签到激励)**
   - 每次签到需间隔至少5分钟(300秒)
   - 每次签到boost点数+1,无上限
   - 使用**分池权重法**计算boost奖励,由两部分组成:
     - **Stake部分** (γ权重): 按质押占比分配,与boost无关
     - **Hybrid部分** (1-γ权重): 按质押×boost的归一化乘积分配
   - 公式:
     ```
     用户boost奖励 = stake部分奖励 + hybrid部分奖励

     stake部分奖励 = γ × 总boost奖池 × (用户质押 / 总质押)

     hybrid部分奖励 = (1-γ) × 总boost奖池 × (用户s_i×b_i) / Σ(s_j×b_j)
       其中: s_i = 用户质押/总质押, b_i = 用户boost/总boost点数
     ```
   - gamma参数可配置(默认0.6),范围[0, 1],只能在session开始前设置

4. **Session管理**
   - 支持多个独立session
   - 全局时间不重叠检查
   - 新session需等前一session结束

5. **安全机制**
   - 重入保护（ReentrancyGuard）
   - 防重复提取检查
   - Owner权限管理
   - Session时间不重叠验证

## 技术规范

- **Solidity版本**: 0.8.20
- **编译器优化**: via-ir enabled, 200 runs
- **依赖库**: OpenZeppelin Contracts v5.0.2
- **目标网络**: BNB Chain (BSC)

## 合约架构

### 主要数据结构

```solidity
struct Session {
    address stakingToken;           // 质押代币 (ERC20)
    address rewardToken;            // LP质押奖励代币
    address checkInRewardToken;     // 签到奖励代币 (boost奖励)
    uint256 totalReward;            // LP质押总奖励数量
    uint256 checkInRewardPool;      // 签到奖励池总数量 (boost奖励池)
    uint256 startTime;              // 开始时间
    uint256 endTime;                // 结束时间
    uint256 totalStaked;            // 总质押量
    uint256 rewardPerSecond;        // 每秒奖励
    uint256 accRewardPerShare;      // 累积每份额奖励
    uint256 lastRewardTime;         // 上次更新时间
    uint256 totalWeightedStake;     // 加权质押总量 [保留用于兼容]
    uint256 totalBoostPoints;       // 全局boost点数总和 Σ(boost)
    uint256 gamma;                  // boost奖励分配参数(scaled by 1e18) 默认0.6
    bool active;                    // 是否激活
}

struct UserInfo {
    uint256 amount;                 // 用户质押量
    uint256 rewardDebt;             // 奖励债务
    uint256 boost;                  // boost点数(每次签到+1,无上限)
    uint40 lastCheckInTime;         // 最后签到时间(用于5分钟冷却)
    bool hasWithdrawn;              // 是否已提取
}
```

### 核心函数

#### Owner函数

- `createSession(params)` - 创建新的质押session
- `setGamma(sessionId, gamma)` - 设置session的gamma参数(仅在session开始前)

#### 用户函数

- `deposit(sessionId, amount)` - 质押代币
- `checkIn(sessionId)` - 签到增加boost(需间隔5分钟)
- `withdraw(sessionId)` - 提取本金和所有奖励(session结束后)

#### 查询函数

- `pendingReward(sessionId, user)` - 查询待领取LP质押奖励
- `pendingBoostReward(sessionId, user)` - 查询boost奖励(新)
- `getPendingRewards(sessionId, user)` - 同时查询质押奖励和boost奖励(新)
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

// 2. 签到增加boost点数(可多次签到,每次间隔5分钟)
lpStaking.checkIn(sessionId);  // boost = 1

// 等待5分钟后再次签到
// ... 5分钟后 ...
lpStaking.checkIn(sessionId);  // boost = 2

// 可以继续签到,每次boost+1
// ... 5分钟后 ...
lpStaking.checkIn(sessionId);  // boost = 3

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
- ✅ Gamma参数设置(边界值、权限控制、时间限制)
- ✅ 质押功能（ERC20）
- ✅ 签到机制（5分钟冷却）
- ✅ Boost递增和累积
- ✅ 多次签到测试
- ✅ 提取功能
- ✅ LP奖励计算准确性
- ✅ Boost奖励分配（分池权重法）
- ✅ 不同gamma值下的奖励分配
- ✅ 边界条件（gamma=0、gamma=1、无人签到等）
- ✅ getPendingRewards函数测试
- ✅ 多session场景
- ✅ Gas优化验证

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
- 🟡 签到需间隔至少5分钟(300秒)
- 🟢 可多次签到,每次boost+1,无上限
- 🔴 只能在session结束后提取
- 🔴 新session必须等前一session结束且时间不重叠
- 🟢 复存不会重置boost值

## 示例场景

### 场景: 标准LP质押与Boost奖励

```
Session配置:
- 质押代币: CWS-USDT LP
- LP奖励代币: ASTER
- Boost奖励池: 5,000 ASTER
- LP总奖励: 10,000 ASTER
- 持续时间: 30天
- Gamma: 0.6 (默认)

用户A: 质押3,000 LP，签到1次(boost=1)
  → LP奖励: 10,000 × 0.3 = 3,000 ASTER
  → Boost奖励:
     - Stake部分: 5,000 × 0.6 × 0.3 = 900 ASTER
     - Hybrid部分: 根据归一化的stake×boost计算
     - 总boost奖励 ≈ 1,100 ASTER

用户B: 质押3,000 LP，签到5次(boost=5)
  → LP奖励: 10,000 × 0.3 = 3,000 ASTER
  → Boost奖励:
     - Stake部分: 5,000 × 0.6 × 0.3 = 900 ASTER
     - Hybrid部分: 因boost更高,获得更多
     - 总boost奖励 ≈ 1,900 ASTER

用户C: 质押4,000 LP，不签到(boost=0)
  → LP奖励: 10,000 × 0.4 = 4,000 ASTER
  → Boost奖励:
     - Stake部分: 5,000 × 0.6 × 0.4 = 1,200 ASTER
     - Hybrid部分: 0 (没有签到)
     - 总boost奖励 = 1,200 ASTER

说明: Boost奖励既考虑质押占比,也激励签到行为,实现公平与激励的平衡
```

## 部署地址

### BSC主网
- 待部署

### BSC测试网
- **Staking合约**: `0xFF3808FAf86c7F439610128c5D5CA99e209A6063`
- **部署者**: `0x87D14D7964245bbfEd65344bdBE3fA87fa611385`
- **交易哈希**: `0x00a9a8e2ddce1b01a9b2f58f3377efa40b468c4c455ce3642d0cc756c9077884`
- **区块浏览器**: https://testnet.bscscan.com/address/0xFF3808FAf86c7F439610128c5D5CA99e209A6063

## 更新日志

### v3.0.0 - Boost奖励算法重构

**重大变更**:
- ✅ 实现**分池权重法**计算boost奖励
- ✅ 新增`gamma`参数控制stake/hybrid权重分配(默认0.6)
- ✅ 新增`totalBoostPoints`字段追踪全局boost点数
- ✅ 新增`setGamma()`函数允许在session开始前设置gamma
- ✅ 新增`pendingBoostReward()`函数(替代`pendingCheckInReward`)
- ✅ 新增`getPendingRewards()`函数同时查询两种奖励
- ✅ 移除BNB支持,仅支持ERC20代币
- ✅ 移除Pausable功能

**算法改进**:
- Boost奖励 = Stake部分(γ权重) + Hybrid部分(1-γ权重)
- Stake部分: 按质押占比分配,确保基础公平
- Hybrid部分: 按归一化的(质押×boost)分配,激励签到行为
- 边界处理: 无人签到时hybrid部分也按stake分配

**测试覆盖**:
- 新增gamma参数测试(边界值、权限、时间限制)
- 新增分池权重法测试(不同gamma值、不同boost组合)
- 新增getPendingRewards函数测试
- 更新所有boost奖励相关测试
- 总计50+测试用例

### v2.0.0 - 签到机制升级

**重大变更**:
- ✅ 移除"每个session只能签到一次"的限制
- ✅ 实现5分钟签到冷却机制
- ✅ Boost点数改为每次签到+1,无上限
- ✅ 使用`uint40`存储时间戳,优化gas消耗
- ✅ 更新`UserInfo`结构体:`hasCheckedIn` → `lastCheckInTime`

**Gas优化**:
- 首次签到: ~71,851 gas
- 后续签到: ~8,141 gas (节省89%)

## License

MIT

## 联系方式

- Website: [seascape.network](https://seascape.network)
- Twitter: [@SeascapeNetwork](https://twitter.com/SeascapeNetwork)
