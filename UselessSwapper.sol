pragma solidity 0.8.0;

/**
 * Created September 1st 2021
 * Developed by Markymark (MoonMark)
 * Swapper Contract to Accept BNB and return Useless to Sender
 * Splitting off a tax to fuel the Useless Furnace
 */
// SPDX-License-Identifier: Unlicensed

import "./IERC20.sol";
import "./Address.sol";
import "./SafeMath.sol";
import "./IUniswapV2Router02.sol";
import "./ReentrantGuard.sol";

/**
 * BNB Sent to this contract will be used to automatically buy Useless and send it back to the sender
 */
contract UselessSwapper is ReentrancyGuard {
    
    using Address for address;
    using SafeMath for uint256;

    // Initialize Pancakeswap Router
    IUniswapV2Router02 public _router;
  
    // Receive Token From Swap 
    address public _token;
    
    // path of Token -> BNB
    address[] sellPath;
    
    // path of BNB -> Token 
    address[] buyPath;

    // Useless Furnace Address
    address public _uselessFurnace;

    // fee allocated to furnace
    uint256 public _furnaceFee;
    
    // fee allocated to furnace on bypass
    uint256 public _bypassFee;
    
    // whether we accept bnb for swaps or not
    bool public _swappingEnabled;

    // owner of Swapper
    address public _owner;
    modifier onlyOwner() {require(msg.sender == _owner, 'Only Owner Function!'); _;}
  
    // initialize variables
    constructor() {
        _token = 0x2cd2664Ce5639e46c6a3125257361e01d0213657;
        _router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        _uselessFurnace = 0x16F21Ae97D967E87792A40c826c0AA943b78A6ec;
        _furnaceFee = 80;
        _bypassFee = 40;
        _swappingEnabled = true;
        _owner = msg.sender;
        buyPath = new address[](2);
        sellPath = new address[](2);
        sellPath[0] = _token;
        sellPath[1] = _router.WETH();
        buyPath[0] = _router.WETH();
        buyPath[1] = _token;
    }
    
    /** Updates the Pancakeswap Router and Pancakeswap pairing for BNB In Case of migration */
    function updatePancakeswapRouter(address newPCSRouter) external onlyOwner {
        require(newPCSRouter != address(0), 'Cannot Set Pancakeswap Router To Zero Address');
        _router = IUniswapV2Router02(newPCSRouter);
        buyPath[0] = _router.WETH();
        sellPath[1] = _router.WETH();
        emit UpdatedPancakeswapRouter(newPCSRouter);
    }
    
    /** Updates The Useless Furnace in Case of Migration */
    function updateFurnaceContractAddress(address newFurnace) external onlyOwner {
        require(newFurnace != address(0), 'Cannot Set Furnace To Zero Address');
        _uselessFurnace = newFurnace;
        emit UpdateFurnaceContractAddress(newFurnace);
    }
    
    function updateUselessContractAddress(address newUselessAddress) external onlyOwner {
        require(newUselessAddress != address(0), 'CANNOT ASSIGN THE ZERO ADDRESS');
        _token = newUselessAddress;
        buyPath[1] = newUselessAddress;
        sellPath[0] = newUselessAddress;
        emit UpdatedUselessContractAddress(newUselessAddress);
    }
    
    /** Updates The Fee Taken By The Furnace */
    function updateFurnaceFee(uint256 newFee) external onlyOwner {
        require(newFee <= 500, 'Fee Too High!!');
        _furnaceFee = newFee;
        emit UpdatedFurnaceFee(newFee);
    }
    
    function updateBypassFee(uint256 newBypassFee) external onlyOwner {
        require(newBypassFee <= 500, 'Fee Too High!!');
        _bypassFee = newBypassFee;
        emit UpdatedBypassFee(newBypassFee);
    }
    
    function updateSwappingEnabled(bool swappingEnabled) external onlyOwner {
        _swappingEnabled = swappingEnabled;
        emit UpdatedSwappingEnabled(swappingEnabled);
    }

    /** Withdraws Tokens Mistakingly Sent To This Contract Address */
    function withdrawTokens(address tokenToWithdraw) external onlyOwner {
	    uint256 balance = IERC20(tokenToWithdraw).balanceOf(address(this));
	    require(balance > 0, 'Cannot Withdraw Token With Zero Balance');
	    bool success = IERC20(tokenToWithdraw).transfer(msg.sender, balance);
	    require(success, 'Token Transfer Failed');
	    emit OwnerWithdrawTokens(tokenToWithdraw, balance);
    }
  
    /** Withdraws BNB Given The Unlikely Scenario Some is Stuck inside the contract */
    function withdrawBNB() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, 'Cannot Withdraw Zero BNB');
	    (bool success,) = payable(msg.sender).call{value: balance, gas: 26000}("");
	    require(success, 'BNB Withdrawal Failed');
	    emit OwnerWithdrawBNB(balance);
    }
    
    /** Transfers Ownership To New Address */
    function transferOwnership(address newOwner) external onlyOwner {
        _owner = newOwner;
        emit OwnershipTransfered(newOwner);
    }
    
    /** Sells Token For Useless, Fueling the Useless Furnace. Requires Token Approval */
    function sellUselessForBNB(uint256 numUseless) external nonReentrant {
        // balance of Useless
        uint256 uselessBalance = IERC20(_token).balanceOf(msg.sender);
        // ensure they have enough useless
        require(numUseless <= uselessBalance && numUseless > 0, 'Insufficient Balance');
        // balance of contract before swap
        uint256 contractBalanceBefore = IERC20(_token).balanceOf(address(this));
        // move tokens into this swapper
        IERC20(_token).transferFrom(msg.sender, address(this), numUseless);
        // how many tokens were received from transfer
        uint256 receivedFromTransfer = IERC20(_token).balanceOf(address(this)).sub(contractBalanceBefore);
        // ensure we gained tokens and that it matches numUseless
        require(receivedFromTransfer > 0 && receivedFromTransfer >= numUseless, 'Incorrect Amount Received From Transfer');
        // sell these tokens for BNB, sending to owner
        sellToken(receivedFromTransfer);
    }
    
    function uselessBypass(address receiver, uint256 numTokens) external nonReentrant {
        // balance of Useless
        uint256 balance = IERC20(_token).balanceOf(msg.sender);
        // check balances
        require(numTokens <= balance && balance > 0, 'Insufficient Balance');
        // balance before transfer
        uint256 contractBalanceBefore = IERC20(_token).balanceOf(address(this));
        // transfer to this contract
        bool succOne = IERC20(_token).transferFrom(msg.sender, address(this), numTokens);
        // require success
        require(succOne, 'Failure on Transfer From');
        // transfer received tokens to recipient
        uint256 diff = IERC20(_token).balanceOf(address(this)).sub(contractBalanceBefore);
        // ensure it matches
        require(diff >= numTokens, 'Transfer was taxed');
        // apply fee to tokens
        uint256 tokensForFurnace = numTokens.mul(_bypassFee).div(1000);
        // tokens for Furnace
        uint256 tokensToTransfer = numTokens.sub(tokensForFurnace);
        // transfer tokens to recipient
        bool succTwo = IERC20(_token).transfer(receiver, tokensToTransfer);
        // transfer tokens to furnace
        bool success = IERC20(_token).transfer(_uselessFurnace, tokensForFurnace);
        // require success
        require(succTwo, 'Failure on Transfer To Recipient');
        require(success, 'Failure on Transfer To Furnace');
    }

    
    /** Swaps BNB For Useless, sending fee to furnace */
    function purchaseToken() private {
        // fee removed for Useless Furnace
        uint256 furnaceFee = _furnaceFee.mul(msg.value).div(1000);
        // amount to swap for USELESS
        uint256 bnbToSwap = msg.value.sub(furnaceFee);
        // balance before Swap
        uint256 balanceBefore = IERC20(_token).balanceOf(address(this));
        // Swap BNB for Token
        try _router.swapExactETHForTokens{value: bnbToSwap}(
            0,
            buyPath,
            address(this),
            block.timestamp.add(30)
        ) {} catch{revert();}
        // balance after
        uint256 balanceAfter = IERC20(_token).balanceOf(address(this)).sub(balanceBefore);
        // transfer balance after to sender
        bool successful = IERC20(_token).transfer(msg.sender, balanceAfter);
        // ensure transfer was successful
        require(successful, 'Failed on Token Transfer');
        // send proceeds to furnace
        (bool success,) = payable(_uselessFurnace).call{value: furnaceFee, gas:26000}("");
        require(success, 'Furnace Payment Failed');
    }
    
        
    /** Swaps BNB For Useless, sending fee to furnace */
    function sellToken(uint256 numTokens) private {
        
        // fee removed for Useless Furnace
        uint256 furnaceFee = _furnaceFee.mul(numTokens).div(1000);
        // amount to swap for USELESS
        uint256 tokensToSwap = numTokens.sub(furnaceFee);
        // approve PCS Router of Useless Amount
        IERC20(_token).approve(address(_router), tokensToSwap);
        
        // Swap BNB for Token
        try _router.swapExactTokensForETH(
            tokensToSwap,
            0,
            sellPath,
            msg.sender,
            block.timestamp.add(30)
        ) {} catch{revert();}

        bool success = IERC20(_token).transfer(_uselessFurnace, furnaceFee);
        require(success, 'Furnace Payment Failed');
    }
	
    // Swap For Useless
    receive() external payable {
        require(_swappingEnabled, 'Swapping Is Disabled');
        purchaseToken();
    }

    // EVENTS
    event UpdatedFurnaceFee(uint256 newFee);
    event UpdatedBypassFee(uint256 newBypassFee);
    event UpdatedSwappingEnabled(bool swappingEnabled);
    event UpdatedPancakeswapRouter(address newRouter);
    event UpdateFurnaceContractAddress(address newFurnaceContractAddrss);
    event UpdatedUselessContractAddress(address newUselessContractAddress);
    event OwnerWithdrawTokens(address tokenWithdrawn, uint256 numTokensWithdrawn);
    event OwnerWithdrawBNB(uint256 numBNB);
    event OwnershipTransfered(address newOwner);
  
}  