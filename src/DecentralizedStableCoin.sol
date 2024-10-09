// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal/private view & pure functions
// external/public view & pure functions

pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DecentralizedStableCoin
 * @author 0xInkya
 * @notice This contract is governed by the DSCEngine contract.
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error DecentralizedStableCoin__MintAmountMustBeMoreThanZero();
    error DecentralizedStableCoin__MintRecipientIsZeroAddress();
    error DecentralizedStableCoin__BurnAmountMustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable() {}

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Mints DSC to a recipient
     * @param _to The address to mint DSC to
     * @param _amount The amount of DSC to mint
     * @dev Only the owner can call this function. onlyOwner modifier is from the Ownable contract
     */
    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_amount <= 0) revert DecentralizedStableCoin__MintAmountMustBeMoreThanZero();
        if (_to == address(0)) revert DecentralizedStableCoin__MintRecipientIsZeroAddress();
        _mint(_to, _amount);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Burns DSC from the caller's balance
     * @param _amount The amount of DSC to burn
     * @dev Virtual function on ERC20Burnable contract
     */
    function burn(uint256 _amount) public override onlyOwner {
        if (_amount <= 0) revert DecentralizedStableCoin__BurnAmountMustBeMoreThanZero();
        if (_amount > balanceOf(msg.sender)) revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        super.burn(_amount);
    }
}
