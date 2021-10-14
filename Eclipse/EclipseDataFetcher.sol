//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./SafeMath.sol";
import "./Address.sol";

contract EclipseDataFetcher {

    using SafeMath for uint256;
    using Address for address;

    uint256 public _defaultSwapperFee;
    uint256 constant _swapperFeeDenominator = 10**5;

    address public _furnace;
    address public _marketing;
    address _swapper;
    
    uint256 _decayPeriod;
    uint256 _decayFee;
    uint256 _uselessMinimumToDecayFullBalance;

    struct ListedToken {
        bool isListed;
        uint256 swapperFee;
    }

    mapping (address => ListedToken) listedTokens;

    mapping (address => bool) _isMaster;
    modifier onlyMaster(){require(_isMaster[msg.sender], 'Only Master'); _;}

    constructor() {
        _isMaster[msg.sender] = true;
        _decayPeriod = 201600; // one week
        _decayFee = 10;
        _uselessMinimumToDecayFullBalance = 10**7 * 10**9; // 10 million useless
    }

    function setMasterPriviledge(address user, bool userIsMaster) external onlyMaster {
        _isMaster[user] = userIsMaster;
    }

    function setSwapperFeeForToken(address token, uint256 fee) external onlyMaster {
        listedTokens[token].swapperFee = fee;
    }

    function listToken(address token) external onlyMaster {
        _listToken(token, _defaultSwapperFee);
    }

    function setDefaultSwapperFee(uint256 newDefault) external onlyMaster {
        _defaultSwapperFee = newDefault;
    }

    function listTokenCustomSwapperFee(address token, uint256 swapperFee) external onlyMaster {
        _listToken(token, swapperFee);
    }

    function _listToken(address token, uint256 swapperFee) private {
        listedTokens[token].isListed = true;
        listedTokens[token].swapperFee = swapperFee;
    }
    
    function isListed(address token) external view returns (bool) {
        return listedTokens[token].isListed;
    }

    function getFurnace() external view returns(address) {
        return _furnace;
    }

    function getMarketing() external view returns(address) {
        return _marketing;
    }

    function isMaster(address user) external view returns(bool) {
        return _isMaster[user];
    }
    
    function getDecayPeriod() public view returns (uint256) {
        return _decayPeriod;
    }
    
    function getDecayFee() public view returns (uint256) {
        return _decayFee;
    }
    
    function getUselessMinimumToDecayFullBalance() public view returns (uint256) {
        return _uselessMinimumToDecayFullBalance;
    }
    
    function getSwapper() public view returns (address) {
        return _swapper;
    }

    function getSwapperFeeForToken(address token) public view returns(uint256) {
        if (!listedTokens[token].isListed) return _defaultSwapperFee.mul(2);
        return listedTokens[token].swapperFee;
    }

    function calculateSwapperFee(address token, uint256 amountBNB) external view returns (uint256) {
        return amountBNB.mul(getSwapperFeeForToken(token)).div(_swapperFeeDenominator);
    }

}
