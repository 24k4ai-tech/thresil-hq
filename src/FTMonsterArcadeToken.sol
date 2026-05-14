// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title Oracle777
/// @notice Fixed-supply ERC20 for the Oracle777 arcade curve.
contract FTMonsterArcadeToken {
    string public constant name = "Oracle777";
    string public constant symbol = "777X";
    string public constant website = "https://www.777x.space/";
    string public constant description =
        "Oracle777 runs the SATO reserve rail first, keeps the last-buyer chase alive, gives SOTO holders a claim lane, and burns tokens into a penalty draw that locks a future block seed before payout.";
    string public constant aiIdentity =
        "777X powers the Oracle777 arcade: curve buys, last-buyer pot, official LP rewards, and burn-to-shoot penalty rounds.";
    string public constant projectWebsite = "https://www.777x.space/";
    string public constant projectGithub = "https://github.com/24k4ai-tech/thresil-hq";
    string public constant projectImage = "https://www.777x.space/assets/oracle777-og-card-wide.jpg";
    uint8 public constant decimals = 18;
    uint256 public constant TOTAL_SUPPLY = 210_000_000_000 * 1e18;

    uint256 public immutable genesisBlock;
    bytes32 public immutable genesisHash;

    uint256 public totalSupply;

    mapping(address account => uint256) public balanceOf;
    mapping(address owner => mapping(address spender => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    error InsufficientBalance();
    error InsufficientAllowance();
    error ZeroAddress();

    constructor(address initialReceiver) {
        if (initialReceiver == address(0)) revert ZeroAddress();
        genesisBlock = block.number;
        genesisHash = blockhash(block.number - 1);
        totalSupply = TOTAL_SUPPLY;
        balanceOf[initialReceiver] = TOTAL_SUPPLY;
        emit Transfer(address(0), initialReceiver, TOTAL_SUPPLY);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < value) revert InsufficientAllowance();
            unchecked {
                allowance[from][msg.sender] = allowed - value;
            }
            emit Approval(from, msg.sender, allowance[from][msg.sender]);
        }
        _transfer(from, to, value);
        return true;
    }

    function burn(uint256 value) external {
        uint256 balance = balanceOf[msg.sender];
        if (balance < value) revert InsufficientBalance();
        unchecked {
            balanceOf[msg.sender] = balance - value;
            totalSupply -= value;
        }
        emit Transfer(msg.sender, address(0), value);
    }

    function _transfer(address from, address to, uint256 value) internal {
        if (to == address(0)) revert ZeroAddress();
        uint256 balance = balanceOf[from];
        if (balance < value) revert InsufficientBalance();
        unchecked {
            balanceOf[from] = balance - value;
            balanceOf[to] += value;
        }
        emit Transfer(from, to, value);
    }
}
