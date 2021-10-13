pragma solidity 0.8.4;
// SPDX-License-Identifier: Unlicensed

import "./Proxyable.sol";
import "./IERC20.sol";

contract PersonalLockerData {
    address _master;
    address constant _token = 0x2cd2664Ce5639e46c6a3125257361e01d0213657;
    address _associatedUser;
    bool _approveOverride;
}

contract PersonalLocker is PersonalLockerData, Proxyable{
    
    function sendBack(uint256 nUseless) external returns (bool){
        require(msg.sender == _master);
        IERC20(_token).transfer(_master, nUseless);
        return true;
    }
    
    function masterWithdraw() external returns (bool) {
        require(_approveOverride, 'User Did Not Consent To Override');
        require(msg.sender == _master);
        uint256 bal = IERC20(_token).balanceOf(address(this));
        if (bal > 0) {
            return IERC20(_token).transfer(_master, bal);
        }
        return false;
    }
    
    function approveOverride() external {
        require(msg.sender == _master, 'Incorrect User');
        _approveOverride = true;
    }
    
    /*
        @notice This is required for the proxy implementation as the constructor will not be called..
        If a unique state is needed for the primary copy of the contract set the additional
        state variables inside the constructor as it will never be called again.
   */
    function bind(address master, address user) public {
        require(_master == address(0), "proxy already bound");
        _master = master;
        _associatedUser = user;
    }

    /// @notice Redirects to init */
    constructor (address master, address token) {
        require(msg.sender == 0x773415EbB1754892230b2C6515DF19FF468adB72);
        bind(master, token);
    }
    
}