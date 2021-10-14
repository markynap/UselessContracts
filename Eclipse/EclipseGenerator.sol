//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./IEclipse.sol";
import "./Proxyable.sol";
import "./DataFetcher.sol";
import "./SafeMath.sol";
import "./Address.sol";
import "./ReentrantGuard.sol";
import "./IERC20.sol";

/** 
 * 
 * King Of The Hill Contract Generator
 * Generates Proxy KOTH Contracts For Specified Token Projects
 * Costs A Specified Amount To Have KOTH Created and Swapper Unlocked
 * Developed by Markymark (DeFi Mark)
 * 
 */ 

contract EclipseGenerator is ReentrancyGuard {
    
    using Address for address;
    using SafeMath for uint256;
    // useless contract
    address constant _useless = 0x2cd2664Ce5639e46c6a3125257361e01d0213657;
    // owner 
    address _master;
    // parent contract
    address _parentProxy;
    // data fetcher
    EclipseDataFetcher immutable _fetcher;
    // master only functions
    modifier onlyMaster() {require(msg.sender == _master, 'Master Function'); _;}
    // koth tracking
    mapping ( address => bool ) isKOTHContract;
    mapping ( address => address ) tokenToKOTH;
    mapping ( address => uint256 ) bnbAccruedPerToken;
    address[] kothContracts;
    
    // decay tracker
    uint256 public decayIndex;
    
    // initialize
    constructor() {
        _master = 0x8d2F3CA0e254e1786773078D69731d0c03fBc8DF;
        _fetcher = EclipseDataFetcher(0x2cd2664Ce5639e46c6a3125257361e01d0213657);
    }
    
    function lockProxy(address proxy) external onlyMaster {
        require(_parentProxy == address(0), 'Proxy Locked');
        _parentProxy = proxy;
    }
    
    
    //////////////////////////////////////////
    ///////    PUBLIC FUNCTIONS    ///////////
    //////////////////////////////////////////
    
    
    function createKOTH(address _kothOwner, address _tokenToList) external payable nonReentrant {
        require(!_isContract(msg.sender) && tx.origin == msg.sender, 'No Proxies Allowed');
        uint256 cost = _fetcher.getCreationCost();
        require(msg.value >= cost, 'Cost Not Met');
        // create proxy
        address hill = Proxyable(payable(_parentProxy)).createProxy();
        // initialize proxy
        IEclipse(payable(hill)).bind(_kothOwner, _tokenToList);
        // add to database
        isKOTHContract[address(hill)] = true;
        tokenToKOTH[_tokenToList] = address(hill);
        kothContracts.push(address(hill));
        emit KOTHCreated(address(hill), _tokenToList, _kothOwner);
    }
    
    
    //////////////////////////////////////////
    ///////    MASTER FUNCTIONS    ///////////
    //////////////////////////////////////////
    
    
    function transferOwnership(address newOwner) external onlyMaster {
        require(_master != newOwner, 'Owners Match');
        _master = newOwner;
        emit TransferOwnership(newOwner);
    }
    
    function decayByToken(address _token) external onlyMaster {
        IEclipse decayHill = IEclipse(payable(tokenToKOTH[_token]));
        decayHill.decay();
    }
    
    function decayByKOTH(address _KOTH) external onlyMaster {
        IEclipse decayHill = IEclipse(payable(_KOTH));
        decayHill.decay();
    }
    
    function iterateDecay(uint256 iterations) external onlyMaster {
        require(iterations <= kothContracts.length, 'Too Many Iterations');
        for (uint i = 0; i < iterations; i++) {
            if (decayIndex >= kothContracts.length) {
                decayIndex = 0;
            }
            IEclipse(payable(kothContracts[decayIndex])).decay();
            decayIndex++;
        }
    }
    
    function deleteKOTH(address koth) external onlyMaster {
        require(isKOTHContract[koth], 'Not KOTH Contract');
        for (uint i = 0; i < kothContracts.length; i++) {
            if (koth == kothContracts[i]) {
                kothContracts[i] = kothContracts[kothContracts.length - 1];
                break;
            }
        }
        kothContracts.pop();
        delete isKOTHContract[koth];
        delete tokenToKOTH[IEclipse(payable(koth)).getTokenRepresentative()];
    }
    
    function pullRevenue() external onlyMaster {
        (bool success,) = payable(_master).call{value: address(this).balance}("");
        require(success, 'BNB Transfer Failed');
    }
    
    function withdrawTokens(address token) external onlyMaster {
        uint256 bal = IERC20(token).balanceOf(address(this));
        require(bal > 0, 'Insufficient Balance');
        IERC20(token).transfer(_master, bal);
    }
    
    
    //////////////////////////////////////////
    ///////     READ FUNCTIONS     ///////////
    //////////////////////////////////////////
    
    function kingOfTheHill() external view returns (address) {
        uint256 max = 0;
        address king;
        for (uint i = 0; i < kothContracts.length; i++) {
            uint256 amount = IERC20(_useless).balanceOf(kothContracts[i]);
            if (amount > max) {
                max = amount;
                king = kothContracts[i];
            }
        }
        return king == address(0) ? king : IEclipse(payable(king)).getTokenRepresentative();
    }
    
    function getUselessInKOTH(address _token) external view returns(uint256) {
        if (tokenToKOTH[_token] == address(0)) return 0;
        return IERC20(_useless).balanceOf(tokenToKOTH[_token]);
    }
    
    function getKOTHForToken(address _token) external view returns(address) {
        return tokenToKOTH[_token];
    }
    
    function getIsKOTHContract(address _contract) external view returns(bool) {
        return isKOTHContract[_contract];
    }
    
    function isTokenListed(address token) external view returns(bool) {
        return tokenToKOTH[token] != address(0);
    }
    
    function getKOTHContracts() external view returns (address[] memory) {
        return kothContracts;
    }
    
    function getBNBAccruedPerToken(address token) external view returns (uint256) {
        return bnbAccruedPerToken[token];
    }
    
    receive() external payable {
        
    }
    
    /**
     * @notice Check if an address is a contract
     */
    function _isContract(address _addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }
    
    //////////////////////////////////////////
    ///////         EVENTS         ///////////
    //////////////////////////////////////////
    
    
    event KOTHCreated(address KOTH, address tokenListed, address kothLister);
    event TransferOwnership(address newOwner);

}
