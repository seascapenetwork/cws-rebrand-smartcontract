// SPDX-License-Identifier: MIT
pragma solidity =0.8.20 ^0.8.20;

// lib/openzeppelin-contracts/contracts/utils/Address.sol

// OpenZeppelin Contracts (last updated v5.0.0) (utils/Address.sol)

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev The ETH balance of the account is not enough to perform the operation.
     */
    error AddressInsufficientBalance(address account);

    /**
     * @dev There's no code at `target` (it is not a contract).
     */
    error AddressEmptyCode(address target);

    /**
     * @dev A call to an address target failed. The target may have reverted.
     */
    error FailedInnerCall();

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://consensys.net/diligence/blog/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.8.20/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        if (address(this).balance < amount) {
            revert AddressInsufficientBalance(address(this));
        }

        (bool success, ) = recipient.call{value: amount}("");
        if (!success) {
            revert FailedInnerCall();
        }
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason or custom error, it is bubbled
     * up by this function (like regular Solidity function calls). However, if
     * the call reverted with no returned reason, this function reverts with a
     * {FailedInnerCall} error.
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        if (address(this).balance < value) {
            revert AddressInsufficientBalance(address(this));
        }
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Tool to verify that a low level call to smart-contract was successful, and reverts if the target
     * was not a contract or bubbling up the revert reason (falling back to {FailedInnerCall}) in case of an
     * unsuccessful call.
     */
    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata
    ) internal view returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            // only check if target is a contract if the call was successful and the return data is empty
            // otherwise we already know that it was a contract
            if (returndata.length == 0 && target.code.length == 0) {
                revert AddressEmptyCode(target);
            }
            return returndata;
        }
    }

    /**
     * @dev Tool to verify that a low level call was successful, and reverts if it wasn't, either by bubbling the
     * revert reason or with a default {FailedInnerCall} error.
     */
    function verifyCallResult(bool success, bytes memory returndata) internal pure returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            return returndata;
        }
    }

    /**
     * @dev Reverts with returndata if present. Otherwise reverts with {FailedInnerCall}.
     */
    function _revert(bytes memory returndata) private pure {
        // Look for revert reason and bubble it up if present
        if (returndata.length > 0) {
            // The easiest way to bubble the revert reason is using memory via assembly
            /// @solidity memory-safe-assembly
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        } else {
            revert FailedInnerCall();
        }
    }
}

// lib/openzeppelin-contracts/contracts/utils/Context.sol

// OpenZeppelin Contracts (last updated v5.0.1) (utils/Context.sol)

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}

// lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol

// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/IERC20.sol)

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

// lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol

// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/extensions/IERC20Permit.sol)

/**
 * @dev Interface of the ERC20 Permit extension allowing approvals to be made via signatures, as defined in
 * https://eips.ethereum.org/EIPS/eip-2612[EIP-2612].
 *
 * Adds the {permit} method, which can be used to change an account's ERC20 allowance (see {IERC20-allowance}) by
 * presenting a message signed by the account. By not relying on {IERC20-approve}, the token holder account doesn't
 * need to send a transaction, and thus is not required to hold Ether at all.
 *
 * ==== Security Considerations
 *
 * There are two important considerations concerning the use of `permit`. The first is that a valid permit signature
 * expresses an allowance, and it should not be assumed to convey additional meaning. In particular, it should not be
 * considered as an intention to spend the allowance in any specific way. The second is that because permits have
 * built-in replay protection and can be submitted by anyone, they can be frontrun. A protocol that uses permits should
 * take this into consideration and allow a `permit` call to fail. Combining these two aspects, a pattern that may be
 * generally recommended is:
 *
 * ```solidity
 * function doThingWithPermit(..., uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) public {
 *     try token.permit(msg.sender, address(this), value, deadline, v, r, s) {} catch {}
 *     doThing(..., value);
 * }
 *
 * function doThing(..., uint256 value) public {
 *     token.safeTransferFrom(msg.sender, address(this), value);
 *     ...
 * }
 * ```
 *
 * Observe that: 1) `msg.sender` is used as the owner, leaving no ambiguity as to the signer intent, and 2) the use of
 * `try/catch` allows the permit to fail and makes the code tolerant to frontrunning. (See also
 * {SafeERC20-safeTransferFrom}).
 *
 * Additionally, note that smart contract wallets (such as Argent or Safe) are not able to produce permit signatures, so
 * contracts should have entry points that don't rely on permit.
 */
