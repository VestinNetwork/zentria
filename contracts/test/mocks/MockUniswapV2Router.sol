// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {MockUniswapV2Factory} from "./MockUniswapV2Factory.sol";
import {MockUniswapV2Pair} from "./MockUniswapV2Pair.sol";
import {MockWETH} from "./MockWETH.sol";

/// @notice Minimal Uniswap V2 router mock for testing the launchpad flow.
/// @dev Only implements addLiquidityETH. For tax tests we simulate buys/sells by
///      pranking transfers directly from/to the pair address — this matches the
///      behavior of real V2 swaps as far as MemeToken is concerned.
contract MockUniswapV2Router {
    using SafeERC20 for IERC20;

    address public immutable factoryAddr;
    address public immutable wethAddr;

    constructor(address factory_, address weth_) {
        factoryAddr = factory_;
        wethAddr = weth_;
    }

    function factory() external view returns (address) {
        return factoryAddr;
    }

    function WETH() external view returns (address) {
        return wethAddr;
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256, /* amountTokenMin */
        uint256, /* amountETHMin */
        address to,
        uint256 /* deadline */
    )
        external
        payable
        returns (uint256 amountToken, uint256 amountETH, uint256 liquidity)
    {
        amountToken = amountTokenDesired;
        amountETH = msg.value;

        address pair = MockUniswapV2Factory(factoryAddr).getPair(token, wethAddr);
        require(pair != address(0), "pair missing");

        // Match real Uniswap V2 router: tokens go directly from sender to pair (no router intermediary).
        IERC20(token).safeTransferFrom(msg.sender, pair, amountToken);
        MockWETH(payable(wethAddr)).deposit{value: amountETH}();
        IERC20(wethAddr).safeTransfer(pair, amountETH);

        liquidity = _sqrt(amountToken * amountETH);
        MockUniswapV2Pair(pair).mint(to, liquidity);
    }

    /// @dev Babylonian sqrt (Uniswap V2 reference implementation).
    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    receive() external payable {}
}
