// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
/**
 * @title Decentralised Stable Coin
 * @author Adnan Hamid
 * Collateral: Exogenous ETH & BTC
 * Minting: Algorithmic
 * Relative Stability: USD
 *
 * This is a contract ment to be governed by DSC Engine. This contract is ERC20 implementation of stablecoin
 */

contract DecentralisedStableCoin is ERC20Burnable, Ownable {
    error DecentralisedStableCoin__MustBeMoreThanZero();
    error DecentralisedStableCoin__BurnAmountExceedsBalance();
    error DecentralisedStableCoin__NotZeroAddress();

    constructor() ERC20("DecentralisedStableCoin", "DSC") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralisedStableCoin__MustBeMoreThanZero();
        }
        if (_amount > balance) {
            revert DecentralisedStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralisedStableCoin__NotZeroAddress();
        }
        if (amount <= 0) {
            revert DecentralisedStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, amount);
        return true;
    }
}
