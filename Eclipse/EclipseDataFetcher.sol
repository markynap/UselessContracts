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
    address public uselessRewardPot;
   
    uint256 public uselessRewardPotPercentage;
    uint256 _decayPeriod;
    uint256 _decayFee;
    uint256 _uselessMinimumToDecayFullBalance;
    uint256 public creationCost;

    struct ListedToken {
        bool isListed;
        uint256 swapperFee;
        uint256 listedIndex;
    }

    mapping (address => ListedToken) listedTokens;
    address[] listed;

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
    
    function setUselessRewardPot(address newPot) external onlyMaster {
        uselessRewardPot = newPot;
    }
    
    function setEclipseCreationCost(uint256 newCost) external onlyMaster {
        creationCost = newCost;
    }
    
    function setUselessRewardPotPercentage(uint256 newPercentage) external onlyMaster {
        uselessRewardPotPercentage = newPercentage;
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
    
    function delistToken(address token) external onlyMaster {
        listed[listedTokens[token].listedIndex] = listed[listed.length-1];
        listedTokens[listed[listed.length-1]].listedIndex = listedTokens[token].listedIndex;
        listed.pop();
        delete listedTokens[token];
    }

    function _listToken(address token, uint256 swapperFee) private {
        listedTokens[token].isListed = true;
        listedTokens[token].swapperFee = swapperFee;
        listedTokens[token].listedIndex = listed.length;
        listed.push(token);
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
    
    function getListedTokens() public view returns (address[] memory) {
        return listed;
    }

    function getSwapperFeeForToken(address token) public view returns(uint256) {
        if (!listedTokens[token].isListed) return _defaultSwapperFee.mul(2);
        return listedTokens[token].swapperFee;
    }

    function calculateSwapperFee(address token, uint256 amountBNB) external view returns (uint256) {
        return amountBNB.mul(getSwapperFeeForToken(token)).div(_swapperFeeDenominator);
    }

}
