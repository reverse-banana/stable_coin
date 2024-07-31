// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

contract ManualToken {
    mapping(address => uint256) private s_balances;

    function name() public pure returns (string memory) {
        return "Manual Token";
    }

    // we achive same by using:
    // string public name = "Manual Token";

    function totalSupply() public pure returns (uint256) {
        return 100 ether; // meaning 100 with 18 decomals
    }

    function decimals() public pure returns (uint8) {
        return 18;
    }

    function balanceOf(address _owner) public view returns (uint256 balance) {
        return s_balances[_owner];
        // return the value from the mapping with _owner key aka balance of the owner
    }

    function transfer(address _to, uint256 _amount) public {
        uint256 previousBalances = balanceOf(msg.sender) + balanceOf(_to);
        // making snapshot of the accounts of sender and receiver total sum
        s_balances[msg.sender] -= _amount;
        // substracting the sended amount from the sender account (by using map key pointer)
        s_balances[_to] += _amount;
        // adding the sended amount to the receiver account (by using map key pointer)

        require(s_balances[msg.sender] + s_balances[_to] == previousBalances);
        // making sure that sender and receiver balances have the same checksum after the tnx
    }
}