interface IERC20Permit {
    /**
     * @dev Sets `value` as the allowance of `spender` over ``owner``'s tokens,
     * given ``owner``'s signed approval.
     *
     * IMPORTANT: The same issues {IERC20-approve} has related to transaction
     * ordering also apply here.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `deadline` must be a timestamp in the future.
     * - `v`, `r` and `s` must be a valid `secp256k1` signature from `owner`
     * over the EIP712-formatted function arguments.
     * - the signature must use ``owner``'s current nonce (see {nonces}).
     *
     * For more information on the signature format, see the
     * https://eips.ethereum.org/EIPS/eip-2612#specification[relevant EIP
     * section].
     *
     * CAUTION: See Security Considerations above.
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @dev Returns the current nonce for `owner`. This value must be
     * included whenever a signature is generated for {permit}.
     *
     * Every successful call to {permit} increases ``owner``'s nonce by one. This
     * prevents a signature from being used multiple times.
     */
    function nonces(address owner) external view returns (uint256);

    /**
     * @dev Returns the domain separator used in the encoding of the signature for {permit}, as defined by {EIP712}.
     */
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

// lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol

// OpenZeppelin Contracts (last updated v5.0.0) (utils/ReentrancyGuard.sol)

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    uint256 private _status;

    /**
     * @dev Unauthorized reentrant call.
     */
    error ReentrancyGuardReentrantCall();

    constructor() {
        _status = NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        if (_status == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }

        // Any calls to nonReentrant after this point will fail
        _status = ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == ENTERED;
    }
}

// lib/openzeppelin-contracts/contracts/access/Ownable.sol

// OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable.sol)

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * The initial owner is set to the address provided by the deployer. This can
 * later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @dev The owner is not a valid owner account. (eg. `address(0)`)
     */
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the address provided by the deployer as the initial owner.
     */
    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

// lib/openzeppelin-contracts/contracts/utils/Pausable.sol

// OpenZeppelin Contracts (last updated v5.0.0) (utils/Pausable.sol)

