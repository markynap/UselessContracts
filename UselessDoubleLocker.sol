pragma solidity 0.8.4;
//SPDX-License-Identifier: MIT

import "./Address.sol";
import "./SafeMath.sol";
import "./ReentrantGuard.sol";
import "./PersonalLocker.sol";
import "./IERC20.sol";
import "./IUselessBypass.sol";

/**
 * Contract: xToken
 * Developed By: Markymark (DeFiMark / MoonMark)
 *
 * Tax Exempt (or Extra) Token that is Pegged 1:1 to a Native Asset
 * Can Be Used For Tax-Exemptions, Low Gas Transfers, Or anything else
 *
 */
contract UselessLocker is ReentrancyGuard, IERC20 {

    using SafeMath for uint256;
    using Address for address;
    
    // constants
    uint256 constant startingSellTax = 275;
    uint256 constant startingBuyTax = 180;
    uint256 constant blocksPerPeriod = 28800;
    address constant _token = 0x2cd2664Ce5639e46c6a3125257361e01d0213657;
  
    // contract owner
    address public _owner;
    modifier onlyOwner(){require(msg.sender == _owner); _;}
    // Furnace Contract Address
    address _furnace;
    
    address _uselessBypass;
    
    struct Locker {
        uint256[] amountsLocked;
        uint256[] timesLocked;
        uint256[] reflectionsEarned;
        uint256 totalLocked;
    }
    
    struct Holder {
        address sellLockerAddress;
        address buyLockerAddress;
        Locker sellLocker;
        Locker buyLocker;
    }
    
    // master proxy
    address proxy;
    
    // holders
    mapping (address => Holder) holders;

    // Instatiate Locker
    constructor (
    ) {
        _furnace = 0x03F9332cBA1dFc80b503b7EE3A085FBB8532abea;
        _owner = msg.sender;
    }
    
    function totalSupply() external pure override returns (uint256) { return 1000; }
    function balanceOf(address account) public view override returns (uint256) { 
        return IERC20(_token).balanceOf(holders[account].buyLockerAddress).add(IERC20(_token).balanceOf(holders[account].buyLockerAddress));
    }
    function allowance(address holder, address spender) external pure override returns (uint256) { return holder == spender ? 0 : 0; }
    function name() public pure returns (string memory) {
        return "Locked Useless";
    }

    function symbol() public pure returns (string memory) {
        return "LUseless";
    }

    function decimals() public pure override returns (uint8) {
        return 0;
    }
    
    function approve(address spender, uint256 amount) public view override returns (bool) {
        return spender == msg.sender || amount == 0;
    }
    
    /** Transfer Function */
    function transfer(address recipient, uint256 amount) external view override returns (bool) {
        return recipient == msg.sender || amount == 0;
    }
    
    /** Transfer Function */
    function transferFrom(address sender, address recipient, uint256 amount) external pure override returns (bool) {
        return sender == recipient || amount == 0;
    }
  
    ////////////////////////////////////
    //////    PUBLIC FUNCTIONS    //////
    ////////////////////////////////////
    
    
    function approveOverride(bool isBuy) external {
        address locker = isBuy ? holders[msg.sender].buyLockerAddress : holders[msg.sender].sellLockerAddress;
        require(locker != address(0));
        PersonalLocker(payable(locker)).approveOverride();
    }

    /** Locks Number Of Useless Specified, Applying A Large Fee Which Decays To Zero Over Time */
    function lockUseless(uint256 nUseless) external nonReentrant returns(bool) {
        return _lockUseless(nUseless);
    }
    
    /** Migrates Locker For User To New Redeem Account */
    function migrateLocker(address newLockerOwner) external nonReentrant {
        require(holders[msg.sender].buyLockerAddress != address(0) || holders[msg.sender].sellLockerAddress != address(0));
        require(holders[newLockerOwner].buyLockerAddress == address(0) && holders[newLockerOwner].sellLockerAddress == address(0));
        
        if (holders[msg.sender].buyLockerAddress != address(0)) {
            holders[newLockerOwner].buyLockerAddress = holders[msg.sender].buyLockerAddress;
            holders[newLockerOwner].buyLocker = holders[msg.sender].buyLocker;
            delete holders[msg.sender].buyLocker;
            delete holders[msg.sender].buyLockerAddress;
        }
        if (holders[msg.sender].sellLockerAddress != address(0)) {
            holders[newLockerOwner].sellLockerAddress = holders[msg.sender].sellLockerAddress;
            holders[newLockerOwner].sellLocker = holders[msg.sender].sellLocker;
            delete holders[msg.sender].sellLocker;
            delete holders[msg.sender].sellLockerAddress;
        }
    }
    
    function releaseLockedUseless(uint256 amount, uint256 whichBlock, bool isBuy) external nonReentrant returns(bool) {
        return _releaseUseless(amount, whichBlock, isBuy);
    }
    
    function releaseOldestBlock(bool isBuy) external nonReentrant returns (bool) {
        Locker memory lock = isBuy ? holders[msg.sender].buyLocker : holders[msg.sender].sellLocker;
        for (uint i = 0; i < lock.amountsLocked.length; i++) {
            if (lock.amountsLocked[i] > 0) {
                return _releaseUseless(lock.amountsLocked[i], i, isBuy);
            }
        }
        return false;
    }
    
    function releaseAmountOfOldestBlock(uint256 amount, bool isBuy) external nonReentrant returns (bool) {
        require(amount >= 100);
        Locker memory lock = isBuy ? holders[msg.sender].buyLocker : holders[msg.sender].sellLocker;
        for (uint i = 0; i < lock.amountsLocked.length; i++) {
            if (lock.amountsLocked[i] >= amount) {
                return _releaseUseless(amount, i, isBuy);
            }
        }
        return false;
    }
    
    
    ////////////////////////////////////
    //////   INTERNAL FUNCTIONS   //////
    ////////////////////////////////////
    
    
    /** Creates xTokens based on how many Native received */
    function _lockUseless(uint256 nNative) private returns(bool) {
        
        // amount useless received
        uint256 received = _transferInUseless(msg.sender, nNative);

        // locker
        address locker = holders[msg.sender].sellLockerAddress;
        
        // if new user
        if (locker == address(0)) {
            // create them a locker
            locker = PersonalLocker(payable(proxy)).createProxy();
            // set this before init to protect against any recursion
            holders[msg.sender].sellLockerAddress = locker;
            // initialize proxy
            PersonalLocker(payable(locker)).bind(address(this), msg.sender);
        }
        
        // lock tokens
        _lock(msg.sender, received, false);
        
        // send useless to locker
        bool success = IERC20(_token).transfer(locker, received);
        require(success, 'Transfer Fail');
       
        // tell the blockchain
        emit LockedUseless(received, holders[msg.sender].sellLocker.amountsLocked.length-1);
        return true;
    }
    
    /** Buys Useless At 4% Tax, Holds For Buyer */
    function _buyToken(uint256 amountBNB) private returns(bool) {

        // locker
        address locker = holders[msg.sender].buyLockerAddress;
        
        // if new user
        if (locker == address(0)) {
            // create them a locker
            locker = PersonalLocker(payable(proxy)).createProxy();
            // set this before init to protect against any recursion
            holders[msg.sender].buyLockerAddress = locker;
            // initialize proxy
            PersonalLocker(payable(locker)).bind(address(this), msg.sender);
        }
        // balance before swap
        uint256 balBefore = IERC20(_token).balanceOf(address(this));
        
        // buy useless from swapper
        (bool succ,) = payable(_uselessBypass).call{value: amountBNB}("");
        require(succ);
        
        // received 
        uint256 received = IERC20(_token).balanceOf(address(this)).sub(balBefore);
        
        // lock tokens
        _lock(msg.sender, received, true);
        
        // send useless to locker
        bool success = IERC20(_token).transfer(locker, received);
        require(success, 'Transfer Fail');
       
        // tell the blockchain
        emit PurchasedUseless(received, holders[msg.sender].buyLocker.amountsLocked.length-1);
        return true;
    }
    
    
    function _releaseUseless(uint256 amount, uint256 whichBlock, bool isBuy) private returns(bool) {
        
        // which locker 
        Locker storage lock = isBuy ? holders[msg.sender].buyLocker : holders[msg.sender].sellLocker;
        // locker address
        address locker = isBuy ? holders[msg.sender].buyLockerAddress : holders[msg.sender].sellLockerAddress;
        
        require(lock.amountsLocked.length > 0 && lock.totalLocked > 0);
        // amount locked
        uint256 userAmount = lock.amountsLocked[whichBlock];
        require(amount <= userAmount && amount > 0 && lock.totalLocked >= amount);
       
        // calculate tax fee for furnace
        uint256 fee = calculateTax(msg.sender, whichBlock, isBuy);
        // amounts
        uint256 feeAmount; uint256 redeemableAmount; uint256 reflectionAmount;
        
        if (fee == 0) {
            // amount of reflections
            reflectionAmount = reflectionsEarned(msg.sender, whichBlock, isBuy);
            // send percentage of reflection amount
            reflectionAmount = reflectionAmount.mul(amount).div(userAmount);
            // redeemable amount of useless
            redeemableAmount = amount.add(reflectionAmount);
            // send back tokens + reflections
            require(PersonalLocker(locker).sendBack(redeemableAmount), 'Error Sending Tokens');
        } else {
            // fee for furnace
            feeAmount = amount.mul(fee).div(10**3);
            // redeemable amount of token
            redeemableAmount = amount.sub(feeAmount);
            // reflections earned
            reflectionAmount = reflectionsEarned(msg.sender, whichBlock, isBuy);
            // send percentage of reflection amount
            reflectionAmount = reflectionAmount.mul(amount).div(userAmount);
            // amount for furnace
            uint256 reflectForFurnace = reflectionAmount.mul(feeAmount).div(10**3);
            // add to redeemable
            redeemableAmount = redeemableAmount.add(reflectionAmount.sub(reflectForFurnace));
            // send back tokens
            require(PersonalLocker(locker).sendBack(amount.add(reflectionAmount)), 'Error Sending Tokens');
            // send fee to furnace
            IERC20(_token).transfer(_furnace, feeAmount.add(reflectForFurnace));
    
        }
        require(redeemableAmount > 0);
        
        // reduce reflectionsEarned if applicable
        if (!firstOrLastBlock(msg.sender, whichBlock, isBuy)) {
            if (lock.reflectionsEarned[whichBlock+1] > reflectionAmount) {
                lock.reflectionsEarned[whichBlock+1] = lock.reflectionsEarned[whichBlock+1].sub(reflectionAmount);
            } else {
                lock.reflectionsEarned[whichBlock+1] = 0;
            }
            // edit User's Locker Data Including Reflections
            lock.totalLocked = lock.totalLocked.sub(amount.add(reflectionAmount));
            lock.amountsLocked[whichBlock] = lock.amountsLocked[whichBlock].sub(amount);
        } else {
            // edit User's Locker Data Without Reflections
            lock.totalLocked = lock.totalLocked.sub(amount);
            lock.amountsLocked[whichBlock] = lock.amountsLocked[whichBlock].sub(amount);
        }

        // if sender sold out entirely
        if (lock.totalLocked == 0) {
            // send unclaimed reflections to furnace
            uint256 bal = IERC20(_token).balanceOf(locker);
            if (bal > 0) {
                require(PersonalLocker(locker).sendBack(bal));
                IERC20(_token).transfer(_furnace, bal);
            }
            // clear storage
            if (isBuy) {
                delete holders[msg.sender].buyLocker;
            } else {
                delete holders[msg.sender].buyLocker;
            }
        }
        if (isBuy) {
            // emit event
            emit RedeemedUseless(redeemableAmount, feeAmount, whichBlock);
            // redeemable amount of useless
            return IERC20(_token).transfer(msg.sender, redeemableAmount);
        } else {
            // emit event
            emit SoldUseless(redeemableAmount, feeAmount, whichBlock);
            // sell redeemable amount for bnb
            IERC20(_token).approve(_uselessBypass, redeemableAmount);
            IUselessBypass(_uselessBypass).sellUseless(msg.sender, redeemableAmount);
            return true;
        }
        
    }

    function _lock(address sender, uint256 tokens, bool isBuy) private {
        
        // which locker 
        Locker storage lock = isBuy ? holders[sender].buyLocker : holders[sender].sellLocker;
        // locker address
        address locker = isBuy ? holders[sender].buyLockerAddress : holders[sender].sellLockerAddress;
        lock.amountsLocked.push(tokens);
        lock.timesLocked.push(block.number);
        
        if (lock.amountsLocked.length > 1) {
            uint256 diff = IERC20(_token).balanceOf(locker).sub(lock.totalLocked);
            lock.reflectionsEarned.push(diff);
            lock.totalLocked += diff;
        } else {
            lock.reflectionsEarned.push(0);
        }
        lock.totalLocked += tokens;
    }
    
    function _transferInUseless(address sender, uint256 nNative) private returns (uint256){
        // native balance of sender
        uint256 bal = IERC20(_token).balanceOf(sender);
        require(bal > 0 && nNative <= bal);
        // balance before transfer
        uint256 balBefore = IERC20(_token).balanceOf(address(this));
        // move tokens into contract
        bool success = IERC20(_token).transferFrom(sender, address(this), nNative);
        // balance after transfer
        uint256 received = IERC20(_token).balanceOf(address(this)).sub(balBefore);
        require(received <= nNative && received > 0 && success);
        return received;
    }


    ////////////////////////////////////
    //////     OWNER FUNCTIONS    //////
    ////////////////////////////////////


    function lockProxy(address _proxy) external onlyOwner {
        require(_proxy != address(0) && proxy == address(0));
        proxy = _proxy;
    }
    
    function masterWithdraw(address user, bool isBuy) external onlyOwner {
        address locker = isBuy ? holders[user].buyLockerAddress : holders[user].sellLockerAddress;
        require(locker != address(0));
        PersonalLocker(payable(locker)).masterWithdraw();
    }

    /** Withdraw Tokens that are not native token that were mistakingly sent to this address */
    function withdrawTheMistakesOfOthers(address tokenAddress, uint256 nTokens) external onlyOwner {
        nTokens = nTokens == 0 ? IERC20(tokenAddress).balanceOf(address(this)) : nTokens;
        IERC20(tokenAddress).transfer(msg.sender, nTokens);
        emit WithdrawTheMistakesOfOthers(tokenAddress, nTokens);
    }

    /** Upgrades The Pancakeswap Router Used To Purchase Native on BNB Received */
    function updateUselessBypassAddress(address newBypass) external onlyOwner {
        _uselessBypass = newBypass;
        emit UpdatedUselessBypassAddress(newBypass);
    }
    
    /** Transfers Ownership To New Address */
    function transferOwnership(address newOwner) external onlyOwner {
        _owner = newOwner;
        emit TransferOwnership(newOwner);
    }
    
    
    ////////////////////////////////////
    //////     READ FUNCTIONS     //////
    ////////////////////////////////////
    
    
    
    function reflectionsEarned(address user, uint256 whichBlock, bool isBuy) public view returns(uint256) {
        
        if (firstOrLastBlock(user, whichBlock, isBuy)) {
            return isBuy ?
            IERC20(_token).balanceOf(holders[user].buyLockerAddress).sub(holders[user].buyLocker.totalLocked)
            :
            IERC20(_token).balanceOf(holders[user].sellLockerAddress).sub(holders[user].sellLocker.totalLocked);
        } else {
            return isBuy ?
            holders[user].buyLocker.reflectionsEarned[whichBlock+1]
            :
            holders[user].sellLocker.reflectionsEarned[whichBlock+1];
        }
    }
    
    function firstOrLastBlock(address user, uint256 whichBlock, bool isBuy) private view returns (bool) {
        return isBuy ?
        holders[user].buyLocker.amountsLocked.length == 1 || holders[user].buyLocker.amountsLocked.length-1 == whichBlock
        :
        holders[user].sellLocker.amountsLocked.length == 1 || holders[user].sellLocker.amountsLocked.length-1 == whichBlock;
    }
    
    function calculateTax(address user, uint256 whichBlock, bool isBuy) public view returns (uint256) {
        
        uint256 blocksPassed = isBuy ? 
        block.number.sub(holders[user].buyLocker.timesLocked[whichBlock])
        : block.number.sub(holders[user].sellLocker.timesLocked[whichBlock]);
        uint256 period = isBuy ? blocksPerPeriod.div(2) : blocksPerPeriod;
        uint256 _daysPassed = blocksPassed.div(period);
        uint256 tax = isBuy ? startingBuyTax : startingSellTax;
        if (_daysPassed >= tax) {
            return 0;
        } else {
            return tax.sub(_daysPassed);
        }
    }
    
    function hasUselessLocked(address user, bool isBuy) external view returns (bool){
        return isBuy ? holders[user].buyLocker.amountsLocked.length > 0 : holders[user].sellLocker.amountsLocked.length > 0;
    }
    
    function daysPassed(address user, uint256 whichBlock, bool isBuy) external view returns(uint256) {
        uint256 blocksPassed = isBuy ? block.number.sub(holders[user].buyLocker.timesLocked[whichBlock]) : block.number.sub(holders[user].sellLocker.timesLocked[whichBlock]);
        return blocksPassed.div(blocksPerPeriod);
    }
    
    function totalTokensClaimable(address user, bool isBuy) external view returns(uint256) {
        return isBuy ? IERC20(_token).balanceOf(holders[user].buyLockerAddress) : IERC20(_token).balanceOf(holders[user].sellLockerAddress);
    }
    
    function tokensLockedInBlock(address user, uint256 whichBlock, bool isBuy) external view returns(uint256) {
        return isBuy ? holders[user].buyLocker.amountsLocked[whichBlock] : holders[user].sellLocker.amountsLocked[whichBlock];
    }
    
    function numBlocksForUser(address user, bool isBuy) external view returns(uint256) {
        return isBuy ? holders[user].buyLocker.amountsLocked.length : holders[user].sellLocker.amountsLocked.length;
    }
    
    function getLockerForUser(address user, bool isBuy) external view returns(address) {
        return isBuy ? holders[user].buyLockerAddress : holders[user].sellLockerAddress;
    }

    receive() external payable {
        
        uint256 furnVal = msg.value.mul(4).div(10**2);
        uint256 buyVal = msg.value.sub(furnVal);
        
        _buyToken(buyVal);
        
        (bool succ,) = payable(_furnace).call{value:buyVal}("");
        require(succ);
    }

    // EVENTS
    event UpdatedPurchaseFee(uint256 newPurchaseFee);
    event PurchasedUseless(uint256 amountPurchased, uint256 blockNumber);
    event UpdatedUselessBypassAddress(address newBypass);
    event WithdrawTheMistakesOfOthers(address token, uint256 tokenAmount);
    event TransferOwnership(address newOwner);
    event LockedUseless(uint256 tokensLocked, uint256 blockNumber);
    event SoldUseless(uint256 amountSold, uint256 feeTaken, uint256 blockNumber);
    event RedeemedUseless(uint256 amountSold, uint256 feeTaken, uint256 blockNumber);

}
