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
    struct KOTH {
        bool isVerified;
        address tokenRepresentative;
    }
    
    // eclipse => isVerified, tokenRepresentative
    mapping ( address => KOTH ) eclipseContracts;
    
    // Token => Eclipse
    mapping ( address => address ) tokenToEclipse;
    
    // list of Eclipses
    address[] eclipseContractList;
    
    // decay tracker
    uint256 public decayIndex;
    
    uint256 public furnacePercent;
    
    // initialize
    constructor() {
        _master = 0x8d2F3CA0e254e1786773078D69731d0c03fBc8DF;
        _fetcher = EclipseDataFetcher(0x2cd2664Ce5639e46c6a3125257361e01d0213657);
        furnacePercent = 50;
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
        eclipseContracts[address(hill)].isVerified = true;
        eclipseContracts[address(hill)].tokenRepresentative = _tokenToList;
        tokenToEclipse[_tokenToList] = address(hill);
        eclipseContractList.push(address(hill));
        _withdraw();
        emit KOTHCreated(address(hill), _tokenToList, _kothOwner);
    }
    
    function iterateDecay(uint256 iterations) external {
        require(iterations <= eclipseContractList.length, 'Too Many Iterations');
        for (uint i = 0; i < iterations; i++) {
            if (decayIndex >= eclipseContractList.length) {
                decayIndex = 0;
            }
            _decay(eclipseContractList[decayIndex]);
            decayIndex++;
        }
    }
    
    //////////////////////////////////////////
    ///////    MASTER FUNCTIONS    ///////////
    //////////////////////////////////////////
    
    
    function transferOwnership(address newOwner) external onlyMaster {
        require(_master != newOwner, 'Owners Match');
        _master = newOwner;
        emit TransferOwnership(newOwner);
    }
    
    function decayByToken(address _token) external onlyMaster returns (bool) {
        return _decay(tokenToEclipse[_token]);
    }
    
    function decayByEclipse(address _Eclipse) external onlyMaster returns (bool) {
        return _decay(_Eclipse);
    }
    
    function deleteEclipse(address koth) external onlyMaster {
        require(eclipseContracts[koth].isVerified, 'Not KOTH Contract');
        _deleteKOTH(eclipseContracts[koth].tokenRepresentative);
    }
    
    function deleteEclipseByToken(address token) external onlyMaster {
        require(eclipseContracts[tokenToEclipse[token]].isVerified, 'Not KOTH Contract');
        _deleteKOTH(token);
    }
    
    function pullRevenue() external onlyMaster {
        _withdraw();
    }
    
    function withdrawTokens(address token) external onlyMaster {
        uint256 bal = IERC20(token).balanceOf(address(this));
        require(bal > 0, 'Insufficient Balance');
        IERC20(token).transfer(_master, bal);
    }
    
    
    //////////////////////////////////////////
    ///////   INTERNAL FUNCTIONS   ///////////
    //////////////////////////////////////////
    
    
    function _decay(address eclipse) internal returns(bool){
        return IEclipse(payable(eclipse)).decay();
    }
    
    function _deleteKOTH(address token) internal {
        for (uint i = 0; i < eclipseContractList.length; i++) {
            if (koth == eclipseContractList[i]) {
                eclipseContractList[i] = eclipseContractList[eclipseContractList.length - 1];
                break;
            }
        }
        eclipseContractList.pop();
        delete eclipseContracts[koth];
        delete tokenToEclipse[token];
    }
    
    function _withdraw() internal {
        address receiver = _fetcher.getMarketing();
        address furnace = _fetcher.getFurnace();
        
        uint256 amountFurnace = address(this).balance.div(2);
        uint256 receiverAmount = address(this).balance.sub(amountFurnace); 
        
        if (address(this).balance > 100) {
            (bool success,) = payable(receiver).call{value: receiverAmount}("");
            require(success, 'BNB Transfer Failed');
        
            (bool successful,) = payable(furnace).call{value: amountFurnace}("");
            require(successful, 'BNB Transfer Failed');
        }
    }
    
    //////////////////////////////////////////
    ///////     READ FUNCTIONS     ///////////
    //////////////////////////////////////////
    
    function kingOfTheHill() external view returns (address) {
        uint256 max = 0;
        address king;
        for (uint i = 0; i < eclipseContractList.length; i++) {
            uint256 amount = IERC20(_useless).balanceOf(eclipseContractList[i]);
            if (amount > max) {
                max = amount;
                king = eclipseContractList[i];
            }
        }
        return king == address(0) ? king : eclipseContracts[king].tokenRepresentative;
    }
    
    function getUselessInKOTH(address _token) external view returns(uint256) {
        if (tokenToEclipse[_token] == address(0)) return 0;
        return IERC20(_useless).balanceOf(tokenToEclipse[_token]);
    }
    
    function getKOTHForToken(address _token) external view returns(address) {
        return tokenToEclipse[_token];
    }
    
    function getTokenForKOTH(address _KOTH) external view returns(address) {
        return eclipseContracts[_KOTH].tokenRepresentative;
    }
    
    function isEclipseContractVerified(address _contract) external view returns(bool) {
        return eclipseContracts[_contract].isVerified;
    }
    
    function isTokenListed(address token) external view returns(bool) {
        return tokenToEclipse[token] != address(0);
    }
    
    function geteclipseContractList() external view returns (address[] memory) {
        return eclipseContractList;
    }
    
    receive() external payable {}
    
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
