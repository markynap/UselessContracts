pragma solidity 0.8.4;
// SPDX-License-Identifier: Unlicensed

/**
 * Created Sept 2 2021
 * Developed by Markymark (DeFiMark / MoonMark)
 * USELESS Furnace Contract to stablize the Useless Liquidity Pool
 */
 
import "./IERC20.sol";
import "./Address.sol";
import "./SafeMath.sol";
import "./IUniswapV2Router02.sol";
import "./ReentrantGuard.sol";

/**
 * 
 * BNB Sent to this contract will be used to automatically manage the Useless Liquidity Pool
 * Ideally keeping Liquidity Pool Size between 7% - 12.5% of the circulating supply of Useless
 * Liquidity over 20% - LP Extraction
 * Liquidity over 12.5% - Buy/Burn Useless
 * Liquidity between 6.67 - 12.5%  - ReverseSwapAndLiquify
 * Liquidity under 6.67% - LP Injection
 *
 */
contract UselessFurnace is ReentrancyGuard {
    
    using Address for address;
    using SafeMath for uint256;
  
    /**  Useless Stats  **/
    uint256 constant totalSupply = 1000000000 * 10**6 * 10**9;
    address constant _burnWallet = 0x000000000000000000000000000000000000dEaD;
    address constant _token = 0x2cd2664Ce5639e46c6a3125257361e01d0213657;
    address constant private _tokenLP = 0x08A6cD8a2E49E3411d13f9364647E1f2ee2C6380;
  
    /** address of wrapped bnb **/ 
    address constant private _bnb = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    /** Liquidity Pairing Threshold **/
    uint256 constant public pairLiquidityUSELESSThreshold = 5 * 10**16;
  
    /** Expressed as 100 / x **/
    uint256 constant public pullLiquidityRange = 5;
    uint256 constant public buyAndBurnRange = 8;
    uint256 constant public reverseSALRange = 15;
  
    /** BNB Thresholds **/
    uint256 constant public automateThreshold = 2 * 10**17;
    uint256 constant max_bnb_in_call = 50 * 10**18;
  
    /** Pancakeswap Router **/
    IUniswapV2Router02 constant router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
  
    /** Flash-Loan Prevention **/
    uint256 lastBlockAutomated;
    
    /** BNB -> Token **/
    address[] private bnbToToken;

    constructor() {
        // BNB -> Token
        bnbToToken = new address[](2);
        bnbToToken[0] = router.WETH();
        bnbToToken[1] = _token;
    }
  
    /** Automate Function */
    function BURN_IT_DOWN_BABY() external nonReentrant {
        require(address(this).balance >= automateThreshold, 'Not Enough BNB To Trigger Automation');
        require(lastBlockAutomated + 3 < block.number, '4 Blocks Must Pass Until Next Trigger');
        lastBlockAutomated = block.number;
        automate();
    }

    /** Automate Function */
    function automate() private {
        // check useless standing
        checkUselessStanding();
        // determine the health of the lp
        uint256 dif = determineLPHealth();
        // check cases
        dif = clamp(dif, 1, 100);
    
        if (dif <= pullLiquidityRange) {
            uint256 percent = uint256(100).div(dif);
            // pull liquidity
            pullLiquidity(percent);
        } else if (dif <= buyAndBurnRange) {
            // if LP is over 12.5% of Supply we buy burn useless
            buyAndBurn();
        } else if (dif <= reverseSALRange) {
            // if LP is between 6.666%-12.5% of Supply we call reverseSAL
            reverseSwapAndLiquify();
        } else {
            // if LP is under 6.666% of Supply we provide a pairing if one exists, else we call reverseSAL
            uint256 tokenBal = IERC20(_token).balanceOf(address(this));
            if (liquidityThresholdReached(tokenBal)) {
                pairLiquidity(tokenBal);
            } else {
                reverseSwapAndLiquify();
            }
        }
    }

    /**
     * Buys USELESS Tokens and sends them to the burn wallet
     */ 
    function buyAndBurn() private {
        // keep bnb in range
        uint256 bnbToUse = address(this).balance > max_bnb_in_call ? max_bnb_in_call : address(this).balance;
        // buy and burn it
        router.swapExactETHForTokens{value: bnbToUse}(
            0, 
            bnbToToken,
            _burnWallet, // Burn Address
            block.timestamp.add(30)
        );
        // tell blockchain
        emit BuyAndBurn(bnbToUse);
    }
  
   /**
    * Uses BNB in Contract to Purchase Useless, pairs with remaining BNB and adds to Liquidity Pool
    * Reversing The Effects Of SwapAndLiquify
    * Price Positive - LP Neutral Operation
    */
    function reverseSwapAndLiquify() private {
        // BNB Balance before the swap
        uint256 initialBalance = address(this).balance > max_bnb_in_call ? max_bnb_in_call : address(this).balance;
        // USELESS Balance before the Swap
        uint256 contractBalance = IERC20(_token).balanceOf(address(this));
        // Swap 50% of the BNB in Contract for USELESS Tokens
        uint256 transferAMT = initialBalance.div(2);
        // Swap BNB for USELESS
        router.swapExactETHForTokens{value: transferAMT}(
            0, // accept any amount of USELESS
            bnbToToken,
            address(this), // Store in Contract
            block.timestamp.add(30)
        );
        // how many USELESS Tokens were received
        uint256 diff = IERC20(_token).balanceOf(address(this)).sub(contractBalance);
        // add liquidity to Pancakeswap
        addLiquidity(diff, transferAMT);
        emit ReverseSwapAndLiquify(diff, transferAMT);
    }
   
    /**
     * Pairs BNB and USELESS in the contract and adds to liquidity if we are above thresholds 
     */
    function pairLiquidity(uint256 uselessInContract) private {
        // amount of bnb in the pool
        uint256 bnbLP = IERC20(_bnb).balanceOf(_tokenLP);
        // make sure we have tokens in LP
        bnbLP = bnbLP == 0 ? address(_tokenLP).balance : bnbLP;
        // how much BNB do we need to pair with our useless
        uint256 bnbbal = getTokenInToken(_token, _bnb, uselessInContract);
        //if there isn't enough bnb in contract
        if (address(this).balance < bnbbal) {
            // recalculate with bnb we have
            uint256 nUseless = uselessInContract.mul(address(this).balance).div(bnbbal);
            addLiquidity(nUseless, address(this).balance);
            emit LiquidityPairAdded(nUseless, address(this).balance);
        } else {
            // pair liquidity as is 
            addLiquidity(uselessInContract, bnbbal);
            emit LiquidityPairAdded(uselessInContract, bnbbal);
        }
    }
    
    /** Checks Number of Tokens in LP */
    function checkUselessStanding() private {
        uint256 threshold = getCirculatingSupply().div(10**4);
        uint256 uselessBalance = IERC20(_token).balanceOf(address(this));
        if (uselessBalance >= threshold) {
            // burn 1/4 of balance
            try IERC20(_token).transfer(_burnWallet, uselessBalance.div(4)) {} catch {}
        }
    }
   
    /** Returns the price of tokenOne in tokenTwo according to Pancakeswap */
    function getTokenInToken(address tokenOne, address tokenTwo, uint256 amtTokenOne) public view returns (uint256){
        address[] memory path = new address[](2);
        path[0] = tokenOne;
        path[1] = tokenTwo;
        return router.getAmountsOut(amtTokenOne, path)[1];
    } 
    
    /**
     * Adds USELESS and BNB to the USELESS/BNB Liquidity Pool
     */ 
    function addLiquidity(uint256 uselessAmount, uint256 bnbAmount) private {
       
        // approve router to move tokens
        IERC20(_token).approve(address(router), uselessAmount);
        // add the liquidity
        try router.addLiquidityETH{value: bnbAmount}(
            _token,
            uselessAmount,
            0,
            0,
            address(this),
            block.timestamp.add(30)
        ) {} catch{}
    }

    /**
     * Removes Liquidity from the pool and stores the BNB and USELESS in the contract
     */
    function pullLiquidity(uint256 percentLiquidity) private returns (bool){
       // Percent of our LP Tokens
       uint256 pLiquidity = IERC20(_tokenLP).balanceOf(address(this)).mul(percentLiquidity).div(10**2);
       // Approve Router 
       IERC20(_tokenLP).approve(address(router), 115792089237316195423570985008687907853269984665640564039457584007913129639935);
       // remove the liquidity
       try router.removeLiquidityETHSupportingFeeOnTransferTokens(
            _token,
            pLiquidity,
            0,
            0,
            address(this),
            block.timestamp.add(30)
        ) {} catch {return false;}
        
        emit LiquidityPulled(percentLiquidity, pLiquidity);
        return true;
    }
    
    /**
     * Determines the Health of the LP
     * returns the percentage of the Circulating Supply that is in the LP
     */ 
    function determineLPHealth() public view returns(uint256) {
        // Find the balance of USELESS in the liquidity pool
        uint256 lpBalance = IERC20(_token).balanceOf(_tokenLP);
        // lpHealth = Supply / LP Balance
        return lpBalance == 0 ? 6 : getCirculatingSupply().div(lpBalance);
    }
    
    /** Whether or not the Pair Liquidity Threshold has been reached */
    function liquidityThresholdReached(uint256 bal) private view returns (bool) {
        uint256 circulatingSupply = getCirculatingSupply();
        uint256 pow = circulatingSupply < (10**10 * 10**9) ? 5 : 7;
        return bal >= getCirculatingSupply().div(10**pow);
    }
  
    /** Returns the Circulating Supply of Token */
    function getCirculatingSupply() private view returns(uint256) {
        return totalSupply.sub(IERC20(_token).balanceOf(_burnWallet));
    }
  
    /** Amount of LP Tokens in this contract */ 
    function getLPTokenBalance() external view returns (uint256) {
        return IERC20(_tokenLP).balanceOf(address(this));
    }
  
    /** Percentage of LP Tokens In Contract */
    function getPercentageOfLPTokensOwned() external view returns (uint256) {
        return uint256(10**18).mul(IERC20(_tokenLP).balanceOf(address(this))).div(IERC20(_tokenLP).totalSupply());
    }
      
    /** Clamps a variable between a min and a max */
    function clamp(uint256 variable, uint256 min, uint256 max) private pure returns (uint256){
        if (variable <= min) {
            return min;
        } else if (variable >= max) {
            return max;
        } else {
            return variable;
        }
    }
  
    // EVENTS 
    event BuyAndBurn(uint256 amountBNBUsed);
    event ReverseSwapAndLiquify(uint256 uselessAmount,uint256 bnbAmount);
    event LiquidityPairAdded(uint256 uselessAmount,uint256 bnbAmount);
    event LiquidityPulled(uint256 percentOfLiquidity, uint256 numLPTokens);

    // Receive BNB
    receive() external payable { }

}