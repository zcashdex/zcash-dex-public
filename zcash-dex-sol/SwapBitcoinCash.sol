// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./interfaces/ISwap.sol";
import "./interfaces/IStableSwap.sol";

contract SwapBitcoinCash is ISwap {
    IERC20 private constant RENBCH = IERC20(0xc3fEd6eB39178A541D274e6Fc748d48f0Ca01CC3);
    IERC20 private constant WMATIC = IERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);

    IUniswapV2Router02 public constant ROUTER = IUniswapV2Router02(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);

    receive() external payable {}

    function estimateFromTokenToNative(uint256 amountIn) external view override returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = address(RENBCH);
        path[1] = address(WMATIC);
        uint256[] memory amounts = ROUTER.getAmountsOut(amountIn, path);
        return amounts[1];
    }

    function estimateFromNativeToToken(uint256 amountIn) external view override returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = address(WMATIC);
        path[1] = address(RENBCH);
        uint256[] memory amounts = ROUTER.getAmountsOut(amountIn, path);
        return amounts[1];
    }

    function fromNativeToToken(uint256 amountOutMin) payable external override returns (uint256) {
        {
            // convert to WBTC
            uint256 amountIn = address(this).balance;
            address[] memory path = new address[](2);
            path[0] = address(WMATIC);
            path[1] = address(RENBCH);
            ROUTER.swapExactETHForTokens{value: amountIn}(0, path, address(this), block.timestamp);
        }
        {
            uint256 amountOut = RENBCH.balanceOf(address(this));
            require(amountOut >= amountOutMin);
            RENBCH.transfer(msg.sender, amountOut);
            return amountOut;
        }
    }

    function fromTokenToNative(uint256 amountOutMin) external override returns (uint256) {
        {
            // convert to MATIC
            uint256 amountBCH = RENBCH.balanceOf(address(this));
            address[] memory path = new address[](2);
            path[0] = address(RENBCH);
            path[1] = address(WMATIC);
            RENBCH.approve(address(ROUTER), amountBCH);
            ROUTER.swapExactTokensForETH(amountBCH, 0, path, address(this), block.timestamp);
        }
        {
            uint256 amountOut = address(this).balance;
            require(amountOut >= amountOutMin);
            payable(msg.sender).transfer(amountOut);
            return amountOut;
        }
    }
}
