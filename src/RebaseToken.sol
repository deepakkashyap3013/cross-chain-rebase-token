// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

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
// internal & private view & pure functions
// external & public view & pure functions

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RebaseToken
 * @author Deepak Kashyap aka (Cynefin)
 * @notice This is a cross-chain rebase token that incentivises users to deposit into a vault and gain interest in rewards.
 * @notice The interest rate in the smart contract can only decrease
 * @notice Each will user will have their own interest rate that is the global interest rate at the time of depositing.
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    /**
     * errors
     */
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 currentIR, uint256 newIR);

    /**
     * state variables
     */
    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    uint256 private s_interestRate = 5e10; // interest per unit time(second)
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;

    /**
     * events
     */
    event InterestRateSet(uint256 newInterestRate);

    /**
     * functions
     */
    constructor() Ownable(msg.sender) ERC20("Rebase Token", "RBT") {}

    function grantMintAndBurnRole(address _acount) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _acount);
    }

    function revokeMintAndBurnRole(address _acount) external onlyOwner {
        _revokeRole(MINT_AND_BURN_ROLE, _acount);
    }

    /**
     * External functions
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        if (_newInterestRate >= s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    function mint(address _to, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        super._mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }
        _mintAccruedInterest(_from);
        super._burn(_from, _amount);
    }

    /**
     * public
     */

    /**
     * @dev transfers tokens from the sender to the recipient. This function also mints any accrued interest since the last time the user's balance was updated.
     * @param _recipient the address of the recipient
     * @param _amount the amount of tokens to transfer
     * @return true if the transfer was successful
     *
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        // accumulates the balance of the user so it is up to date with any interest accumulated.
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }

        _mintAccruedInterest(_recipient);
        _mintAccruedInterest(msg.sender);

        // Edge case
        if (balanceOf(_recipient) == 0) {
            // Update the users interest rate only if they have not yet got one (or they tranferred/burned all their tokens). Otherwise people could force others to have lower interest.
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }

        return super.transfer(_recipient, _amount);
    }

    /**
     * @dev transfers tokens from the sender to the recipient. This function also mints any accrued interest since the last time the user's balance was updated.
     * @param _sender the address of the sender
     * @param _recipient the address of the recipient
     * @param _amount the amount of tokens to transfer
     * @return true if the transfer was successful
     *
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        // accumulates the balance of the user so it is up to date with any interest accumulated.
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }

        _mintAccruedInterest(_recipient);
        _mintAccruedInterest(_sender);

        // Edge case
        if (balanceOf(_recipient) == 0) {
            // Update the users interest rate only if they have not yet got one (or they tranferred/burned all their tokens). Otherwise people could force others to have lower interest.
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }

        return super.transferFrom(_sender, _recipient, _amount);
    }

    /**
     * internal
     */

    /**
     * @dev accumulates the accrued interest of the user to the principal balance. This function mints the users accrued interest since they last transferred or bridged tokens.
     * @param _user the address of the user for which the interest is being minted
     *
     */
    function _mintAccruedInterest(address _user) internal {
        // Get the user's previous principal balance. The amount of tokens they had last time their interest was minted to them.
        uint256 previousPrincipalBalance = super.balanceOf(_user);

        // Calculate the accrued interest since the last accumulation
        // `balanceOf` uses the user's interest rate and the time since their last update to get the updated balance
        uint256 currentBalance = balanceOf(_user);
        uint256 balanceIncrease = currentBalance - previousPrincipalBalance;

        // Mint an amount of tokens equivalent to the interest accrued
        _mint(_user, balanceIncrease);
        // Update the user's last updated timestamp to reflect this most recent time their interest was minted to them.
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
    }

    /**
     * private
     */

    /**
     * internal & private view & pure functions
     */

    /**
     * @dev returns the interest accrued since the last update of the user's balance - aka since the last time the interest accrued was minted to the user.
     * @return linearInterest the interest accrued since the last update
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        uint256 timeDifference = block.timestamp - s_userLastUpdatedTimestamp[_user];
        // represents the linear growth over time = 1 + (interest rate * time)
        // A = P * (1 + (R * T))
        linearInterest = (s_userInterestRate[_user] * timeDifference) + PRECISION_FACTOR;
    }

    /**
     * external & public view & pure functions
     */

    /**
     * @dev calculates the balance of the user, which is the
     * principal balance + interest generated by the principal balance
     * @param _user the user for which the balance is being calculated
     * @return the total balance of the user
     */
    function balanceOf(address _user) public view override returns (uint256) {
        //current principal balance of the user
        uint256 currentPrincipalBalance = super.balanceOf(_user);
        if (currentPrincipalBalance == 0) {
            return 0;
        }
        // shares * current accumulated interest for that user since their interest was last minted to them.
        return (currentPrincipalBalance * _calculateUserAccumulatedInterestSinceLastUpdate(_user)) / PRECISION_FACTOR;
    }

    /**
     * @dev returns the principal balance of the user. The principal balance is the last
     * updated stored balance, which does not consider the perpetually accruing interest that has not yet been minted.
     * @param _user the address of the user
     * @return the principal balance of the user
     *
     */
    function principleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }
}
