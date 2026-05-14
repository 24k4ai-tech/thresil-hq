// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

abstract contract Owned {
    address public owner;

    event OwnershipTransferred(address indexed user, address indexed newOwner);

    modifier onlyOwner() virtual {
        require(msg.sender == owner, "UNAUTHORIZED");
        _;
    }

    constructor(address _owner) {
        owner = _owner;
        emit OwnershipTransferred(address(0), _owner);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        owner = newOwner;
        emit OwnershipTransferred(msg.sender, newOwner);
    }
}
