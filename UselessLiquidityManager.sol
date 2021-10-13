pragma solidity 0.8.4;
// SPDX-License-Identifier: Unlicensed

import "./IERC20.sol";
import "./Address.sol";
import "./SafeMath.sol";

/** 
 * 
 * Contract To Manage, Lock, and Remove LP Tokens From The Useless MultiSignature Wallet
 * Developed by DeFi Mark
 * 
 */

contract UselessLiquidityManager {

    using Address for address;
    using SafeMath for uint256;

    // liquidity pool token
    address public constant _LP = 0x08A6cD8a2E49E3411d13f9364647E1f2ee2C6380;
    // index not found value
    uint256 public constant ERROR_VALUE = 10**20;

    // token locker
    struct TokenLocker{
        uint256 numTokens;
        uint256 startTime;
        uint256 duration;
    }
    
    // tracks the current Locker Index
    uint256 public nLockers;

    // list of lockers
    mapping (uint256 => TokenLocker) lockers;
    // list of removed indexes
    mapping (uint256 => bool) indexRemoved;

    // address to remove LP Tokens from
    address public _removalTarget;
    
    // owner of contract
    address _owner;
    modifier onlyOwner(){require(msg.sender == _owner, 'Only Owner'); _;}
    
    constructor() {
        _owner = 0x8d2F3CA0e254e1786773078D69731d0c03fBc8DF;
        _removalTarget = 0x8d2F3CA0e254e1786773078D69731d0c03fBc8DF;
    }

    function moveAndLockLPTokens(uint256 percent, uint256 durationInBlocks) external onlyOwner {
        // check range on percent
        require(percent > 0 && percent <= 100, 'Percent Out Of Range');
        // check range on duration
        require(durationInBlocks >= 100, 'Duration Too Short');
        // number of LP Tokens Owned by Target 
        uint256 nTokens = IERC20(_LP).balanceOf(_removalTarget);
        // calculate percentage of LP
        nTokens = nTokens.mul(percent).div(10**2);
        require(nTokens > 0, 'No LP Tokens To Move');
        // balance before transfer
        uint256 balBefore = IERC20(_LP).balanceOf(address(this));
        // transfer LP Tokens From Target To Contract
        bool success = IERC20(_LP).transferFrom(_removalTarget, address(this), nTokens);
        // balance post-transfer
        uint256 received = IERC20(_LP).balanceOf(address(this)).sub(balBefore);
        // ensure tokens were received properly
        require(received > 0 && received <= nTokens && success, 'Receive LP Tokens Error');
        
        // add new locker to list
        lockers[nLockers] = TokenLocker({
            numTokens:received,
            startTime:block.number,
            duration:durationInBlocks
        });
        // increment locker number
        nLockers++;
        emit TokensLocked(received, durationInBlocks, nLockers - 1);
    }

    function reLockTokens(uint256 lockerNumber, uint256 duration) external onlyOwner {
        require(canRemove(lockerNumber), 'Cannot Move Tokens');
        lockers[lockerNumber].startTime = block.number;
        lockers[lockerNumber].duration = duration;
        emit RelockedTokens(lockers[lockerNumber].numTokens, lockerNumber, duration);
    }

    function withdrawUnlockedTokens(uint256 lockerNumber, address destination) external onlyOwner {
        _removeUnlockedTokens(lockerNumber, destination);
    }

    function withdrawUnlockedTokensToSender(uint256 lockerNumber) external onlyOwner {
        _removeUnlockedTokens(lockerNumber, msg.sender);
    }
    
    function removeFirstUnlockedLocker(address destination) external onlyOwner {
        uint256 lockerNo = getFirstLockerAvailable();
        require(lockerNo != ERROR_VALUE, 'No Lockers Available');
        _removeUnlockedTokens(lockerNo, destination);
    }

    function updateLPTokenRemovalTargetAddress(address newAddressToPullTokensFrom) external onlyOwner {
        _removalTarget = newAddressToPullTokensFrom;
        emit RemovalTargetUpdated(newAddressToPullTokensFrom);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        _owner = newOwner;
        emit TransferOwnership(newOwner);
    }

    function _removeUnlockedTokens(uint256 lockerNumber, address destination) internal {
        require(canRemove(lockerNumber), 'Cannot Move Tokens');
        // remove index
        indexRemoved[lockerNumber] = true;
        // number of tokens to remove
        uint256 nTokens = lockers[lockerNumber].numTokens;
        // transfer tokens
        bool success = IERC20(_LP).transfer(destination, nTokens);
        // delete locker data
        delete lockers[lockerNumber];
        // require successful transfer
        require(success, 'Failure on LP Token Transfer');
        emit RemovedUnlockedTokens(nTokens, lockerNumber);
    }

    function timeLeftUntilUnlock(uint256 lockerNumber) external view returns (uint256) {
        if (isUnlocked(lockerNumber)) return 0;
        uint256 endTime = lockers[lockerNumber].startTime + lockers[lockerNumber].duration;
        return block.number.sub(endTime);
    }
    /** Returns The First Unlocked Locker Found, 10^20 if none exists */
    function getFirstLockerAvailable() public view returns (uint256) {
        for (uint i = 0; i < nLockers; i++) {
            if (canRemove(i)) {
                return i;
            }
        }
        return ERROR_VALUE;
    }

    /** Returns The Earliest Locker Number Available That Has Not Yet Been Used */
    function firstLockerNumberNotYetRemoved() external view returns (uint256) {
        for (uint i = 0; i < nLockers; i++) {
            if (!indexRemoved[i]) return i;
        }
        return ERROR_VALUE;
    }

    function numberOfLPTokensInLocker(uint256 lockerNumber) external view returns (uint256) {
        return lockers[lockerNumber].numTokens;
    }

    function percentOfLPTokensInLocker(uint256 lockerNumber) external view returns (uint256) {
        uint256 nTokens = lockers[lockerNumber].numTokens;
        return uint(10**18).mul(nTokens).div(IERC20(_LP).totalSupply());
    }

    function percentOfLPTokensInContract() external view returns (uint256) {
        uint256 nTokens = IERC20(_LP).balanceOf(address(this));
        return uint(10**18).mul(nTokens).div(IERC20(_LP).totalSupply());
    }

    function numLPTokensInContract() external view returns (uint256) {
        return IERC20(_LP).balanceOf(address(this));
    }

    function getLockerInfo(uint256 lockerNumber) external view returns (uint256,uint256,uint256) {
        return(lockers[lockerNumber].numTokens,lockers[lockerNumber].startTime,lockers[lockerNumber].duration);
    }

    function isUnlocked(uint256 lockerNumber) public view returns (bool) {
        return lockers[lockerNumber].startTime + lockers[lockerNumber].duration < block.number;
    }

    function canRemove(uint256 lockerNumber) public view returns (bool) {
        return isUnlocked(lockerNumber)
        && !indexRemoved[lockerNumber]
        && lockers[lockerNumber].numTokens > 0
        && lockerNumber < nLockers;
    }

    function isValidLockerNumber(uint256 lockerNumber) external view returns (bool) {
        return !indexRemoved[lockerNumber];
    }

    event TokensLocked(uint256 nTokens, uint256 duration, uint256 lockNumber);
    event TransferOwnership(address newOwner);
    event RemovalTargetUpdated(address newAddressToPullTokensFrom);
    event RelockedTokens(uint256 nTokens, uint256 lockerNumber, uint256 duration);
    event RemovedUnlockedTokens(uint256 numTokens, uint256 lockerNumber);
    
}