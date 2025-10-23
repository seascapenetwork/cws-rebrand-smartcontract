# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

这是一个基于 Foundry 的 Solidity 智能合约项目,实现了 LP 代币质押与签到奖励系统。合约部署在 BNB Chain (BSC) 上。

**核心合约**: `src/Staking.sol` - LP质押合约,支持线性释放奖励和基于签到的额外激励(boost奖励)

## 开发环境

- **Solidity版本**: 0.8.20
- **框架**: Foundry (forge, cast)
- **依赖**: OpenZeppelin Contracts v5.0.2
- **目标链**: BNB Chain (BSC)
- **编译优化**: via-ir enabled, 200 runs

## 常用命令

### 编译和测试
```bash
# 编译合约
forge build

# 运行所有测试
forge test

# 运行特定测试
forge test --match-test testDeposit

# 详细输出
forge test -vvv

# Gas报告
forge test --gas-report

# 格式化代码
forge fmt
```

### 部署相关
```bash
# 部署到 BSC 测试网
forge create --rpc-url $BSC_TESTNET_RPC \
  --private-key $PRIVATE_KEY \
  --constructor-args $OWNER_ADDRESS \
  src/Staking.sol:Staking

# 验证合约
forge verify-contract \
  --chain-id 97 \
  --num-of-optimizations 200 \
  --constructor-args $(cast abi-encode "constructor(address)" $OWNER_ADDRESS) \
  $CONTRACT_ADDRESS \
  src/Staking.sol:Staking
```

### Cast工具命令
```bash
# 查询合约代码
cast code $CONTRACT_ADDRESS --rpc-url $RPC_URL

# 查询地址余额
cast balance $ADDRESS --rpc-url $RPC_URL

# 调用只读函数
cast call $CONTRACT_ADDRESS "function_signature" --rpc-url $RPC_URL

# 编码/解码ABI
cast abi-encode "function_signature" args...
cast abi-decode "function_signature" encoded_data

# 查询交易详情
cast tx $TX_HASH --rpc-url $RPC_URL

# 查询区块信息
cast block $BLOCK_NUMBER --rpc-url $RPC_URL
```

## 核心架构

### 合约结构 (src/Staking.sol)

**关键数据结构**:
- `Session`: 质押活动配置(代币地址、奖励池、时间范围、gamma参数等)
- `UserInfo`: 用户状态(质押量、奖励债务、boost点数、签到时间、提取状态)
- `CreateSessionParams`: Session创建参数结构体(避免stack too deep)

**核心机制**:

1. **线性奖励释放**
   - 基于质押占TVL比例分配奖励
   - 使用 `accRewardPerShare` 和 `rewardDebt` 机制计算待领取奖励
   - 奖励按秒线性释放 (`rewardPerSecond`)

2. **Boost奖励系统(分池权重法)**
   - 每次签到需间隔5分钟(300秒),每次boost+1,无上限
   - 使用 `gamma` 参数分配stake和hybrid权重(默认0.6)
   - Boost奖励 = Stake部分(γ × 奖励池 × 质押占比) + Hybrid部分((1-γ) × 奖励池 × 归一化的stake×boost乘积)
   - 核心函数: `pendingBoostReward()` 和 `getBoostRewardBreakdown()`

3. **Session管理**
   - 全局时间不重叠检查(新session必须等前一session结束)
   - Gamma参数只能在session开始前设置
   - Session结束后才能提取

**重要修饰符**:
- `sessionExists`: 检查session是否存在
- `sessionInProgress`: 检查session是否正在进行中
- `sessionEnded`: 检查session是否已结束
- `nonReentrant`: 重入保护(OpenZeppelin)
- `onlyOwner`: 仅owner可调用

### 关键函数

**Owner函数**:
- `createSession()`: 创建新的质押session
- `setGamma()`: 设置session的gamma参数(仅在session开始前)

