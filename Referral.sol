//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./IERC20.sol";
import "./Address.sol";
import "./SafeMath.sol";

contract UselessReferral is IERC20 {

    using Address for address;
    using SafeMath for uint256;

    // Referrer
    struct Referrer {
        uint256 totalRefs;
        uint256 lastRef;
        uint256 lastClaim;
        uint256 lastCleanUp;
        uint256 listIndex;
        bytes32 code;
    }

    // list of Referrers 
    mapping ( address => Referrer ) users;
    mapping ( bytes32 => address ) codeToUser;
    address[] listUsers;

    // total refer points granted
    uint256 _totalRefers;

    // for garbage cleanup
    uint256 cleanIndex;
    uint256 iterations;

    // Useless Token Contract
    address constant _token = 0x2cd2664Ce5639e46c6a3125257361e01d0213657;

    // Time Thresholds
    uint256 constant monthly = 864000;
    uint256 constant weekly = 201600;

    // Ownership Access
    mapping ( address => bool ) hasAccess;
    modifier onlyOwners(){require(hasAccess[msg.sender], 'Sender Does Not Have Access'); _;}

    // Initialize Referral System
    constructor() {
        hasAccess[msg.sender] = true;
        iterations = 50;
    }
    
    function totalSupply() external view override returns (uint256) { return _totalRefers; }
    function balanceOf(address account) public view override returns (uint256) { return users[account].totalRefs; }
    function allowance(address holder, address spender) external view override returns (uint256) { return users[holder].totalRefs + users[spender].totalRefs; }
    
    function name() public pure returns (string memory) {
        return "UselessReferralPoints";
    }

    function symbol() public pure returns (string memory) {
        return "UREFPOINTS";
    }

    function decimals() public pure override returns (uint8) {
        return 0;
    }

    function approve(address spender, uint256 amount) public pure override returns (bool) {
        return spender != address(0) && amount > 0;
    }
  
    /** Transfer Function */
    function transfer(address recipient, uint256 amount) external pure override returns (bool) {
        return recipient != address(0) && amount > 0;
    }

    /** Transfer Function */
    function transferFrom(address sender, address recipient, uint256 amount) external pure override returns (bool) {
        return sender != recipient && amount > 0;
    }


    //////////////////////////////////////
    //////     PUBLIC FUNCTIONS     //////
    //////////////////////////////////////


    function claimTokens(address user) external {
        _claimTokens(user);
    }

    function claimTokens() external {
        _claimTokens(msg.sender);
    }


    //////////////////////////////////////
    //////      OWNER FUNCTIONS     //////
    //////////////////////////////////////

    function increaseReferralCountForUser(address user, uint256 numReferrals) external onlyOwners {
        _increaseReferralsForUser(user, numReferrals);
    }
    
    function verifyUser(address user, bytes32 referralCode) external onlyOwners {
        codeToUser[referralCode] = user;
        users[user].code = referralCode;
        emit VerifiedUser(user, referralCode);
    }

    function increaseReferralCountsForUsers(address[] calldata userList, uint256[] calldata numReferrals) external onlyOwners {
        require(userList.length == numReferrals.length, 'Unequal lengths');
        for (uint i = 0; i < userList.length; i++) {
            _increaseReferralsForUser(userList[i], numReferrals[i]);
        }
    }

    function removeUser(address user) external onlyOwners {
        require(user != address(0), 'ERR: Zero Address');
        _removeUser(user);
    }

    function approveUserForOwnership(address user, bool isApproved) external onlyOwners {
        hasAccess[user] = isApproved;
        emit UpdatedAccessToOwnership(user, isApproved);
    }


    //////////////////////////////////////
    //////    INTERNAL FUNCTIONS    //////
    //////////////////////////////////////

    
    function _claimTokens(address user) internal {
        // clean garbage
        cleanGarbage();
        
        // ensure shareholder
        if (users[user].totalRefs == 0) {
            delete users[user];
            return;
        }

        // ensure time has passed
        require(users[user].lastClaim + weekly < block.number, 'Not Time To Claim');
        
        // Balance of Useless in Contract
        uint256 bal = IERC20(_token).balanceOf(address(this));
        // User's portion of balance
        uint256 portion = bal.mul(users[user].totalRefs).div(_totalRefers);
        require(portion > 0, 'No Tokens To Claim');

        // update user's info
        users[user].lastClaim = block.number;

        // send tokens to user
        bool s = IERC20(_token).transfer(user, portion);
        require(s, 'Failure On Token Transfer');

        emit TokensClaimed(user, portion);
    }
    
    function cleanGarbage() internal {
        if (listUsers.length == 0) return;
        uint256 _iterations = listUsers.length > iterations ? iterations : listUsers.length;
        for (uint i = 0; i < _iterations; i++) {
            if (cleanIndex >= listUsers.length) {
                cleanIndex = 0;
            }
            if (isInactive(listUsers[i])) {
                decrementUser(listUsers[i]);
            }
            cleanIndex++;
        }
    }
    
    function _increaseReferralsForUser(address user, uint256 numReferrals) internal {
        require(user != address(0), 'Error: Zero Address');
        require(numReferrals <= 200, 'Error: Too Many Referrals');

        // check if new user
        if (users[user].totalRefs == 0) {
            users[user].listIndex = listUsers.length;
            listUsers.push(user);
            emit ReferrerAdded(user);
        }

        // update user data
        users[user].totalRefs += numReferrals;
        users[user].lastRef = block.number;
        _totalRefers += numReferrals;

        // tell blockchain
        emit IncreasedReferralForUser(user, numReferrals);
    }
    
    function decrementUser(address user) internal {
        if (users[user].totalRefs == 0) {
            _removeUser(user);
            return;
        }
        if (users[user].lastCleanUp + weekly < block.number) {
            users[user].totalRefs--;
            users[user].lastCleanUp = block.number;
            _totalRefers--;
            emit DecrementReferralForUser(user);
        }
    }

    function _removeUser(address user) internal {
        if (users[user].code != bytes32(0)) {
            delete codeToUser[users[user].code];
        }
        address lastUser = listUsers[listUsers.length - 1];
        listUsers[users[user].listIndex] = lastUser;
        users[lastUser].listIndex = users[user].listIndex;
        listUsers.pop();
        delete users[user];
        emit ReferrerRemoved(user);
    }


    //////////////////////////////////////
    //////      READ FUNCTIONS      //////
    //////////////////////////////////////

    
    function isInactive(address user) public view returns (bool) {
        return users[user].lastRef + monthly < block.number;
    }

    function lastClaim(address user) public view returns (uint256) {
        return users[user].lastClaim;
    }

    function lastReferral(address user) public view returns (uint256) {
        return users[user].lastRef;
    }

    function lastDecrement(address user) public view returns (uint256) {
        return users[user].lastCleanUp;
    }

    function getNumReferralsForUser(address user) public view returns (uint256) {
        return users[user].totalRefs;
    }
    
    function getUserByReferralCode(bytes32 code) public view returns (address) {
        return codeToUser[code];
    }
    
    function getReferralCodeForUser(address user) public view returns (bytes32) {
        return users[user].code;
    }

    // EVENTS
    event ReferrerAdded(address referrer);
    event ReferrerRemoved(address referrer);
    event DecrementReferralForUser(address user);
    event VerifiedUser(address user, bytes32 referralCode);
    event TokensClaimed(address referrer, uint256 tokens);
    event UpdatedAccessToOwnership(address user, bool isApproved);
    event IncreasedReferralForUser(address user, uint256 numReferrals);

}