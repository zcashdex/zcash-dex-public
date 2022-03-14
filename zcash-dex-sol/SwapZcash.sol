// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./interfaces/ISwap.sol";

contract SwapZcash is ISwap {
    IERC20 private constant RENZEC = IERC20(0x31a0D1A199631D244761EEba67e8501296d2E383);
    IERC20 private constant WMATIC = IERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);

    IUniswapV2Router02 public constant ROUTER = IUniswapV2Router02(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);

    receive() external payable {}
    
    function estimateFromTokenToNative(uint256 amountIn) external view override returns (uint256) {
        // convert to MATIC
        address[] memory path = new address[](2);
        path[0] = address(RENZEC);
        path[1] = address(WMATIC);
        uint256[] memory amounts = ROUTER.getAmountsOut(amountIn, path);
        return amounts[1];
    }

    function estimateFromNativeToToken(uint256 amountIn) external view override returns (uint256) {
        // convert to RENZEC
        address[] memory path = new address[](2);
        path[0] = address(WMATIC);
        path[1] = address(RENZEC);
        uint256[] memory amounts = ROUTER.getAmountsOut(amountIn, path);
        return amounts[1];
    }

    function fromNativeToToken(uint256 amountOutMin) payable external override returns (uint256) {
        {
            // convert to RENZEC
            uint256 amountIn = address(this).balance;
            address[] memory path = new address[](2);
            path[0] = address(WMATIC);
            path[1] = address(RENZEC);
            ROUTER.swapExactETHForTokens{value: amountIn}(0, path, address(this), block.timestamp);
        }
        {
            uint256 amountOut = RENZEC.balanceOf(address(this));
            require(amountOut >= amountOutMin);
            RENZEC.transfer(msg.sender, amountOut);
            return amountOut;
        }
    }

    function fromTokenToNative(uint256 amountOutMin) external override returns (uint256) {
        {
            // convert to MATIC
            uint256 amountIn = RENZEC.balanceOf(address(this));
            address[] memory path = new address[](2);
            path[0] = address(RENZEC);
            path[1] = address(WMATIC);
            RENZEC.approve(address(ROUTER), amountIn);
            ROUTER.swapExactTokensForETH(amountIn, 0, path, address(this), block.timestamp);
        }
        {
            uint256 amountOut = address(this).balance;
            require(amountOut >= amountOutMin);
            payable(msg.sender).transfer(amountOut);
            return amountOut;
        }
    }
}