**用户函数**:
- `deposit()`: 质押代币
- `checkIn()`: 签到增加boost(需间隔5分钟)
- `withdraw()`: 提取本金和所有奖励(session结束后)

**查询函数**:
- `pendingReward()`: 查询待领取LP质押奖励
- `pendingBoostReward()`: 查询boost奖励
- `getPendingRewards()`: 同时查询两种奖励
- `getBoostRewardBreakdown()`: 查询boost奖励的详细分解(stake部分+hybrid部分)
- `getSessionInfo()`: 获取session信息
- `getUserInfo()`: 获取用户信息

### 内部函数架构

**奖励更新**:
- `_updatePool()`: 更新pool的累积奖励状态
- `_getMultiplier()`: 计算时间乘数

**质押处理**:
- `_processDeposit()`: 处理质押逻辑(收获奖励、更新状态、转移代币)

**提取处理**:
- `_processWithdrawal()`: 处理提取逻辑(计算所有奖励、转移代币)
- `_safeTransferReward()`: 安全转移奖励代币

**Boost奖励计算**:
- `_calculateBoostReward()`: 实现分池权重法计算boost奖励
- 核心逻辑: 分为stake部分(按质押占比)和hybrid部分(按归一化的stake×boost)

## 测试覆盖

测试文件位于 `test/` 目录:
- `Staking.t.sol`: 主测试文件(Session创建、质押、签到、提取、奖励计算)
- `StakingRewardDebtFix.t.sol`: 奖励债务机制测试
- `StakingFlashLoanAttack.t.sol`: 闪电贷攻击防护测试

**测试覆盖项**:
- ✅ Session创建和时间重叠检查
- ✅ Gamma参数设置(边界值、权限、时间限制)
- ✅ 质押和提取功能
- ✅ 签到机制(5分钟冷却、多次签到)
- ✅ LP奖励计算准确性
- ✅ Boost奖励分配(分池权重法、不同gamma值)
- ✅ 边界条件(gamma=0、gamma=1、无人签到等)
- ✅ 安全性测试(重入攻击、闪电贷攻击)

## 部署信息

### BSC测试网
- **Staking合约**: `0xFF3808FAf86c7F439610128c5D5CA99e209A6063`
- **区块浏览器**: https://testnet.bscscan.com/address/0xFF3808FAf86c7F439610128c5D5CA99e209A6063

### RPC端点配置
- BSC主网: `https://bsc-dataseed.binance.org/`
- BSC测试网: `https://data-seed-prebsc-1-s1.binance.org:8545/`

## 开发注意事项

1. **代码修改规范**
   - 修改后必须列出文件列表(标注已有/新增)、函数名、行号
   - 保持代码简洁,仅修复关键问题
   - 尽量复用现有代码,避免引入新概念
   - 所有注释使用中文
   - 禁止在提示语、日志、注释中使用表情符号

2. **安全考虑**
   - 所有状态变更函数需要 `nonReentrant` 保护
   - Session一旦创建参数不可修改(除gamma在开始前可修改)
   - 质押期间资金完全锁定,只能在session结束后提取
   - 新session必须等前一session结束且时间不重叠

3. **Gas优化**
   - 使用 `uint40` 存储时间戳节省gas
   - 使用via-ir编译器优化
   - 签到操作首次~71K gas,后续~8K gas

4. **Boost奖励算法关键点**
   - 使用分池权重法,由gamma参数控制
   - Stake部分确保基础公平,Hybrid部分激励签到
   - 边界处理: 无人签到时hybrid部分也按stake分配
   - 计算中使用SCALER(1e18)保证精度

## 项目依赖

```toml
[dependencies]
openzeppelin-contracts = "5.0.2"
forge-std = "latest"
```

## 相关资源

- Foundry文档: https://book.getfoundry.sh/
- OpenZeppelin Contracts: https://docs.openzeppelin.com/contracts/
- BNB Chain文档: https://docs.bnbchain.org/
