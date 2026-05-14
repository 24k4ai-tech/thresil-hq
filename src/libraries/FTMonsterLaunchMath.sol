// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FullMath} from "v4-core/libraries/FullMath.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

library FTMonsterLaunchMath {
    uint256 internal constant Q96 = 1 << 96;
    uint256 internal constant Q192 = Q96 * Q96;

    error InvalidBudget();
    error SqrtPriceTooLarge();
    error NoLiquidity();

    function initialSqrtPriceX96(uint256 ethBudget, uint256 tokenBudget) internal pure returns (uint160) {
        if (ethBudget == 0 || tokenBudget == 0) revert InvalidBudget();
        uint256 ratioX192 = FullMath.mulDiv(tokenBudget, Q192, ethBudget);
        uint256 sqrtPriceX96 = _sqrt(ratioX192);
        if (sqrtPriceX96 > type(uint160).max) revert SqrtPriceTooLarge();
        return uint160(sqrtPriceX96);
    }

    function fullRangeLiquidity(uint160 sqrtPriceX96, int24 tickSpacing, uint256 ethAmount, uint256 tokenAmount)
        internal
        pure
        returns (uint128)
    {
        if (ethAmount == 0 || tokenAmount == 0) revert NoLiquidity();
        uint160 sqrtA = TickMath.getSqrtPriceAtTick(TickMath.minUsableTick(tickSpacing));
        uint160 sqrtB = TickMath.getSqrtPriceAtTick(TickMath.maxUsableTick(tickSpacing));

        uint256 liquidity0 = _liquidityForAmount0(sqrtPriceX96, sqrtB, ethAmount);
        uint256 liquidity1 = _liquidityForAmount1(sqrtA, sqrtPriceX96, tokenAmount);
        uint256 liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        if (liquidity == 0 || liquidity > type(uint128).max) revert NoLiquidity();
        return uint128(liquidity);
    }

    function _liquidityForAmount0(uint160 sqrtA, uint160 sqrtB, uint256 amount0) private pure returns (uint256) {
        if (sqrtA > sqrtB) (sqrtA, sqrtB) = (sqrtB, sqrtA);
        uint256 intermediate = FullMath.mulDiv(uint256(sqrtA), uint256(sqrtB), Q96);
        return FullMath.mulDiv(amount0, intermediate, sqrtB - sqrtA);
    }

    function _liquidityForAmount1(uint160 sqrtA, uint160 sqrtB, uint256 amount1) private pure returns (uint256) {
        if (sqrtA > sqrtB) (sqrtA, sqrtB) = (sqrtB, sqrtA);
        return FullMath.mulDiv(amount1, Q96, sqrtB - sqrtA);
    }

    function _sqrt(uint256 x) private pure returns (uint256 z) {
        if (x == 0) return 0;
        z = x;
        uint256 y = (x >> 1) + 1;
        while (y < z) {
            z = y;
            y = (x / y + y) >> 1;
        }
    }
}
