// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ═══════════════════════════════════════════════════════════════════════════════
// ISOFIX Demo — Mock RWA ERC-20 Token
// ═══════════════════════════════════════════════════════════════════════════════
//
// Minimal mintable ERC-20 for the ACTUS classification demo on Ethereum Sepolia.
// No library imports so it compiles with a single-file solc invocation from the
// in-browser deploy page (demo-evm/deploy.html).
//
// This is demo infrastructure. Not audited. Not for production use.
// Deploy target: Ethereum Sepolia testnet only.
// ═══════════════════════════════════════════════════════════════════════════════

contract MockRWAToken {
    // ── ERC-20 metadata ──────────────────────────────────────────────────────
    string  public name;
    string  public symbol;
    uint8   public immutable decimals;

    // ── ERC-20 state ─────────────────────────────────────────────────────────
    uint256 public totalSupply;
    mapping(address => uint256)                      public balanceOf;
    mapping(address => mapping(address => uint256))  public allowance;

    // ── Ownership (mint authority) ───────────────────────────────────────────
    address public owner;

    // ── Events ───────────────────────────────────────────────────────────────
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed ownerAddr, address indexed spender, uint256 value);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "MockRWAToken: not owner");
        _;
    }

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        name     = name_;
        symbol   = symbol_;
        decimals = decimals_;
        owner    = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ── ERC-20 core ──────────────────────────────────────────────────────────

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= value, "MockRWAToken: insufficient allowance");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - value;
        }
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(to != address(0), "MockRWAToken: transfer to zero");
        uint256 bal = balanceOf[from];
        require(bal >= value, "MockRWAToken: insufficient balance");
        unchecked { balanceOf[from] = bal - value; }
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }

    // ── Mint / burn ──────────────────────────────────────────────────────────

    function mint(address to, uint256 value) external onlyOwner {
        require(to != address(0), "MockRWAToken: mint to zero");
        totalSupply  += value;
        balanceOf[to] += value;
        emit Transfer(address(0), to, value);
    }

    function burn(uint256 value) external {
        uint256 bal = balanceOf[msg.sender];
        require(bal >= value, "MockRWAToken: burn exceeds balance");
        unchecked { balanceOf[msg.sender] = bal - value; }
        totalSupply -= value;
        emit Transfer(msg.sender, address(0), value);
    }

    // ── Ownership transfer ───────────────────────────────────────────────────

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "MockRWAToken: new owner is zero");
        address old = owner;
        owner = newOwner;
        emit OwnershipTransferred(old, newOwner);
    }
}
