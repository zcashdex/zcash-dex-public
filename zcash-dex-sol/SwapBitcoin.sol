// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./interfaces/ISwap.sol";
import "./interfaces/IStableSwap.sol";

contract SwapBitcoin is ISwap {
    IERC20 private constant RENBTC = IERC20(0xDBf31dF14B66535aF65AaC99C32e9eA844e14501);
    IERC20 private constant WBTC = IERC20(0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6);
    IERC20 private constant WMATIC = IERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);

    IUniswapV2Router02 public constant ROUTER = IUniswapV2Router02(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);
    IStableSwap public constant STABLE_SWAP = IStableSwap(0xC2d95EEF97Ec6C17551d45e77B590dc1F9117C67);

    receive() external payable {}

    function estimateFromTokenToNative(uint256 amountIn) external view override returns (uint256) {
        // convert to WBTC
        uint256 amountWBTC = STABLE_SWAP.get_dy_underlying(1, 0, amountIn);
        // convert to MATIC
        address[] memory path = new address[](2);
        path[0] = address(WBTC);
        path[1] = address(WMATIC);
        uint256[] memory amounts = ROUTER.getAmountsOut(amountWBTC, path);
        return amounts[1];
    }

    function estimateFromNativeToToken(uint256 amountIn) external view override returns (uint256) {
        // convert to WBTC
        address[] memory path = new address[](2);
        path[0] = address(WMATIC);
        path[1] = address(WBTC);
        uint256[] memory amounts = ROUTER.getAmountsOut(amountIn, path);
        uint256 amountWBTC = amounts[1];
        // convert to RENBTC
        return STABLE_SWAP.get_dy_underlying(0, 1, amountWBTC);
    }

    function fromNativeToToken(uint256 amountOutMin) payable external override returns (uint256) {
        {
            // convert to WBTC
            uint256 amountIn = address(this).balance;
            address[] memory path = new address[](2);
            path[0] = address(WMATIC);
            path[1] = address(WBTC);
            ROUTER.swapExactETHForTokens{value: amountIn}(0, path, address(this), block.timestamp);
        }
        {
            // convert to RENBTC
            uint256 amountWBTC = WBTC.balanceOf(address(this));
            WBTC.approve(address(STABLE_SWAP), amountWBTC);
            STABLE_SWAP.exchange_underlying(0, 1, amountWBTC, 0);
        }
        {
            uint256 amountOut = RENBTC.balanceOf(address(this));
            require(amountOut >= amountOutMin);
            RENBTC.transfer(msg.sender, amountOut);
            return amountOut;
        }
    }

    function fromTokenToNative(uint256 amountOutMin) external override returns (uint256) {
        {
            // convert to WBTC
            uint256 amountIn = RENBTC.balanceOf(address(this));
            RENBTC.approve(address(STABLE_SWAP), amountIn);
            STABLE_SWAP.exchange_underlying(1, 0, amountIn, 0);
        }
        {
            // convert to MATIC
            uint256 amountWBTC = WBTC.balanceOf(address(this));
            address[] memory path = new address[](2);
            path[0] = address(WBTC);
            path[1] = address(WMATIC);
            WBTC.approve(address(ROUTER), amountWBTC);
            ROUTER.swapExactTokensForETH(amountWBTC, 0, path, address(this), block.timestamp);
        }
        {
            uint256 amountOut = address(this).balance;
            require(amountOut >= amountOutMin);
            payable(msg.sender).transfer(amountOut);
            return amountOut;
        }
    }
}
