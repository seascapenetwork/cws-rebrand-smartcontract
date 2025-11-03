# Staking 合约前端接口文档

**合约地址**: `0xFF3808FAf86c7F439610128c5D5CA99e209A6063` (BSC测试网)
**Solidity版本**: 0.8.20
**网络**: BNB Chain (BSC)

---

## 目录

- [核心概念](#核心概念)
- [数据结构](#数据结构)
- [Owner专用函数](#owner专用函数)
- [用户函数](#用户函数)
- [查询函数](#查询函数)
- [事件](#事件)
- [错误处理](#错误处理)

---

## 核心概念

### Session (质押活动)
每个Session代表一轮独立的质押活动，包含：
- 质押代币、奖励代币、签到奖励代币
- 活动时间范围（开始/结束时间）
- 奖励池配置

### 双重奖励机制
1. **LP质押奖励**: 基于质押量和时间线性释放
2. **Boost签到奖励**: 基于签到获得的点数比例分配

### 档位积分系统
用户每次签到根据当前质押量获得对应点数：
```
质押量 ≥ 50 LP → 5点
质押量 ≥ 30 LP → 4点
质押量 ≥ 20 LP → 3点
质押量 ≥ 10 LP → 2点
质押量 ≥ 5 LP  → 1点
质押量 < 5 LP  → 无法签到
```

签到规则：
- 最低要求：质押量 ≥ 5 LP
- 签到冷却：距离上次签到至少5分钟（300秒）
- 点数累积：无上限，可多次签到

---

## 数据结构

### CreateSessionParams
```solidity
struct CreateSessionParams {
    address stakingToken;        // 质押代币地址
    address rewardToken;         // LP奖励代币地址
    address checkInRewardToken;  // 签到奖励代币地址
    uint256 totalReward;         // LP奖励总量
    uint256 checkInRewardPool;   // 签到奖励总量
    uint256 startTime;           // 开始时间(unix timestamp)
    uint256 endTime;             // 结束时间(unix timestamp)
}
```

### Session
```solidity
struct Session {
    address stakingToken;        // 质押代币地址
    address rewardToken;         // LP奖励代币地址
    address checkInRewardToken;  // 签到奖励代币地址
    uint256 totalReward;         // LP奖励总量
    uint256 checkInRewardPool;   // 签到奖励总量
    uint256 startTime;           // 开始时间
    uint256 endTime;             // 结束时间
    uint256 totalStaked;         // 当前总质押量(TVL)
    uint256 rewardPerSecond;     // 每秒释放奖励
    uint256 accRewardPerShare;   // 累积每份额奖励
    uint256 lastRewardTime;      // 最后更新时间
    uint256 totalBoostPoints;    // 全局签到点数总和
    bool active;                 // 是否激活
}
```

### UserInfo
```solidity
struct UserInfo {
    uint256 amount;              // 用户质押数量
    uint256 rewardDebt;          // 奖励债务(内部计算用)
    uint256 accumulatedReward;   // 已累积待领取奖励
    uint256 boost;               // 用户累计签到点数
    uint40 lastCheckInTime;      // 最后签到时间
    bool hasWithdrawn;           // 是否已提取
}
```

---

## Owner专用函数

### 1. createSession

**函数签名**:
```solidity
function createSession(CreateSessionParams calldata params) external onlyOwner
```

**功能描述**:
创建新的质押活动Session。合约会转入LP奖励代币和签到奖励代币。

**参数说明**:
| 参数 | 类型 | 说明 |
|------|------|------|
| params | CreateSessionParams | Session参数结构体 |

**前置条件**:
- 调用者必须是owner
- startTime必须大于当前时间
- endTime必须大于startTime
- totalReward和checkInRewardPool必须大于0
- 新Session时间不能与历史Session重叠
- 上一个Session必须已结束
- Owner需要先approve足够的奖励代币给合约

**使用场景**:
项目方创建新的质押活动，设置活动时间和奖励配置。

**注意事项**:
- Session一旦创建，参数不可修改
- 必须等待前一个Session完全结束才能创建新的
- 创建前需要调用代币合约的approve授权

**Web3调用示例**:
```javascript
// 1. 先授权奖励代币
await rewardTokenContract.methods.approve(
    stakingContractAddress,
    totalReward
).send({ from: ownerAddress });

await checkInRewardTokenContract.methods.approve(
    stakingContractAddress,
    checkInRewardPool
).send({ from: ownerAddress });

// 2. 创建Session
const params = {
    stakingToken: "0x...",        // LP代币地址
    rewardToken: "0x...",          // 奖励代币地址
    checkInRewardToken: "0x...",   // 签到奖励代币地址
    totalReward: "10000000000000000000000", // 10000 tokens (18 decimals)
    checkInRewardPool: "5000000000000000000000", // 5000 tokens
    startTime: Math.floor(Date.now() / 1000) + 86400, // 1天后开始
    endTime: Math.floor(Date.now() / 1000) + 86400 + 2592000 // 持续30天
};

await stakingContract.methods.createSession(params)
    .send({ from: ownerAddress });
```

**事件**:
```solidity
event SessionCreated(
    uint256 indexed sessionId,
    address indexed stakingToken,
    address indexed rewardToken,
    address checkInRewardToken,
    uint256 totalReward,
    uint256 checkInRewardPool,
    uint256 startTime,
    uint256 endTime
);
```

---

### 2. recoverUnusedBoostReward

**函数签名**:
```solidity
function recoverUnusedBoostReward(uint256 _sessionId) external onlyOwner
```

**功能描述**:
回收指定Session未使用的签到奖励（仅当无人签到时，即totalBoostPoints=0）。

**参数说明**:
| 参数 | 类型 | 说明 |
|------|------|------|
| _sessionId | uint256 | Session ID |

**前置条件**:
- 调用者必须是owner
- Session必须存在
- Session必须已结束
- Session的totalBoostPoints必须为0（无人签到）
- checkInRewardPool必须大于0

**使用场景**:
当某个Session结束后无人签到，owner可以回收签到奖励池中的代币。

**注意事项**:
- 只要有任何人签到过（totalBoostPoints > 0），就无法回收
- 每个Session只能回收一次
- 回收后checkInRewardPool归零

**Web3调用示例**:
```javascript
// 先查询Session信息确认totalBoostPoints为0
const sessionInfo = await stakingContract.methods.getSessionInfo(sessionId).call();
if (sessionInfo.totalBoostPoints === "0") {
    await stakingContract.methods.recoverUnusedBoostReward(sessionId)
        .send({ from: ownerAddress });
}
```

**可能的错误**:
- `"Session does not exist"` - Session不存在
- `"Session not ended yet"` - Session未结束
- `"Boost points exist, cannot recover"` - 有人签到过
- `"No boost reward to recover"` - 奖池已为0

---

## 用户函数

### 3. deposit

**函数签名**:
```solidity
function deposit(uint256 _sessionId, uint256 _amount) external nonReentrant
```

**功能描述**:
用户质押代币到指定Session。可以多次质押，质押量会累加。

**参数说明**:
| 参数 | 类型 | 说明 |
|------|------|------|
| _sessionId | uint256 | Session ID |
| _amount | uint256 | 质押数量（wei单位，需要乘以10^18） |

**前置条件**:
- Session必须存在
- Session必须在进行中（当前时间在startTime和endTime之间）
- _amount必须大于0
- 用户需要先approve足够的质押代币给合约

**使用场景**:
- 用户首次参与质押
- 用户追加质押以提升档位
- 用户在Session期间增加质押量

**注意事项**:
- 每次deposit会自动收获当前pending的LP奖励到accumulatedReward
- 可以多次deposit，质押量累加
- 增加质押量会影响下次签到的档位和点数
- Session期间可以随时deposit，但只能在Session结束后withdraw

**Web3调用示例**:
```javascript
// 1. 先授权质押代币
const amount = web3.utils.toWei("100", "ether"); // 100 tokens
await lpTokenContract.methods.approve(
    stakingContractAddress,
    amount
).send({ from: userAddress });

// 2. 质押
await stakingContract.methods.deposit(sessionId, amount)
    .send({ from: userAddress });
```

**事件**:
```solidity
event Deposited(
    uint256 indexed sessionId,
    address indexed user,
    uint256 amount,
    uint256 timestamp,
    uint256 totalStaked
);
```

**可能的错误**:
- `"Session does not exist"` - Session不存在
- `"Session not started"` - Session未开始
- `"Session ended"` - Session已结束
- `"Amount must be greater than 0"` - 金额为0

---

### 4. checkIn

**函数签名**:
```solidity
function checkIn(uint256 _sessionId) external nonReentrant
```

**功能描述**:
用户签到以获得boost点数。根据当前质押量判定档位，获得对应点数。

**参数说明**:
| 参数 | 类型 | 说明 |
|------|------|------|
| _sessionId | uint256 | Session ID |

**前置条件**:
- Session必须存在
- Session必须在进行中
- 用户质押量必须 ≥ 5 LP（5 ether in wei）
- 距离上次签到必须 ≥ 5分钟（300秒）

**使用场景**:
- 用户定期签到累积boost点数
- 质押后立即首次签到
- 充值提升档位后重新签到获得更高点数

**档位规则**:
```
质押 ≥ 50 LP → 获得 5点
质押 ≥ 30 LP → 获得 4点
质押 ≥ 20 LP → 获得 3点
质押 ≥ 10 LP → 获得 2点
质押 ≥ 5 LP  → 获得 1点
质押 < 5 LP  → 无法签到
```

**注意事项**:
- 签到冷却时间为5分钟（300秒）
- 每次签到根据**当前质押量**判定档位
- 点数无上限，可以无限累积
- 签到不消耗gas之外的任何费用
- 可以在充值后再次签到以获得更高档位的点数

**Web3调用示例**:
```javascript
// 检查是否满足签到条件
const userInfo = await stakingContract.methods.getUserInfo(sessionId, userAddress).call();
const currentTime = Math.floor(Date.now() / 1000);
const canCheckIn = userInfo.amount >= web3.utils.toWei("5", "ether") &&
                   currentTime >= parseInt(userInfo.lastCheckInTime) + 300;

if (canCheckIn) {
    await stakingContract.methods.checkIn(sessionId)
        .send({ from: userAddress });
}
```

**事件**:
```solidity
event CheckedIn(
    uint256 indexed sessionId,
    address indexed user,
    uint256 timestamp
);
```

**可能的错误**:
- `"Session does not exist"` - Session不存在
- `"Session not started"` - Session未开始
- `"Session ended"` - Session已结束
- `"Must stake at least 5 LP to check-in"` - 质押量不足5 LP
- `"Check-in cooldown not expired"` - 签到冷却未过期
- `"Staked amount below minimum tier"` - 质押量低于最低档位（理论上与上面重复）

---

### 5. withdraw

**函数签名**:
```solidity
function withdraw(uint256 _sessionId) external nonReentrant
```

**功能描述**:
用户提取本金和所有奖励（LP质押奖励 + Boost签到奖励）。只能在Session结束后调用。

**参数说明**:
| 参数 | 类型 | 说明 |
|------|------|------|
| _sessionId | uint256 | Session ID |

**前置条件**:
- Session必须存在
- Session必须已结束（当前时间 > endTime）
- 用户必须有质押（amount > 0）
- 用户未曾提取过（hasWithdrawn = false）

**使用场景**:
Session结束后，用户提取本金和所有奖励。

**返回内容**:
一次性转出三种代币：
1. 质押本金（stakingToken）
2. LP质押奖励（rewardToken）
3. Boost签到奖励（checkInRewardToken）

**注意事项**:
- 每个用户每个Session只能withdraw一次
- 必须等Session完全结束后才能withdraw
- 提取后hasWithdrawn标记为true，防止重复提取
- 如果未曾签到，签到奖励为0
- 三种代币可能是不同的ERC20代币，注意接收

**Web3调用示例**:
```javascript
// 检查Session是否结束
const sessionInfo = await stakingContract.methods.getSessionInfo(sessionId).call();
const currentTime = Math.floor(Date.now() / 1000);

if (currentTime > sessionInfo.endTime) {
    // 先查询待领取奖励
    const rewards = await stakingContract.methods.getPendingRewards(sessionId, userAddress).call();
    console.log("LP奖励:", web3.utils.fromWei(rewards.stakingReward, "ether"));
    console.log("Boost奖励:", web3.utils.fromWei(rewards.boostReward, "ether"));

    // 提取
    await stakingContract.methods.withdraw(sessionId)
        .send({ from: userAddress });
}
```

**事件**:
```solidity
event Withdrawn(
    uint256 indexed sessionId,
    address indexed user,
    uint256 stakedAmount,
    uint256 rewardAmount,
    uint256 checkInReward,
    uint256 timestamp
);
```

**可能的错误**:
- `"Session does not exist"` - Session不存在
- `"Session not ended yet"` - Session未结束
- `"No staked amount"` - 没有质押
- `"Already withdrawn"` - 已经提取过

---

## 查询函数

### 6. pendingReward

**函数签名**:
```solidity
function pendingReward(uint256 _sessionId, address _user) external view returns (uint256)
```

**功能描述**:
查询用户待领取的LP质押奖励（不包括boost奖励）。

**参数说明**:
| 参数 | 类型 | 说明 |
|------|------|------|
| _sessionId | uint256 | Session ID |
| _user | address | 用户地址 |

**返回值**:
| 类型 | 说明 |
|------|------|
| uint256 | 待领取的LP质押奖励数量（wei单位） |

**使用场景**:
- 前端展示用户当前LP质押奖励
- 计算预期收益
- withdraw前查看奖励金额

**计算逻辑**:
```
LP奖励 = accumulatedReward + (当前pending奖励)
当前pending = (用户质押量 × 累积每份额奖励 / SCALER) - 奖励债务
```

**Web3调用示例**:
```javascript
const reward = await stakingContract.methods.pendingReward(sessionId, userAddress).call();
console.log("待领取LP奖励:", web3.utils.fromWei(reward, "ether"), "tokens");
```

---

### 7. pendingBoostReward

**函数签名**:
```solidity
function pendingBoostReward(uint256 _sessionId, address _user) external view returns (uint256)
```

**功能描述**:
查询用户待领取的Boost签到奖励。

**参数说明**:
| 参数 | 类型 | 说明 |
|------|------|------|
| _sessionId | uint256 | Session ID |
| _user | address | 用户地址 |

**返回值**:
| 类型 | 说明 |
|------|------|
| uint256 | 待领取的Boost奖励数量（wei单位） |

**使用场景**:
- 前端展示用户签到奖励
- 激励用户签到
- withdraw前查看奖励金额

**计算逻辑**:
```
Boost奖励 = checkInRewardPool × (用户点数 / 总点数)
```

**Web3调用示例**:
```javascript
const boostReward = await stakingContract.methods.pendingBoostReward(sessionId, userAddress).call();
console.log("待领取Boost奖励:", web3.utils.fromWei(boostReward, "ether"), "tokens");
```

---

### 8. getPendingRewards

**函数签名**:
```solidity
function getPendingRewards(uint256 _sessionId, address _user)
    external view returns (uint256 stakingReward, uint256 boostReward)
```

**功能描述**:
一次性查询用户的LP质押奖励和Boost签到奖励。

**参数说明**:
| 参数 | 类型 | 说明 |
|------|------|------|
| _sessionId | uint256 | Session ID |
| _user | address | 用户地址 |

**返回值**:
| 参数 | 类型 | 说明 |
|------|------|------|
| stakingReward | uint256 | LP质押奖励数量（wei） |
| boostReward | uint256 | Boost签到奖励数量（wei） |

**使用场景**:
- 前端一次性获取所有奖励信息
- 减少RPC调用次数
- 展示总奖励预览

**Web3调用示例**:
```javascript
const rewards = await stakingContract.methods.getPendingRewards(sessionId, userAddress).call();
console.log("LP奖励:", web3.utils.fromWei(rewards.stakingReward, "ether"));
console.log("Boost奖励:", web3.utils.fromWei(rewards.boostReward, "ether"));
console.log("总奖励:", web3.utils.fromWei(
    (BigInt(rewards.stakingReward) + BigInt(rewards.boostReward)).toString(),
    "ether"
));
```

---

### 9. getSessionInfo

**函数签名**:
```solidity
function getSessionInfo(uint256 _sessionId) external view returns (Session memory)
```

**功能描述**:
获取指定Session的完整信息。

**参数说明**:
| 参数 | 类型 | 说明 |
|------|------|------|
| _sessionId | uint256 | Session ID |

**返回值**:
返回Session结构体，包含以下字段：
| 字段 | 类型 | 说明 |
|------|------|------|
| stakingToken | address | 质押代币地址 |
| rewardToken | address | LP奖励代币地址 |
| checkInRewardToken | address | 签到奖励代币地址 |
| totalReward | uint256 | LP奖励总量 |
| checkInRewardPool | uint256 | 签到奖励总量 |
| startTime | uint256 | 开始时间 |
| endTime | uint256 | 结束时间 |
| totalStaked | uint256 | 当前总质押量(TVL) |
| rewardPerSecond | uint256 | 每秒释放奖励 |
| accRewardPerShare | uint256 | 累积每份额奖励 |
| lastRewardTime | uint256 | 最后更新时间 |
| totalBoostPoints | uint256 | 全局签到点数总和 |
| active | bool | 是否激活 |

**使用场景**:
- 前端展示Session详细信息
- 获取TVL（totalStaked）
- 计算APR/APY
- 显示活动时间和状态

**Web3调用示例**:
```javascript
const session = await stakingContract.methods.getSessionInfo(sessionId).call();

console.log("质押代币:", session.stakingToken);
console.log("TVL:", web3.utils.fromWei(session.totalStaked, "ether"), "LP");
console.log("开始时间:", new Date(session.startTime * 1000).toLocaleString());
console.log("结束时间:", new Date(session.endTime * 1000).toLocaleString());
console.log("总签到点数:", session.totalBoostPoints);

// 计算Session进度
const now = Math.floor(Date.now() / 1000);
const duration = session.endTime - session.startTime;
const elapsed = now - session.startTime;
const progress = Math.min(100, Math.max(0, (elapsed / duration) * 100));
console.log("进度:", progress.toFixed(2) + "%");
```

---

### 10. getUserInfo

**函数签名**:
```solidity
function getUserInfo(uint256 _sessionId, address _user) external view returns (UserInfo memory)
```

**功能描述**:
获取用户在指定Session中的状态信息。

**参数说明**:
| 参数 | 类型 | 说明 |
|------|------|------|
| _sessionId | uint256 | Session ID |
| _user | address | 用户地址 |

**返回值**:
返回UserInfo结构体，包含以下字段：
| 字段 | 类型 | 说明 |
|------|------|------|
| amount | uint256 | 用户质押数量 |
| rewardDebt | uint256 | 奖励债务（内部计算用） |
| accumulatedReward | uint256 | 已累积待领取奖励 |
| boost | uint256 | 用户累计签到点数 |
| lastCheckInTime | uint40 | 最后签到时间戳 |
| hasWithdrawn | bool | 是否已提取 |

**使用场景**:
- 前端展示用户质押信息
- 显示用户累计签到点数
- 检查签到冷却时间
- 判断当前档位

**Web3调用示例**:
```javascript
const userInfo = await stakingContract.methods.getUserInfo(sessionId, userAddress).call();

console.log("质押数量:", web3.utils.fromWei(userInfo.amount, "ether"), "LP");
console.log("累计点数:", userInfo.boost);
console.log("最后签到:", new Date(userInfo.lastCheckInTime * 1000).toLocaleString());
console.log("已提取:", userInfo.hasWithdrawn);

// 判断当前档位
const amount = parseFloat(web3.utils.fromWei(userInfo.amount, "ether"));
let tier = 0;
if (amount >= 50) tier = 5;
else if (amount >= 30) tier = 4;
else if (amount >= 20) tier = 3;
else if (amount >= 10) tier = 2;
else if (amount >= 5) tier = 1;
console.log("当前档位:", tier, "点/次");

// 检查是否可以签到
const now = Math.floor(Date.now() / 1000);
const canCheckIn = amount >= 5 &&
                   now >= parseInt(userInfo.lastCheckInTime) + 300;
console.log("可以签到:", canCheckIn);
if (!canCheckIn && amount >= 5) {
    const cooldownRemaining = parseInt(userInfo.lastCheckInTime) + 300 - now;
    console.log("冷却剩余:", cooldownRemaining, "秒");
}
```

---

### 11. currentSessionId

**函数签名**:
```solidity
function currentSessionId() external view returns (uint256)
```

**功能描述**:
获取当前最新的Session ID。

**返回值**:
| 类型 | 说明 |
|------|------|
| uint256 | 当前Session ID计数器（从1开始） |

**使用场景**:
- 获取最新的Session ID
- 判断是否有活动Session
- 遍历所有Session

**Web3调用示例**:
```javascript
const latestSessionId = await stakingContract.methods.currentSessionId().call();
console.log("最新Session ID:", latestSessionId);

if (latestSessionId === "0") {
    console.log("暂无活动Session");
} else {
    // 获取最新Session信息
    const latestSession = await stakingContract.methods.getSessionInfo(latestSessionId).call();
    console.log("最新Session:", latestSession);
}
```

---

## 事件

### SessionCreated
```solidity
event SessionCreated(
    uint256 indexed sessionId,
    address indexed stakingToken,
    address indexed rewardToken,
    address checkInRewardToken,
    uint256 totalReward,
    uint256 checkInRewardPool,
    uint256 startTime,
    uint256 endTime
);
```
**触发时机**: 创建新Session时
**用途**: 监听新活动创建

### Deposited
```solidity
event Deposited(
    uint256 indexed sessionId,
    address indexed user,
    uint256 amount,
    uint256 timestamp,
    uint256 totalStaked
);
```
**触发时机**: 用户质押时
**用途**: 监听用户质押行为，更新TVL

### CheckedIn
```solidity
event CheckedIn(
    uint256 indexed sessionId,
    address indexed user,
    uint256 timestamp
);
```
**触发时机**: 用户签到时
**用途**: 监听签到行为，统计签到数据

### Withdrawn
```solidity
event Withdrawn(
    uint256 indexed sessionId,
    address indexed user,
    uint256 stakedAmount,
    uint256 rewardAmount,
    uint256 checkInReward,
    uint256 timestamp
);
```
**触发时机**: 用户提取时
**用途**: 监听提取行为，统计奖励发放

**事件监听示例**:
```javascript
// 监听所有Deposited事件
stakingContract.events.Deposited({
    filter: { sessionId: 1 },
    fromBlock: 'latest'
})
.on('data', event => {
    console.log('用户质押:', {
        user: event.returnValues.user,
        amount: web3.utils.fromWei(event.returnValues.amount, 'ether'),
        totalStaked: web3.utils.fromWei(event.returnValues.totalStaked, 'ether')
    });
});

// 监听特定用户的CheckedIn事件
stakingContract.events.CheckedIn({
    filter: { user: userAddress },
    fromBlock: 'latest'
})
.on('data', event => {
    console.log('签到成功:', new Date(event.returnValues.timestamp * 1000));
});
```

---

## 错误处理

### 常见错误及处理

| 错误信息 | 原因 | 解决方案 |
|---------|------|---------|
| `"Session does not exist"` | Session ID无效 | 检查Session ID是否正确 |
| `"Session not started"` | Session未开始 | 等待Session开始时间 |
| `"Session ended"` | Session已结束 | 此Session已结束，无法操作 |
| `"Session not ended yet"` | Session未结束 | 等待Session结束才能withdraw |
| `"Amount must be greater than 0"` | 金额为0 | 输入有效金额 |
| `"Must stake at least 5 LP to check-in"` | 质押不足5 LP | 增加质押量至≥5 LP |
| `"Check-in cooldown not expired"` | 签到冷却中 | 等待5分钟冷却时间 |
| `"No staked amount"` | 没有质押 | 先质押代币 |
| `"Already withdrawn"` | 已经提取过 | 每个Session只能提取一次 |
| `"Ownable: caller is not the owner"` | 非owner调用 | 仅owner可调用此函数 |

### 前端错误处理示例

```javascript
async function deposit(sessionId, amount) {
    try {
        const tx = await stakingContract.methods.deposit(sessionId, amount)
            .send({ from: userAddress });
        console.log("质押成功:", tx.transactionHash);
        return { success: true, tx };
    } catch (error) {
        // 解析错误信息
        if (error.message.includes("Session not started")) {
            return { success: false, error: "活动尚未开始" };
        } else if (error.message.includes("Session ended")) {
            return { success: false, error: "活动已结束" };
        } else if (error.message.includes("Amount must be greater than 0")) {
            return { success: false, error: "金额必须大于0" };
        } else {
            return { success: false, error: "交易失败: " + error.message };
        }
    }
}

async function checkIn(sessionId) {
    try {
        // 先检查条件
        const userInfo = await stakingContract.methods.getUserInfo(sessionId, userAddress).call();
        const amount = parseFloat(web3.utils.fromWei(userInfo.amount, "ether"));

        if (amount < 5) {
            return { success: false, error: "质押量不足5 LP，无法签到" };
        }

        const now = Math.floor(Date.now() / 1000);
        const cooldownEnd = parseInt(userInfo.lastCheckInTime) + 300;

        if (now < cooldownEnd) {
            const remaining = cooldownEnd - now;
            return {
                success: false,
                error: `签到冷却中，剩余${remaining}秒`
            };
        }

        // 执行签到
        const tx = await stakingContract.methods.checkIn(sessionId)
            .send({ from: userAddress });
        console.log("签到成功:", tx.transactionHash);
        return { success: true, tx };

    } catch (error) {
        return { success: false, error: "签到失败: " + error.message };
    }
}
```

---

## 完整使用流程示例

### 1. Owner创建Session
```javascript
// 步骤1: 授权奖励代币
await rewardToken.methods.approve(stakingContract.address, totalReward).send({from: owner});
await checkInRewardToken.methods.approve(stakingContract.address, checkInRewardPool).send({from: owner});

// 步骤2: 创建Session
const params = {
    stakingToken: lpTokenAddress,
    rewardToken: rewardTokenAddress,
    checkInRewardToken: checkInRewardTokenAddress,
    totalReward: web3.utils.toWei("10000", "ether"),
    checkInRewardPool: web3.utils.toWei("5000", "ether"),
    startTime: Math.floor(Date.now()/1000) + 86400,
    endTime: Math.floor(Date.now()/1000) + 86400 + 2592000
};
await stakingContract.methods.createSession(params).send({from: owner});
```

### 2. 用户参与质押
```javascript
// 步骤1: 授权LP代币
const amount = web3.utils.toWei("100", "ether");
await lpToken.methods.approve(stakingContract.address, amount).send({from: user});

// 步骤2: 质押
await stakingContract.methods.deposit(sessionId, amount).send({from: user});

// 步骤3: 签到
await stakingContract.methods.checkIn(sessionId).send({from: user});
```

### 3. 查询奖励
```javascript
const rewards = await stakingContract.methods.getPendingRewards(sessionId, userAddress).call();
console.log("LP奖励:", web3.utils.fromWei(rewards.stakingReward, "ether"));
console.log("Boost奖励:", web3.utils.fromWei(rewards.boostReward, "ether"));
```

### 4. 提取奖励
```javascript
// 等待Session结束
const session = await stakingContract.methods.getSessionInfo(sessionId).call();
if (Math.floor(Date.now()/1000) > session.endTime) {
    await stakingContract.methods.withdraw(sessionId).send({from: user});
}
```

---

## 附录

### ABI获取
可以通过以下命令获取合约ABI：
```bash
forge inspect Staking abi > Staking.abi.json
```

### 常用单位转换
```javascript
// Wei <-> Ether
const wei = web3.utils.toWei("100", "ether");    // 100 tokens -> wei
const ether = web3.utils.fromWei(wei, "ether");  // wei -> 100 tokens

// 时间戳转换
const timestamp = Math.floor(Date.now() / 1000); // JS时间 -> Unix时间戳
const date = new Date(timestamp * 1000);         // Unix时间戳 -> JS时间
```

### 合约地址
- **BSC测试网**: `0xFF3808FAf86c7F439610128c5D5CA99e209A6063`
- **BSC主网**: 待部署

### BSC RPC端点
- **主网**: `https://bsc-dataseed.binance.org/`
- **测试网**: `https://data-seed-prebsc-1-s1.binance.org:8545/`

### 区块浏览器
- **测试网**: https://testnet.bscscan.com/address/0xFF3808FAf86c7F439610128c5D5CA99e209A6063
- **主网**: https://bscscan.com/

---

**文档版本**: v1.0
**更新日期**: 2025-11-03
**合约版本**: Staking.sol (Boost点数系统版本)
