// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./interfaces/IFastVault.sol";
import "./interfaces/IGatewayRegistry.sol";
import "./interfaces/ISwap.sol";
import "./interfaces/IWrappedNative.sol";

contract Exchange {
    IGatewayRegistry public constant REGISTRY = IGatewayRegistry(0xf36666C230Fa12333579b9Bd6196CB634D6BC506);
    IUniswapV2Router02 public constant ROUTER = IUniswapV2Router02(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);
    uint public constant FEE2 = 5e17; // 0.5 MATIC

    constructor() { }

    receive() external payable {}

    event Swap(
        address indexed receiver,
        address indexed mint,
        address indexed dest
    );

    struct MintAndSwapParams {
        address mint;
        uint256 amountOutMin;
        uint256 deadline;
        address swapToNative;
        address swapToToken;
        address dest;
        bytes destAddress;
    }

    function swapForNativeAndTokenAndBridge(
        address receiver,
        bytes calldata _msg,
        bytes calldata _msgsig
    ) internal returns (uint256) {
        {
            // validate msg was signed by receiver
            address signer = ECDSA.recover(ECDSA.toEthSignedMessageHash(keccak256(_msg)), _msgsig);
            require(signer == receiver, "authorized");
        }
        // decode parameters
        (MintAndSwapParams memory params) = abi.decode(_msg, (MintAndSwapParams));
        require(params.deadline >= block.timestamp, "deadline");
        {   
            // swap to MATIC
            uint256 amountIn = IERC20(params.mint).balanceOf(address(this));
            IERC20(params.mint).transfer(address(params.swapToNative), amountIn);
            ISwap(params.swapToNative).fromTokenToNative(0);
            // send fee to transaction sender
            payable(tx.origin).transfer(FEE2);
            uint256 amountOut = address(this).balance;
            if (params.swapToToken != address(0)) {
                // swap to destination token
                amountOut = ISwap(params.swapToToken).fromNativeToToken{value: amountOut}(0);
            }
            // bridge
            amountOut = bridgeToDestination(amountOut, params.dest, params.destAddress);
            require(amountOut >= params.amountOutMin, "minimum");
            emit Swap(receiver, params.mint, params.dest);
            return amountOut;
        }
    }

    function fastMintAndSwapForNativeAndTokenAndBridge(
        address receiver,
        bytes calldata _msg,
        bytes calldata _msgsig,
        IFastVault vault,
        bytes calldata _vaultsig,
        uint256 _amount
    ) external returns (uint256) {
        vault.borrowFor(receiver, _amount, _vaultsig);
        return swapForNativeAndTokenAndBridge(receiver, _msg, _msgsig);
    }

    function mintAndSwapForNativeAndTokenAndBridge(
        address receiver,
        bytes calldata _msg,
        bytes calldata _msgsig,
        IFastVault vault,
        bytes calldata _vaultsig,
        uint256 _amount,
        bytes32 _nHash,
        bytes calldata _mintsig
    ) external returns (uint256) {
        if (!mintStatus(vault.TOKEN(), receiver, address(vault), _amount, _nHash)) {
            vault.mint(receiver, _amount, _nHash, _mintsig);
        }
        vault.borrowFor(receiver, _amount, _vaultsig);
        return swapForNativeAndTokenAndBridge(receiver, _msg, _msgsig);
    }

    function bridgeToDestination(uint256 amount, address dest, bytes memory destAddress) internal returns (uint256) {
        if (dest == address(0x0)) {
            address nativeAddress = abi.decode(destAddress, (address));
            require(nativeAddress != address(0));
            payable(nativeAddress).transfer(amount);
            return amount;
        } else {
            IERC20(dest).approve(address(ROUTER), amount);
            return REGISTRY.getGatewayByToken(dest).burn(destAddress, amount);
        }
    }

    function recovery(
        address receiver,
        bytes calldata _msg,
        bytes calldata _msgsig,
        uint256 _amount,
        bytes32 _nHash,
        bytes calldata _sig
    ) external {
        {
            // validate msg was signed by receiver
            address signer = ECDSA.recover(ECDSA.toEthSignedMessageHash(keccak256(_msg)), _msgsig);
            require(signer == receiver);
        }
        (address mint) = abi.decode(_msg, (address));
        REGISTRY.getGatewayByToken(mint).mint(
                keccak256(abi.encode(receiver)),
                _amount,
                _nHash,
                _sig);
        IERC20(mint).transfer(receiver, IERC20(mint).balanceOf(address(this)));
    }

    function mintStatus(
        address mint,
        address receiver,
        address vault,
        uint256 _amount,
        bytes32 _nHash
    ) public view returns (bool) {
        IGateway gateway = REGISTRY.getGatewayByToken(mint);
        bytes32 sigHash = gateway.hashForSignature(
            keccak256(abi.encode(receiver)),
            _amount,
            vault,
            _nHash
        );
        return gateway.status(sigHash);
    }
}
