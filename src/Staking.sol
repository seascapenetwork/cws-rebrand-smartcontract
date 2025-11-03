// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Staking - LP代币质押与签到奖励合约
/// @author Seascape Network
/// @notice 本合约支持ERC20代币质押，线性释放奖励，以及基于签到的额外激励
/// @dev 使用OpenZeppelin v5.0.2，Solidity 0.8.20，包含重入保护
contract Staking is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============================================
    // 常量
    // ============================================

    /// @notice 精度缩放因子，用于高精度计算
    uint256 private constant SCALER = 1e18;

    // ============================================
    // 数据结构
    // ============================================

    /// @notice 创建Session的参数结构体
    /// @dev 用于减少createSession函数的参数数量，避免stack too deep
    struct CreateSessionParams {
        address stakingToken;           // 质押代币地址 (仅支持ERC20)
        address rewardToken;            // LP质押奖励代币地址
        address checkInRewardToken;     // 签到奖励代币地址
        uint256 totalReward;            // LP质押总奖励数量
        uint256 checkInRewardPool;      // 签到奖励池总数量
        uint256 startTime;              // 活动开始时间(unix时间戳)
        uint256 endTime;                // 活动结束时间(unix时间戳)
    }

    /// @notice Session质押活动结构体
    /// @dev 每个session代表一轮独立的质押活动
    struct Session {
        address stakingToken;           // 质押代币地址 (仅支持ERC20)
        address rewardToken;            // LP质押奖励代币地址
        address checkInRewardToken;     // 签到奖励代币地址 (boost奖励)
        uint256 totalReward;            // LP质押总奖励数量
        uint256 checkInRewardPool;      // 签到奖励池总数量 (boost奖励池)
        uint256 startTime;              // 活动开始时间(unix时间戳)
        uint256 endTime;                // 活动结束时间(unix时间戳)
        uint256 totalStaked;            // 当前总质押量(TVL)
        uint256 rewardPerSecond;        // 每秒释放的奖励 = totalReward / duration
        uint256 accRewardPerShare;      // 累积的每份额奖励(scaled by SCALER)
        uint256 lastRewardTime;         // 上次更新奖励的时间
        uint256 totalBoostPoints;       // 全局boost点数总和 Σ(所有用户的签到点数)
        bool active;                    // session是否激活(防止重复使用)
    }

    /// @notice 用户信息结构体
    /// @dev 记录每个用户在特定session中的状态
    struct UserInfo {
        uint256 amount;                 // 用户质押数量
        uint256 rewardDebt;             // 奖励债务(用于计算待领取奖励)
        uint256 accumulatedReward;      // 累积的待领取奖励(deposit时自动收获但不发送)
        uint256 boost;                  // 用户累计签到点数(根据签到时的质押档位累加)
        uint40 lastCheckInTime;         // 最后一次签到时间戳(用于5分钟冷却检查)
        bool hasWithdrawn;              // 是否已提取(防止重复提取)
    }

    // ============================================
    // 状态变量
    // ============================================

    /// @notice 当前session ID计数器
    uint256 public currentSessionId;

    /// @notice sessionId => Session信息
    mapping(uint256 => Session) public sessions;

    /// @notice sessionId => user address => UserInfo
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    /// @notice 记录所有历史session的时间范围，用于检查重叠
    struct TimeRange {
        uint256 startTime;
        uint256 endTime;
    }
    TimeRange[] private sessionTimeRanges;

    // ============================================
    // 事件
    // ============================================

    /// @notice 当新session创建时触发
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

    /// @notice 当用户质押时触发
    event Deposited(
        uint256 indexed sessionId,
        address indexed user,
        uint256 amount,
        uint256 timestamp,
        uint256 totalStaked
    );

    /// @notice 当用户签到时触发
    event CheckedIn(
        uint256 indexed sessionId,
        address indexed user,
        uint256 timestamp
    );

    /// @notice 当用户提取时触发
    event Withdrawn(
        uint256 indexed sessionId,
        address indexed user,
        uint256 stakedAmount,
        uint256 rewardAmount,
        uint256 checkInReward,
        uint256 timestamp
    );

    // ============================================
    // 修饰符
    // ============================================

    /// @notice 检查session是否存在
    modifier sessionExists(uint256 _sessionId) {
        require(_sessionId > 0 && _sessionId <= currentSessionId, "Session does not exist");
        _;
    }

    /// @notice 检查session是否在活动期间
    modifier sessionInProgress(uint256 _sessionId) {
        Session storage session = sessions[_sessionId];
        require(block.timestamp >= session.startTime, "Session not started");
        require(block.timestamp <= session.endTime, "Session ended");
        _;
    }

    /// @notice 检查session是否已结束
    modifier sessionEnded(uint256 _sessionId) {
        Session storage session = sessions[_sessionId];
        require(block.timestamp > session.endTime, "Session not ended yet");
        _;
    }

    // ============================================
    // 构造函数
    // ============================================

    /// @notice 初始化合约
    /// @param _initialOwner 初始owner地址
    constructor(address _initialOwner) Ownable(_initialOwner) {
        currentSessionId = 0;
    }

    // ============================================
    // Owner函数
    // ============================================

    /// @notice 创建新的质押session
    /// @dev 必须确保时间不重叠，且owner拥有足够的奖励代币
    /// @param params 创建session的参数结构体
    function createSession(CreateSessionParams calldata params)
        external
        onlyOwner
    {
        // 参数验证
        require(params.startTime > block.timestamp, "Start time must be in future");
        require(params.endTime > params.startTime, "End time must be after start time");
        require(params.totalReward > 0, "Total reward must be greater than 0");
        require(params.checkInRewardPool > 0, "CheckIn reward pool must be greater than 0");

        // 检查时间是否与任何历史session重叠
        _checkTimeOverlap(params.startTime, params.endTime);

        // 检查最近一个session是否已结束
        if (currentSessionId > 0) {
            require(block.timestamp > sessions[currentSessionId].endTime, "Previous session not ended");
        }

        // 转入LP奖励代币 (仅支持ERC20)
        IERC20(params.rewardToken).safeTransferFrom(msg.sender, address(this), params.totalReward);

        // 转入签到奖励代币 (仅支持ERC20)
        IERC20(params.checkInRewardToken).safeTransferFrom(msg.sender, address(this), params.checkInRewardPool);

        // 创建新session
        _createNewSession(params);

        emit SessionCreated(
            currentSessionId,
            params.stakingToken,
            params.rewardToken,
            params.checkInRewardToken,
            params.totalReward,
            params.checkInRewardPool,
            params.startTime,
            params.endTime
        );
    }

    /// @notice 提取指定session未使用的boost奖励(仅在totalBoostPoints为0时可调用)
    /// @dev 只有owner可以调用，且只能在session结束后
    /// @param _sessionId Session ID
    function recoverUnusedBoostReward(uint256 _sessionId)
        external
        onlyOwner
        sessionExists(_sessionId)
        sessionEnded(_sessionId)
    {
        Session storage session = sessions[_sessionId];
        require(session.totalBoostPoints == 0, "Boost points exist, cannot recover");

        uint256 amount = session.checkInRewardPool;
        require(amount > 0, "No boost reward to recover");

        // 重置奖池金额，防止重复提取
        session.checkInRewardPool = 0;

        // 转出boost奖励代币到owner
        _safeTransfer(session.checkInRewardToken, owner(), amount);
    }

    // ============================================
    // 用户函数
    // ============================================

    /// @notice 用户质押代币到指定session
    /// @param _sessionId Session ID
    /// @param _amount 质押数量
    function deposit(uint256 _sessionId, uint256 _amount)
        external
        nonReentrant
        sessionExists(_sessionId)
        sessionInProgress(_sessionId)
    {
        require(_amount > 0, "Amount must be greater than 0");

        // 更新session奖励
        _updatePool(_sessionId);

        // 处理质押
        _processDeposit(_sessionId, _amount);
    }

    /// @notice 用户签到(需距离上次签到至少5分钟且质押量≥5 LP)
    /// @param _sessionId Session ID
    function checkIn(uint256 _sessionId)
        external
        nonReentrant
        sessionExists(_sessionId)
        sessionInProgress(_sessionId)
    {
        UserInfo storage user = userInfo[_sessionId][msg.sender];
        Session storage session = sessions[_sessionId];

        require(user.amount >= 5 ether, "Must stake at least 5 LP to check-in");
        require(block.timestamp >= user.lastCheckInTime + 300, "Check-in cooldown not expired");

        // 根据当前质押量判定档位并获取点数
        uint256 points = _getTierPoints(user.amount);
        require(points > 0, "Staked amount below minimum tier");

        // 增加用户累计点数
        user.boost += points;

        // 更新全局点数总和
        session.totalBoostPoints += points;

        // 更新最后签到时间
        user.lastCheckInTime = uint40(block.timestamp);

        emit CheckedIn(_sessionId, msg.sender, block.timestamp);
    }

    /// @notice 用户提取本金和所有奖励(只能在session结束后)
    /// @param _sessionId Session ID
    function withdraw(uint256 _sessionId)
        external
        nonReentrant
        sessionExists(_sessionId)
        sessionEnded(_sessionId)
    {
        UserInfo storage user = userInfo[_sessionId][msg.sender];
        require(user.amount > 0, "No staked amount");
        require(!user.hasWithdrawn, "Already withdrawn");

        // 更新pool到session结束时间
        _updatePool(_sessionId);

        // 计算奖励并执行提取
        _processWithdrawal(_sessionId, user);
    }

    // ============================================
    // 查询函数
    // ============================================

    /// @notice 查询用户待领取的LP质押奖励
    /// @param _sessionId Session ID
    /// @param _user 用户地址
    /// @return 待领取的LP质押奖励数量(包含已累积的和当前pending的)
    function pendingReward(uint256 _sessionId, address _user)
        external
        view
        sessionExists(_sessionId)
        returns (uint256)
    {
        Session storage session = sessions[_sessionId];
        UserInfo storage user = userInfo[_sessionId][_user];

        // 已累积的奖励
        uint256 accumulated = user.accumulatedReward;

        // 当前pending奖励
        if (user.amount > 0) {
            uint256 accRewardPerShare = session.accRewardPerShare;

            if (block.timestamp > session.lastRewardTime && session.totalStaked > 0) {
                uint256 timeElapsed = _getElapsedTime(_sessionId, session.lastRewardTime);
                uint256 reward = timeElapsed * session.rewardPerSecond;
                accRewardPerShare += (reward * SCALER) / session.totalStaked;
            }

            accumulated += (user.amount * accRewardPerShare / SCALER) - user.rewardDebt;
        }

        return accumulated;
    }

    /// @notice 查询用户的boost奖励(基于点数分配)
    /// @param _sessionId Session ID
    /// @param _user 用户地址
    /// @return boost奖励数量
    function pendingBoostReward(uint256 _sessionId, address _user)
        external
        view
        sessionExists(_sessionId)
        returns (uint256)
    {
        UserInfo storage user = userInfo[_sessionId][_user];
        return _calculateCheckInReward(_sessionId, user);
    }

    /// @notice 查询用户的所有待领取奖励(质押奖励 + boost奖励)
    /// @param _sessionId Session ID
    /// @param _user 用户地址
    /// @return stakingReward 质押奖励数量(包含已累积的和当前pending的)
    /// @return boostReward boost奖励数量
    function getPendingRewards(uint256 _sessionId, address _user)
        external
        view
        sessionExists(_sessionId)
        returns (uint256 stakingReward, uint256 boostReward)
    {
        Session storage session = sessions[_sessionId];
        UserInfo storage user = userInfo[_sessionId][_user];

        // 计算质押奖励 = 已累积的 + 当前pending
        stakingReward = user.accumulatedReward;

        if (user.amount > 0) {
            uint256 accRewardPerShare = session.accRewardPerShare;

            if (block.timestamp > session.lastRewardTime && session.totalStaked > 0) {
                uint256 timeElapsed = _getElapsedTime(_sessionId, session.lastRewardTime);
                uint256 reward = timeElapsed * session.rewardPerSecond;
                accRewardPerShare += (reward * SCALER) / session.totalStaked;
            }

            stakingReward += (user.amount * accRewardPerShare / SCALER) - user.rewardDebt;
        }

        // 计算boost奖励
        boostReward = _calculateCheckInReward(_sessionId, user);

        return (stakingReward, boostReward);
    }

    /// @notice 获取session信息
    /// @param _sessionId Session ID
    function getSessionInfo(uint256 _sessionId)
        external
        view
        sessionExists(_sessionId)
        returns (Session memory)
    {
        return sessions[_sessionId];
    }

    /// @notice 获取用户信息
    /// @param _sessionId Session ID
    /// @param _user 用户地址
    function getUserInfo(uint256 _sessionId, address _user)
        external
        view
        sessionExists(_sessionId)
        returns (UserInfo memory)
    {
        return userInfo[_sessionId][_user];
    }

    // ============================================
    // 内部函数
    // ============================================

    /// @notice 创建新session并记录
    /// @param params session参数
    function _createNewSession(CreateSessionParams calldata params) internal {
        currentSessionId++;

        sessions[currentSessionId] = Session({
            stakingToken: params.stakingToken,
            rewardToken: params.rewardToken,
            checkInRewardToken: params.checkInRewardToken,
            totalReward: params.totalReward,
            checkInRewardPool: params.checkInRewardPool,
            startTime: params.startTime,
            endTime: params.endTime,
            totalStaked: 0,
            rewardPerSecond: params.totalReward / (params.endTime - params.startTime),
            accRewardPerShare: 0,
            lastRewardTime: params.startTime,
            totalBoostPoints: 0,
            active: true
        });

        // 记录时间范围
        sessionTimeRanges.push(TimeRange({
            startTime: params.startTime,
            endTime: params.endTime
        }));
    }

    /// @notice 处理用户提取逻辑
    /// @param _sessionId Session ID
    /// @param user 用户信息引用
    function _processWithdrawal(uint256 _sessionId, UserInfo storage user) internal {
        Session storage session = sessions[_sessionId];

        // 计算LP质押奖励 = 已累积的 + 当前pending
        uint256 lpReward = user.accumulatedReward +
                          ((user.amount * session.accRewardPerShare / SCALER) - user.rewardDebt);

        // 计算签到奖励
        uint256 checkInReward = _calculateCheckInReward(_sessionId, user);

        uint256 stakedAmount = user.amount;

        // 标记已提取，防止重复提取
        user.hasWithdrawn = true;

        // 注意: 我们不更新 totalStaked 和 totalBoostPoints
        // 因为奖励应该基于session结束时的最终状态，而不是提取时的动态状态
        // 如果更新这些值，会导致后提取的用户获得不公平的高额奖励

        // 转出所有代币
        _transferWithdrawals(session, stakedAmount, lpReward, checkInReward);

        emit Withdrawn(_sessionId, msg.sender, stakedAmount, lpReward, checkInReward, block.timestamp);
    }

    /// @notice 计算boost奖励(基于点数分配)
    /// @param _sessionId Session ID
    /// @param user 用户信息
    /// @return boost奖励数量
    function _calculateCheckInReward(uint256 _sessionId, UserInfo storage user) internal view returns (uint256) {
        Session storage session = sessions[_sessionId];

        // 如果用户没有点数，返回0
        if (user.boost == 0) {
            return 0;
        }

        // 如果全局点数为0，返回0
        if (session.totalBoostPoints == 0) {
            return 0;
        }

        // 奖励 = 奖池 × (用户点数 / 总点数)
        return (session.checkInRewardPool * user.boost) / session.totalBoostPoints;
    }

    /// @notice 转出提取的代币
    /// @param session Session信息
    /// @param stakedAmount 质押本金
    /// @param lpReward LP奖励
    /// @param checkInReward 签到奖励
    function _transferWithdrawals(
        Session storage session,
        uint256 stakedAmount,
        uint256 lpReward,
        uint256 checkInReward
    ) internal {
        // 转出质押本金
        _safeTransfer(session.stakingToken, msg.sender, stakedAmount);

        // 转出LP质押奖励
        if (lpReward > 0) {
            _safeTransfer(session.rewardToken, msg.sender, lpReward);
        }

        // 转出签到奖励
        if (checkInReward > 0) {
            _safeTransfer(session.checkInRewardToken, msg.sender, checkInReward);
        }
    }

    /// @notice 处理质押逻辑
    /// @param _sessionId Session ID
    /// @param _amount 质押数量
    function _processDeposit(uint256 _sessionId, uint256 _amount) internal {
        Session storage session = sessions[_sessionId];
        UserInfo storage user = userInfo[_sessionId][msg.sender];

        // 转入质押代币 (仅支持ERC20)
        IERC20(session.stakingToken).safeTransferFrom(msg.sender, address(this), _amount);

        // 如果用户已有质押,先收获pending奖励到accumulatedReward
        if (user.amount > 0) {
            uint256 pending = (user.amount * session.accRewardPerShare / SCALER) - user.rewardDebt;
            if (pending > 0) {
                user.accumulatedReward += pending;
            }
        }

        // 更新用户状态
        user.amount += _amount;
        // 重新计算 rewardDebt: 这是标准的 MasterChef 模式
        // 在上面已经收获了 pending 奖励到 accumulatedReward,所以这里重新设置 rewardDebt 是正确的
        user.rewardDebt = user.amount * session.accRewardPerShare / SCALER;

        // 更新session总质押量
        session.totalStaked += _amount;

        emit Deposited(_sessionId, msg.sender, _amount, block.timestamp, session.totalStaked);
    }

    /// @notice 更新pool的奖励
    /// @param _sessionId Session ID
    function _updatePool(uint256 _sessionId) internal {
        Session storage session = sessions[_sessionId];

        uint256 currentTime = block.timestamp;
        if (currentTime <= session.lastRewardTime) {
            return;
        }

        if (session.totalStaked == 0) {
            session.lastRewardTime = currentTime > session.endTime ? session.endTime : currentTime;
            return;
        }

        uint256 timeElapsed = _getElapsedTime(_sessionId, session.lastRewardTime);
        uint256 reward = timeElapsed * session.rewardPerSecond;

        session.accRewardPerShare += (reward * SCALER) / session.totalStaked;
        session.lastRewardTime = currentTime > session.endTime ? session.endTime : currentTime;
    }

    /// @notice 计算从lastTime到现在的有效时间(不超过session结束时间)
    /// @param _sessionId Session ID
    /// @param _lastTime 上次更新时间
    /// @return 有效的时间间隔(秒)
    function _getElapsedTime(uint256 _sessionId, uint256 _lastTime) internal view returns (uint256) {
        Session storage session = sessions[_sessionId];
        uint256 currentTime = block.timestamp > session.endTime ? session.endTime : block.timestamp;

        if (currentTime <= _lastTime) {
            return 0;
        }

        return currentTime - _lastTime;
    }


    /// @notice 检查新session时间是否与历史重叠
    /// @param _startTime 新session开始时间
    /// @param _endTime 新session结束时间
    function _checkTimeOverlap(uint256 _startTime, uint256 _endTime) internal view {
        // 获取最后一个session的时间范围
        TimeRange memory lastRange = sessionTimeRanges.length > 0 ? sessionTimeRanges[sessionTimeRanges.length - 1] : TimeRange(0, 0);

        // 检查是否重叠: 新session的开始时间或结束时间与最后一个session的时间重叠
        bool overlap = (_startTime < lastRange.endTime && _endTime > lastRange.startTime);

        require(!overlap, "Session time overlaps with existing session");
    }


    /// @notice 根据质押量判定档位并返回对应点数
    /// @param _amount 质押数量
    /// @return 档位对应的点数(1-5)
    function _getTierPoints(uint256 _amount) internal pure returns (uint256) {
        if (_amount >= 50 ether) {
            return 5;
        } else if (_amount >= 30 ether) {
            return 4;
        } else if (_amount >= 20 ether) {
            return 3;
        } else if (_amount >= 10 ether) {
            return 2;
        } else if (_amount >= 5 ether) {
            return 1;
        } else {
            return 0;
        }
    }

    /// @notice 安全转账函数(仅支持ERC20)
    /// @param _token 代币地址
    /// @param _to 接收地址
    /// @param _amount 转账数量
    function _safeTransfer(address _token, address _to, uint256 _amount) internal {
        if (_amount == 0) {
            return;
        }

        IERC20(_token).safeTransfer(_to, _amount);
    }
}
