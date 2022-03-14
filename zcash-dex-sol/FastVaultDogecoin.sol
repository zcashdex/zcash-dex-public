// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./interfaces/IFastVault.sol";
import "./interfaces/IGatewayRegistry.sol";
import "SafeCallee.sol";

contract FastVaultDogecoin is IFastVault {
    SafeCallee internal constant SAFE_CALLEE = SafeCallee(0x44A0a9CF602E076eDE16b83E1cbe6997D3e99895);
    address public constant override TOKEN = 0xcE829A89d4A55a63418bcC43F00145adef0eDB8E;
    IGatewayRegistry public constant REGISTRY = IGatewayRegistry(0xf36666C230Fa12333579b9Bd6196CB634D6BC506);
    uint256 public constant DUST = 1000;

    address public owner;
    mapping(bytes32 => bool) public nonces;
    mapping(address => uint256) public balances;
    mapping(address => uint256) public borrows;
    mapping(address => uint256) public allowances;
    uint256 available;

    event Allow(
        address indexed receiver,
        bytes32 indexed nonce
    );

    event Borrow(
        address indexed receiver,
        address indexed caller
    );

    constructor(address _owner) {
        owner = _owner;
        available = 0;
    }

    function setOwner(address _owner) external {
        require(owner == msg.sender, "permission");
        owner = _owner;
    }

    function ownerDeposit(uint256 amount) external {
        require(owner == msg.sender, "permission");
        IERC20(TOKEN).transferFrom(msg.sender, address(this), amount);
        available += amount;
    }

    function ownerWithdrawAll() external {
        require(owner == msg.sender, "permission");
        IERC20(TOKEN).transfer(owner, available);
        available = 0;
    }

    function allow(bytes32 nonce, address receiver, uint256 balance) public {
        require(owner == msg.sender, "permission");
        require(nonces[nonce] == false, "nonce");
        require(allowances[receiver] == 0, "allowance");
        require(balances[receiver] == 0, "balance");
        require(borrows[receiver] == 0, "borrow");
        require(balance <= available, "available");
        allowances[receiver] = balance;
        available -= balance;
        nonces[nonce] = true;
        emit Allow(receiver, nonce);
    }

    function allowAndCall(bytes32 nonce, address receiver, uint256 balance, address target, bytes calldata data) external {
        allow(nonce, receiver, balance);
        SAFE_CALLEE.doCall(target, data);
    }

    function borrowFor(address receiver, uint256 amount, bytes calldata _sig) external override returns (uint256) {
        {
            // validate msg was signed by receiver
            bytes memory _msg = abi.encode("vault-DOGE", msg.sender, amount);
            address signer = ECDSA.recover(ECDSA.toEthSignedMessageHash(keccak256(_msg)), _sig);
            require(signer == receiver, "permission");
        }
        if (amount <= balances[receiver]) {
            balances[receiver] -= amount;
        } else {
            uint256 borrowed = amount - balances[receiver];
            require(borrowed <= allowances[receiver], "allowance");
            allowances[receiver] -= borrowed;
            borrows[receiver] += borrowed;
        }
        IERC20(TOKEN).transfer(msg.sender, amount);
        emit Borrow(receiver, msg.sender);
        return amount;
    }

    function mint(address receiver, uint256 _amount, bytes32 _nHash, bytes calldata _sig) external override {
        REGISTRY.getGatewayByToken(TOKEN).mint(
            keccak256(abi.encode(receiver)),
            _amount,
            _nHash,
            _sig);

        if (_amount <= borrows[receiver]) {
            available += _amount;
            borrows[receiver] -= _amount;
        } else {
            uint256 remaining = _amount - borrows[receiver];
            available += borrows[receiver];
            borrows[receiver] = 0;
            if (remaining <= DUST) {
                available += remaining;
            } else {
                balances[receiver] += remaining;
            }
        }
        // do not allow any more borrows for this receiver
        available += allowances[receiver];
        allowances[receiver] = 0;
    }
}
