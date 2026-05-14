// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FTMonsterArcadeToken} from "./FTMonsterArcadeToken.sol";
import {IFTMonsterArcadeLauncher} from "./interfaces/IFTMonsterArcadeLauncher.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/types/BalanceDelta.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

/// @title FTMonsterArcadeSwapRouter
/// @notice Exact-input router for the canonical ETH / Oracle777 v4 pool.
contract FTMonsterArcadeSwapRouter is IUnlockCallback {
    using BalanceDeltaLibrary for BalanceDelta;

    uint256 private constant MAX_INT256_UINT = uint256(type(int256).max);

    enum Action {
        Buy,
        Sell
    }

    struct CallbackData {
        Action action;
        address payer;
        address recipient;
        uint256 amountIn;
        uint256 minAmountOut;
    }

    IPoolManager public immutable poolManager;
    FTMonsterArcadeToken public immutable token;
    IFTMonsterArcadeLauncher public immutable launcher;
    PoolKey public poolKey;
    address public owner;

    event Bought(address indexed account, uint256 ethIn, uint256 tokenOut);
    event Sold(address indexed account, uint256 tokenIn, uint256 ethOut);
    event OwnerTransferred(address indexed oldOwner, address indexed newOwner);
    event EthWithdrawn(address indexed to, uint256 amount);

    error InvalidPool();
    error NoEth();
    error NoToken();
    error AmountTooLarge();
    error InsufficientOutput();
    error NotPoolManager();
    error NotOwner();
    error ZeroAddress();
    error EthTransferFailed();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(
        IPoolManager poolManager_,
        PoolKey memory poolKey_,
        FTMonsterArcadeToken token_,
        IFTMonsterArcadeLauncher launcher_,
        address owner_
    ) {
        if (Currency.unwrap(poolKey_.currency0) != address(0) || Currency.unwrap(poolKey_.currency1) != address(token_))
        {
            revert InvalidPool();
        }
        if (owner_ == address(0)) revert ZeroAddress();
        poolManager = poolManager_;
        poolKey = poolKey_;
        token = token_;
        launcher = launcher_;
        owner = owner_;
        emit OwnerTransferred(address(0), owner_);
    }

    function buy(uint256 minTokenOut) external payable returns (uint256 tokenOut) {
        if (msg.value == 0) revert NoEth();
        if (msg.value > MAX_INT256_UINT) revert AmountTooLarge();

        tokenOut = abi.decode(
            poolManager.unlock(
                abi.encode(
                    CallbackData({
                        action: Action.Buy,
                        payer: msg.sender,
                        recipient: msg.sender,
                        amountIn: msg.value,
                        minAmountOut: minTokenOut
                    })
                )
            ),
            (uint256)
        );
        _refundEth(msg.sender);
        emit Bought(msg.sender, msg.value, tokenOut);
    }

    function sell(uint256 tokenIn, uint256 minEthOut) external returns (uint256 ethOut) {
        if (tokenIn == 0) revert NoToken();
        if (tokenIn > MAX_INT256_UINT) revert AmountTooLarge();

        ethOut = abi.decode(
            poolManager.unlock(
                abi.encode(
                    CallbackData({
                        action: Action.Sell,
                        payer: msg.sender,
                        recipient: msg.sender,
                        amountIn: tokenIn,
                        minAmountOut: minEthOut
                    })
                )
            ),
            (uint256)
        );
        emit Sold(msg.sender, tokenIn, ethOut);
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        CallbackData memory data = abi.decode(rawData, (CallbackData));

        if (data.action == Action.Buy) {
            return abi.encode(_buy(data));
        }
        return abi.encode(_sell(data));
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnerTransferred(owner, newOwner);
        owner = newOwner;
    }

    function withdrawEth(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        (bool ok,) = payable(to).call{value: amount}("");
        if (!ok) revert EthTransferFailed();
        emit EthWithdrawn(to, amount);
    }

    function withdrawAllEth(address to) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        uint256 amount = address(this).balance;
        (bool ok,) = payable(to).call{value: amount}("");
        if (!ok) revert EthTransferFailed();
        emit EthWithdrawn(to, amount);
    }

    function _buy(CallbackData memory data) internal returns (uint256 tokenOut) {
        poolManager.sync(poolKey.currency0);
        uint256 ethFee = (data.amountIn * launcher.currentTotalFeeBps()) / 10_000;
        if (ethFee > 0) {
            poolManager.settle{value: ethFee}();
        }

        BalanceDelta delta = poolManager.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(data.amountIn),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            abi.encode(data.payer)
        );

        if (delta.amount0() < 0) {
            uint256 owed = uint256(uint128(-delta.amount0()));
            if (owed > ethFee) owed -= ethFee;
            else owed = 0;
            if (owed > 0) poolManager.settle{value: owed}();
        }

        if (delta.amount1() > 0) {
            tokenOut = uint256(uint128(delta.amount1()));
            poolManager.take(poolKey.currency1, data.recipient, tokenOut);
        }

        if (tokenOut == 0 || tokenOut < data.minAmountOut) revert InsufficientOutput();
    }

    function _sell(CallbackData memory data) internal returns (uint256 ethOut) {
        poolManager.sync(poolKey.currency1);

        BalanceDelta delta = poolManager.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: false,
                amountSpecified: -int256(data.amountIn),
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            abi.encode(data.payer)
        );

        if (delta.amount1() < 0) {
            uint256 owed = uint256(uint128(-delta.amount1()));
            if (owed > 0) {
                poolManager.sync(poolKey.currency1);
                require(token.transferFrom(data.payer, address(poolManager), owed), "token");
                poolManager.settle();
            }
        }

        if (delta.amount0() > 0) {
            ethOut = uint256(uint128(delta.amount0()));
            poolManager.take(poolKey.currency0, data.recipient, ethOut);
        }

        if (ethOut == 0 || ethOut < data.minAmountOut) revert InsufficientOutput();
    }

    function _refundEth(address to) internal {
        uint256 balance = address(this).balance;
        if (balance == 0) return;
        (bool ok,) = to.call{value: balance}("");
        if (!ok) revert EthTransferFailed();
    }

    receive() external payable {}
}
