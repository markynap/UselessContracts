//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./IERC20.sol";
import "./IUniswapV2Router02.sol";
import "./EclipseDataFetcher.sol";
import "./SafeMath.sol";
import "./IEclipse.sol";
import "./Proxyable.sol";

/** 
 *
 * Useless King Of The Hill Contract
 * Tracks Useless In Contract To Determine Listing on the Useless App
 * Developed by Markymark (DeFi Mark)
 * 
 */

contract EclipseData {
    
    mapping ( address => bool ) canModerate;
    address _tokenOwner;
    address _useless;
    address _pcsRouter;
    address _tokenRep;
    bool receiveDisabled;
    EclipseDataFetcher _fetcher;
    uint256 lastDecay;
}


contract Eclipse is EclipseData, IEclipse, Proxyable {
    
    using SafeMath for uint256; 
    
    modifier isModerator() {require(canModerate[msg.sender], 'Only Moderator'); _; }
    modifier isTokenOwner() {require(msg.sender == _tokenOwner, 'Only Owner'); _; }
    modifier isMaster() {require(_fetcher.isMaster(msg.sender), 'Only Master'); _; }
    
    constructor(address tokenOwner, address _token) {
        require(msg.sender == 0xf5f91867eBA4F7439997C6D90377557aA612fCF5);
        _bind(tokenOwner,_token);
    }
    
    function bind(address tokenOwner, address _token) external override {
        _bind(tokenOwner, _token);
    }
    
    function _bind(address tokenOwner, address _token) private {
        require(_useless == address(0), 'Proxy Already Bound');
        canModerate[tokenOwner] = true;
        _tokenOwner = tokenOwner;
        _tokenRep = _token;
        _useless = 0x2cd2664Ce5639e46c6a3125257361e01d0213657;
        _pcsRouter = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
        _fetcher = EclipseDataFetcher(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        lastDecay = block.number;
    }
    
    //////////////////////////////////////////
    ///////     OWNER FUNCTIONS    ///////////
    //////////////////////////////////////////
    
    function setModerator(address mod, bool canMod) external isTokenOwner {
        canModerate[mod] = canMod;
        emit SetModerator(mod, canMod);
    }
    
    //////////////////////////////////////////
    ///////    MASTER FUNCTIONS    ///////////
    //////////////////////////////////////////
    
    function decay() external override isMaster {
        require(lastDecay + _fetcher.getDecayPeriod() <= block.number, 'Not Time To Decay');
        lastDecay = block.number;
        uint256 bal = IERC20(_useless).balanceOf(address(this));
        uint256 decayFee = _fetcher.getDecayFee();
        uint256 minimum = _fetcher.getUselessMinimumToDecayFullBalance();
        uint256 takeBal = bal <= minimum ? bal : bal.div(decayFee);
        address furnace = _fetcher.getFurnace();
        bool success = IERC20(_useless).transfer(furnace, takeBal);
        require(success, 'Failure on Useless Transfer To Furnace');
        emit Decay(takeBal);
    }
    
    
    //////////////////////////////////////////
    ///////   MODERATOR FUNCTIONS  ///////////
    //////////////////////////////////////////
    
    
    function liquidateToken(address token) external isModerator {
        liquidate(token, address(_pcsRouter));
    }
    
    function liquidateTokenCustomRouter(address token, address router) external isModerator {
        liquidate(token, router);
    }
    
    function swapTokenForUseless(address token) external isModerator {
        _swapTokenForUseless(token, _pcsRouter);
    }
    
    function swapTokenForUselessCustomRouter(address token, address router) external isModerator {
        _swapTokenForUseless(token, router);
    }
    
    
    //////////////////////////////////////////
    ///////    PRIVATE FUNCTIONS   ///////////
    //////////////////////////////////////////
    
    
    function liquidate(address token, address router) internal {
        require(token != _useless, 'Cannot Liquidate Useless Token');
        uint256 bal = IERC20(token).balanceOf(address(this));
        require(bal > 0, 'Insufficient Balance');
        
        IUniswapV2Router02 customRouter = IUniswapV2Router02(router);
        IERC20(token).approve(router, bal);
        
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = customRouter.WETH();
        
        receiveDisabled = true;
        customRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            bal,
            0,
            path,
            address(this),
            block.timestamp.add(30)
        );
        receiveDisabled = false;
        
        buyUseless(address(this).balance);
    }
    
    function _swapTokenForUseless(address token, address router) private {
        require(token != _useless, 'Cannot Liquidate Useless Token');
        uint256 bal = IERC20(token).balanceOf(address(this));
        require(bal > 0, 'Insufficient Balance');
        
        IUniswapV2Router02 customRouter = IUniswapV2Router02(router);
        IERC20(token).approve(router, bal);
        
        address[] memory path = new address[](3);
        path[0] = token;
        path[1] = customRouter.WETH();
        path[2] = _useless;
        
        customRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            bal,
            0,
            path,
            address(this),
            block.timestamp.add(30)
        );
        
    }
    
    function buyUseless(uint256 amount) private {
        if (amount == 0) return;
        address swapper = _fetcher.getSwapper();
        (bool success, ) = address(swapper).call{value: amount}("");
        require(success, 'Failed Useless Purchase');
    }
    
    receive() external payable {
        if (!receiveDisabled) {
            buyUseless(msg.value);
        }
    }
    
    //////////////////////////////////////////
    ///////     READ FUNCTIONS     ///////////
    //////////////////////////////////////////
    
    function getUselessInContract() external view returns (uint256) {
        return IERC20(_useless).balanceOf(address(this));
    }
    
    function getTokenRepresentative() external override view returns (address) {
        return _tokenRep;
    }
    
    // EVENTS
    event SetModerator(address moderator, bool canModerate);
    event Decay(uint256 numUseless);
    
}
