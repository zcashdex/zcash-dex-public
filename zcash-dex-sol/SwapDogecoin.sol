// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./interfaces/ISwap.sol";
import "./interfaces/IStableSwap.sol";

contract SwapDogecoin is ISwap {
    IERC20 private constant RENDOGE = IERC20(0xcE829A89d4A55a63418bcC43F00145adef0eDB8E);
    IERC20 private constant WETH = IERC20(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619);
    IERC20 private constant WMATIC = IERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);

    IUniswapV2Router02 public constant ROUTER = IUniswapV2Router02(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);

    receive() external payable {}

    function estimateFromTokenToNative(uint256 amountIn) external view override returns (uint256) {
        address[] memory path = new address[](3);
        path[0] = address(RENDOGE);
        path[1] = address(WETH);
        path[2] = address(WMATIC);
        uint256[] memory amounts = ROUTER.getAmountsOut(amountIn, path);
        return amounts[2];
    }

    function estimateFromNativeToToken(uint256 amountIn) external view override returns (uint256) {
        address[] memory path = new address[](3);
        path[0] = address(WMATIC);
        path[1] = address(WETH);
        path[2] = address(RENDOGE);
        uint256[] memory amounts = ROUTER.getAmountsOut(amountIn, path);
        return amounts[2];
    }

    function fromNativeToToken(uint256 amountOutMin) payable external override returns (uint256) {
        {
            uint256 amountIn = address(this).balance;
            address[] memory path = new address[](3);
            path[0] = address(WMATIC);
            path[1] = address(WETH);
            path[2] = address(RENDOGE);
            ROUTER.swapExactETHForTokens{value: amountIn}(0, path, address(this), block.timestamp);
        }
        {
            uint256 amountOut = RENDOGE.balanceOf(address(this));
            require(amountOut >= amountOutMin);
            RENDOGE.transfer(msg.sender, amountOut);
            return amountOut;
        }
    }

    function fromTokenToNative(uint256 amountOutMin) external override returns (uint256) {
        {
            uint256 amountDOGE = RENDOGE.balanceOf(address(this));
            address[] memory path = new address[](3);
            path[0] = address(RENDOGE);
            path[1] = address(WETH);
            path[2] = address(WMATIC);
            RENDOGE.approve(address(ROUTER), amountDOGE);
            ROUTER.swapExactTokensForETH(amountDOGE, 0, path, address(this), block.timestamp);
        }
        {
            uint256 amountOut = address(this).balance;
            require(amountOut >= amountOutMin);
            payable(msg.sender).transfer(amountOut);
            return amountOut;
        }
    }
}
