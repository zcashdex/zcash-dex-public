// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

contract SafeCallee {
    function doCall(address target, bytes calldata data) external {
        (bool success, ) = target.call(data);
        require(success);
    }
}
