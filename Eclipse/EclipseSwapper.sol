

import "./EclipseData.sol";
import "./IUniswapV2Router02.sol";
import "./ReentrantGuard.sol";

contract EclipseSwapper is ReentrancyGuard {

    address constant _v2router = 0x10ED43C718714eb63d5aA57B78B54704E256024E;

    EclipseData _data;

    mapping (address => uint256) bnbPerToken;

    uint256 public _marketingCut;

    address _master;
    modifer onlyOwner(){require(msg.sender == _master, 'Only Owner'); _;}

    constructor(){
        _data = EclipseData(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        _master = msg.sender;
    }

    function buyToken(address token) external payable nonReentrant{
        _buyToken(token, _v2router);
    }
    
    function buyTokenCustomRouter(address token, address router) external payable nonReentrant {
        _buyToken(token, router);
    }
    
    function _buyToken(address token, address router) private {
        require(msg.value >= 10**9, 'Purchase Too Small');
        bnbPerToken[token] = bnbPerToken[token].add(msg.value);
        
        IUniswapV2Router02 customRouter = IUniswapV2Router02(router);
        address[] memory path = new address[](2);
        path[0] = customRouter.WETH();
        path[1] = token;
        
        uint256 tax = _data.calculateSwapperFee(token, msg.value);
        uint256 swapAmount = msg.value.sub(tax);
        uint256 marketingTax = tax.mul(_marketingCut).div(10**2);
        tax = tax.sub(marketingTax);
        
        customRouter.swapExactETHForTokens{value:swapAmount}(
            0,
            path,
            msg.sender,
            block.timestamp.add(30)
        );
        if (tax > 0) {
            (bool success,) = payable(_data.getFurnace()).call{value: tax}("");
            require(success, 'BNB Transfer To Furnace Failure');
        }
        if (marketingTax > 0) {
            (bool success,) = payable(_data.getMarketing()).call{value: marketingTax}("");
            require(success, 'BNB Transfer To Furnace Failure');
        }
    }
    
    function transferOwnership(address newOwner) external onlyOwner {
        _master = newOwner;
    }

    function setMarketingTaxCut(uint256 newTaxCut) external onlyOwner {
        _marketingCut = newTaxCut;
    }

}