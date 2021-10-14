//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./Address.sol";
import "./IERC20.sol";
import "./SafeMath.sol";
import "./IUniswapV2Router02.sol";
import "./IDiscountBuyer.sol";

contract tokenDiscountBuyer is IDiscountBuyer {
    
    using Address for address;
    using SafeMath for uint256;

    // constants
    uint256 constant unit = 10**18;
    uint256 constant _denominator = 10**5;
    address constant token = 0x2cd2664Ce5639e46c6a3125257361e01d0213657;
    
    // fees
    uint256 public _startingFee;
    uint256 public _minFee;
    uint256 public _bnbPercent;
    address public _furnace;
    
    // receiver for user
    mapping ( address => address ) receiveForUser;

    // math
    uint256 public _factor;
    uint256 public _minBNB;
    
    // PCS 
    IUniswapV2Router02 _router;
    address[] path;
    
    // swaps
    bool public _swapEnabled;
    
    // ownership
    address _master;
    modifier onlyOwner(){require(msg.sender == _master, 'Invalid Entry'); _;}
    
    // events
    event BoughtAndReturnedtoken(address to, uint256 amounttoken);
    event UpdatedBNBPercentage(uint256 newPercent);
    event UpdatedFactor(uint256 newFactor);
    event UpdatedMinBNB(uint256 newMin);
    event UpdatedMinimumFee(uint256 minFee);
    event UpdatedStartingFee(uint256 newStartingFee);
    event UpdatedFurnace(address newDistributor);
    event UpdatedSwapEnabled(bool swapEnabled);
    event TransferredOwnership(address newOwner);

    constructor() {
        // ownership
        _master = msg.sender;
        // state
        _swapEnabled = true;
        _minBNB = 10 * unit;
        _factor = 30;
        _startingFee = 5000;
        _bnbPercent = 50;
        _minFee = 0;
        _furnace = 0x03F9332cBA1dFc80b503b7EE3A085FBB8532abea;
        _router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        path = new address[](2);
        path[0] = _router.WETH();
        path[1] = token;
    }
    
    function setReceiveForUser(address receiver) external override {
        receiveForUser[msg.sender] = receiver;
    }
    
    function getReceiveForUser(address user) public view returns (address) {
        return receiveForUser[user] == address(0) ? user : receiveForUser[user];
    }

    function buyToken() private {
        
        // calculate fees
        (uint256 _furnaceFee, uint256 _burnFee) = calculateFees(msg.value);
        
        // portion out amounts
        uint256 furnaceAmount = msg.value.mul(_furnaceFee).div(_denominator);
        uint256 swapAmount = msg.value.sub(furnaceAmount);
        
        // purchase token
        uint256 tokenReceived = purchaseToken(swapAmount);
        
        // send bnb to distributor
        if (furnaceAmount > 0) {
            (bool s2,) = payable(_furnace).call{value: furnaceAmount}("");
            require(s2, 'Error On Distributor Payment');
        }
        
        // portion amount for sender
        uint256 burnAmount = tokenReceived.mul(_burnFee).div(_denominator);
        uint256 sendAmount = tokenReceived.sub(burnAmount);
        
        // receiver of token
        address receiver = getReceiveForUser(msg.sender);
        
        // transfer token To Sender
        bool success = IERC20(token).transfer(receiver, sendAmount);
        require(success, 'Error on token Transfer');
        
        // Send token Balance To Furnace
        if (burnAmount > 0) {
            bool successful = IERC20(token).transfer(_furnace, burnAmount);
            require(successful, 'Error Sending token To Furnace');
        }
        emit BoughtAndReturnedtoken(receiver, sendAmount);
    }
    
    function purchaseToken(uint256 amount) internal returns (uint256) {
        uint256 tokenBefore = IERC20(token).balanceOf(address(this));
        _router.swapExactETHForTokens{value: amount}(
            0,
            path,
            address(this),
            block.timestamp.add(30)
        );
        return IERC20(token).balanceOf(address(this)).sub(tokenBefore);
    }
    
    function calculateFees(uint256 amount) public view returns (uint256, uint256) {
        
        uint256 bVal = _factor.mul(amount).div(unit);
        if (bVal >= _startingFee) {
            return (_minFee,_minFee);
        }
        
        uint256 fee = _startingFee.sub(bVal).add(_minFee);
        uint256 rAlloc = _bnbPercent.mul(fee).div(10**2);
        return (rAlloc, fee.sub(rAlloc));
    }
    
    function updateBNBPercentage(uint256 bnbPercent) external onlyOwner {
        require(bnbPercent <= 100);
        _bnbPercent = bnbPercent;
        emit UpdatedBNBPercentage(bnbPercent);
    }
    
    function updateFactor(uint256 newFactor) external onlyOwner {
        _factor = newFactor;
        emit UpdatedFactor(newFactor);
    }
    
    function updateMinimumBNB(uint256 newMinimum) external onlyOwner {
        _minBNB = newMinimum;
        emit UpdatedMinBNB(newMinimum);
    }
    
    function updateStartingFee(uint256 newFee) external onlyOwner {
        _startingFee = newFee;
        emit UpdatedStartingFee(newFee);
    }
    
    function updateFurnaceAddress(address newFurnace) external onlyOwner {
        _furnace = newFurnace;
        emit UpdatedFurnace(newFurnace);
    }
    
    function setSwapperEnabled(bool isEnabled) external onlyOwner {
        _swapEnabled = isEnabled;
        emit UpdatedSwapEnabled(isEnabled);
    }
    
    function setMinFee(uint256 minFee) external onlyOwner {
        _minFee = minFee;
        emit UpdatedMinimumFee(minFee);
    }

    function withdrawBNB(uint256 percent) external onlyOwner returns (bool s) {
        uint256 am = address(this).balance.mul(percent).div(10**2);
        require(am > 0);
        (s,) = payable(_master).call{value: am}("");
    }

    function withdrawToken(address _token) external onlyOwner {
        uint256 bal = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(_master, bal);
    }

    function transferOwnership(address newMaster) external onlyOwner {
        _master = newMaster;
        emit TransferredOwnership(newMaster);
    }
    
    receive() external payable {
        require(_swapEnabled, 'Swapper Is Disabled');
        require(msg.value >= _minBNB, 'Purchase Value Too Small');
        buyToken();
    }
}