/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract Pausable is Context {
    bool private _paused;

    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    /**
     * @dev The operation failed because the contract is paused.
     */
    error EnforcedPause();

    /**
     * @dev The operation failed because the contract is not paused.
     */
    error ExpectedPause();

    /**
     * @dev Initializes the contract in unpaused state.
     */
    constructor() {
        _paused = false;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        _requirePaused();
        _;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Throws if the contract is paused.
     */
    function _requireNotPaused() internal view virtual {
        if (paused()) {
            revert EnforcedPause();
        }
    }

    /**
     * @dev Throws if the contract is not paused.
     */
    function _requirePaused() internal view virtual {
        if (!paused()) {
            revert ExpectedPause();
        }
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}

// lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol

// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/utils/SafeERC20.sol)

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using Address for address;

    /**
     * @dev An operation with an ERC20 token failed.
     */
    error SafeERC20FailedOperation(address token);

    /**
     * @dev Indicates a failed `decreaseAllowance` request.
     */
    error SafeERC20FailedDecreaseAllowance(address spender, uint256 currentAllowance, uint256 requestedDecrease);

    /**
     * @dev Transfer `value` amount of `token` from the calling contract to `to`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transfer, (to, value)));
    }

    /**
     * @dev Transfer `value` amount of `token` from `from` to `to`, spending the approval given by `from` to the
     * calling contract. If `token` returns no value, non-reverting calls are assumed to be successful.
     */
    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transferFrom, (from, to, value)));
    }

    /**
     * @dev Increase the calling contract's allowance toward `spender` by `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 oldAllowance = token.allowance(address(this), spender);
        forceApprove(token, spender, oldAllowance + value);
    }

    /**
     * @dev Decrease the calling contract's allowance toward `spender` by `requestedDecrease`. If `token` returns no
     * value, non-reverting calls are assumed to be successful.
     */
    function safeDecreaseAllowance(IERC20 token, address spender, uint256 requestedDecrease) internal {
        unchecked {
            uint256 currentAllowance = token.allowance(address(this), spender);
            if (currentAllowance < requestedDecrease) {
                revert SafeERC20FailedDecreaseAllowance(spender, currentAllowance, requestedDecrease);
            }
            forceApprove(token, spender, currentAllowance - requestedDecrease);
        }
    }

    /**
     * @dev Set the calling contract's allowance toward `spender` to `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful. Meant to be used with tokens that require the approval
     * to be set to zero before setting it to a non-zero value, such as USDT.
     */
    function forceApprove(IERC20 token, address spender, uint256 value) internal {
        bytes memory approvalCall = abi.encodeCall(token.approve, (spender, value));

        if (!_callOptionalReturnBool(token, approvalCall)) {
            _callOptionalReturn(token, abi.encodeCall(token.approve, (spender, 0)));
            _callOptionalReturn(token, approvalCall);
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address-functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data);
        if (returndata.length != 0 && !abi.decode(returndata, (bool))) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     *
     * This is a variant of {_callOptionalReturn} that silents catches all reverts and returns a bool instead.
     */
    function _callOptionalReturnBool(IERC20 token, bytes memory data) private returns (bool) {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We cannot use {Address-functionCall} here since this should return false
        // and not revert is the subcall reverts.

        (bool success, bytes memory returndata) = address(token).call(data);
        return success && (returndata.length == 0 || abi.decode(returndata, (bool))) && address(token).code.length > 0;
    }
}

// src/Staking.sol

/// @title Staking - LP代币质押与签到奖励合约
/// @author Seascape Network
/// @notice 本合约支持LP/ERC20/BNB质押，线性释放奖励，以及基于签到的额外激励
/// @dev 使用OpenZeppelin v5.0.2，Solidity 0.8.20，包含重入保护和暂停机制
contract Staking is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ============================================
    // 常量
    // ============================================

    /// @notice 精度缩放因子，用于高精度计算
    uint256 private constant SCALER = 1e18;

    /// @notice BNB原生代币的地址表示
    address private constant BNB_ADDRESS = address(0);

    // ============================================
    // 数据结构
    // ============================================

    /// @notice 创建Session的参数结构体
    /// @dev 用于减少createSession函数的参数数量，避免stack too deep
    struct CreateSessionParams {
        address stakingToken;           // 质押代币地址 (address(0)表示BNB)
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
        address stakingToken;           // 质押代币地址 (address(0)表示BNB)
        address rewardToken;            // LP质押奖励代币地址
        address checkInRewardToken;     // 签到奖励代币地址
        uint256 totalReward;            // LP质押总奖励数量
        uint256 checkInRewardPool;      // 签到奖励池总数量
        uint256 startTime;              // 活动开始时间(unix时间戳)
        uint256 endTime;                // 活动结束时间(unix时间戳)
        uint256 totalStaked;            // 当前总质押量(TVL)
        uint256 rewardPerSecond;        // 每秒释放的奖励 = totalReward / duration
        uint256 accRewardPerShare;      // 累积的每份额奖励(scaled by SCALER)
        uint256 lastRewardTime;         // 上次更新奖励的时间
        uint256 totalWeightedStake;     // 全局加权质押量 Σ(用户质押 × boost点数)
        bool active;                    // session是否激活(防止重复使用)
    }

    /// @notice 用户信息结构体
    /// @dev 记录每个用户在特定session中的状态
    struct UserInfo {
        uint256 amount;                 // 用户质押数量
        uint256 rewardDebt;             // 奖励债务(用于计算待领取奖励)
        uint256 boost;                  // 用户boost点数(每次签到+1，无上限)
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
        payable
        onlyOwner
        whenNotPaused
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

        // 缓存地址值以减少stack使用
        address _rewardToken = params.rewardToken;
        address _checkInToken = params.checkInRewardToken;

        // 转入LP奖励代币
        if (_rewardToken != BNB_ADDRESS) {
            require(IERC20(_rewardToken).transferFrom(msg.sender, address(this), params.totalReward), "Reward transfer failed");
        } else {
            require(msg.value >= params.totalReward, "Insufficient BNB for reward");
        }

        // 转入签到奖励代币
        if (_checkInToken != BNB_ADDRESS) {
            require(IERC20(_checkInToken).transferFrom(msg.sender, address(this), params.checkInRewardPool), "CheckIn transfer failed");
        } else {
            if (_rewardToken == BNB_ADDRESS) {
                require(msg.value >= params.totalReward + params.checkInRewardPool, "Insufficient BNB");
            } else {
                require(msg.value >= params.checkInRewardPool, "Insufficient BNB");
            }
        }

        // 创建新session
        _createNewSession(params);

        emit SessionCreated(
            currentSessionId,
            params.stakingToken,
            _rewardToken,
            _checkInToken,
            params.totalReward,
            params.checkInRewardPool,
            params.startTime,
            params.endTime
        );
    }

    /// @notice 暂停合约
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice 恢复合约
    function unpause() external onlyOwner {
        _unpause();
    }

    // ============================================
    // 用户函数
    // ============================================

    /// @notice 用户质押代币到指定session
    /// @param _sessionId Session ID
    /// @param _amount 质押数量
    function deposit(uint256 _sessionId, uint256 _amount)
        external
        payable
        nonReentrant
        whenNotPaused
        sessionExists(_sessionId)
        sessionInProgress(_sessionId)
    {
        require(_amount > 0, "Amount must be greater than 0");

        // 更新session奖励
        _updatePool(_sessionId);

        // 处理质押
        _processDeposit(_sessionId, _amount);
    }

    /// @notice 用户签到(需距离上次签到至少5分钟)
    /// @param _sessionId Session ID
    function checkIn(uint256 _sessionId)
        external
        nonReentrant
        whenNotPaused
        sessionExists(_sessionId)
        sessionInProgress(_sessionId)
    {
        UserInfo storage user = userInfo[_sessionId][msg.sender];
        Session storage session = sessions[_sessionId];

        require(user.amount > 0, "Must stake before check-in");
        require(block.timestamp >= user.lastCheckInTime + 300, "Check-in cooldown not expired");

        // 更新全局加权质押量: 从 (amount * oldBoost) 变为 (amount * newBoost)
        uint256 oldWeightedStake = user.amount * user.boost;
        user.boost += 1;
        uint256 newWeightedStake = user.amount * user.boost;

        session.totalWeightedStake = session.totalWeightedStake - oldWeightedStake + newWeightedStake;

        // 更新最后签到时间
        user.lastCheckInTime = uint40(block.timestamp);

        emit CheckedIn(_sessionId, msg.sender, block.timestamp);
    }

    /// @notice 用户提取本金和所有奖励(只能在session结束后)
    /// @param _sessionId Session ID
    function withdraw(uint256 _sessionId)
        external
        nonReentrant
        whenNotPaused
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
    /// @return 待领取的LP质押奖励数量
    function pendingReward(uint256 _sessionId, address _user)
        external
        view
        sessionExists(_sessionId)
        returns (uint256)
    {
        Session storage session = sessions[_sessionId];
        UserInfo storage user = userInfo[_sessionId][_user];

        if (user.amount == 0) {
            return 0;
        }

        uint256 accRewardPerShare = session.accRewardPerShare;

        if (block.timestamp > session.lastRewardTime && session.totalStaked > 0) {
            uint256 timeElapsed = _getElapsedTime(_sessionId, session.lastRewardTime);
            uint256 reward = timeElapsed * session.rewardPerSecond;
            accRewardPerShare += (reward * SCALER) / session.totalStaked;
        }

        return (user.amount * accRewardPerShare / SCALER) - user.rewardDebt;
    }

    /// @notice 查询用户的签到奖励(只有session结束后才能准确计算)
    /// @param _sessionId Session ID
    /// @param _user 用户地址
    /// @return 签到奖励数量
    function pendingCheckInReward(uint256 _sessionId, address _user)
        external
        view
        sessionExists(_sessionId)
        returns (uint256)
    {
        Session storage session = sessions[_sessionId];
        UserInfo storage user = userInfo[_sessionId][_user];

        if (user.boost == 0 || session.totalWeightedStake == 0) {
            return 0;
        }

        uint256 userWeightedStake = user.amount * user.boost;
        return (session.checkInRewardPool * userWeightedStake) / session.totalWeightedStake;
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
            totalWeightedStake: 0,
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

        // 计算LP质押奖励
        uint256 lpReward = (user.amount * session.accRewardPerShare / SCALER) - user.rewardDebt;

        // 计算签到奖励
        uint256 checkInReward = _calculateCheckInReward(_sessionId, user);

        uint256 stakedAmount = user.amount;

        // 标记已提取，防止重复提取
        user.hasWithdrawn = true;

        // 更新全局状态
        session.totalStaked -= stakedAmount;
        if (user.boost > 0) {
            session.totalWeightedStake -= (user.amount * user.boost);
        }

        // 转出所有代币
        _transferWithdrawals(session, stakedAmount, lpReward, checkInReward);

        emit Withdrawn(_sessionId, msg.sender, stakedAmount, lpReward, checkInReward, block.timestamp);
    }

    /// @notice 计算签到奖励
    /// @param _sessionId Session ID
    /// @param user 用户信息
    /// @return 签到奖励数量
    function _calculateCheckInReward(uint256 _sessionId, UserInfo storage user) internal view returns (uint256) {
        if (user.boost == 0) {
            return 0;
        }

        Session storage session = sessions[_sessionId];
        if (session.totalWeightedStake == 0) {
            return 0;
        }

        uint256 userWeightedStake = user.amount * user.boost;
        return (session.checkInRewardPool * userWeightedStake) / session.totalWeightedStake;
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

        // 转入质押代币
        if (session.stakingToken != BNB_ADDRESS) {
            require(msg.value == 0, "Do not send BNB for ERC20 staking");
            IERC20(session.stakingToken).safeTransferFrom(msg.sender, address(this), _amount);
        } else {
            require(msg.value == _amount, "Incorrect BNB amount");
        }

        // 更新用户状态
        user.amount += _amount;
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
        for (uint256 i = 0; i < sessionTimeRanges.length; i++) {
            TimeRange memory range = sessionTimeRanges[i];

            // 检查是否重叠: 新区间的开始时间在旧区间内，或新区间的结束时间在旧区间内，或新区间完全包含旧区间
            bool overlap = (_startTime < range.endTime && _endTime > range.startTime);

            require(!overlap, "Session time overlaps with existing session");
        }
    }

    /// @notice 安全转账函数(支持BNB和ERC20)
    /// @param _token 代币地址 (address(0)表示BNB)
    /// @param _to 接收地址
    /// @param _amount 转账数量
    function _safeTransfer(address _token, address _to, uint256 _amount) internal {
        if (_amount == 0) {
            return;
        }

        if (_token == BNB_ADDRESS) {
            (bool success, ) = payable(_to).call{value: _amount}("");
            require(success, "BNB transfer failed");
        } else {
            IERC20(_token).safeTransfer(_to, _amount);
        }
    }

    // ============================================
    // 接收BNB
    // ============================================

    /// @notice 接收BNB (用于owner存入奖励)
    receive() external payable {}
}

