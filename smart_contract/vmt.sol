// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@pancakeswap/pancake-swap-lib/contracts/utils/FixedPoint.sol";
import "https://github.com/sadiq1971/sol-contracts/blob/main/lib/Ownable.sol";
import "https://github.com/sadiq1971/sol-contracts/blob/main/token/bep20/IBEP20.sol";
import "https://github.com/sadiq1971/sol-contracts/blob/main/uniswap/interface/IUniswapV2Pair.sol";
import "https://github.com/sadiq1971/sol-contracts/blob/main/uniswap/interface/IUniswapV2Router01.sol";
import "https://github.com/sadiq1971/sol-contracts/blob/main/uniswap/interface/IUniswapV2Router02.sol";
import "https://github.com/sadiq1971/sol-contracts/blob/main/uniswap/interface/IUniswapV2Factory.sol";
import "https://github.com/sadiq1971/sol-contracts/blob/main/uniswap/lib/UniswapOracleLibrary.sol";


contract Vemate is  IBEP20, Ownable{
    using FixedPoint for *;

    struct FeeWallet {
        address  payable dev;
        address  payable marketing;
        address  payable charity;
    }

    struct FeePercent {
        uint8  lp;
        uint8  dev;
        uint8  marketing;
        uint8  charity;
        bool enabledOnBuy;
        bool enabledOnSell;
    }

    FeeWallet public feeWallets;
    FeePercent public fee  = FeePercent(2, 1, 1, 1, false, true);

    IUniswapV2Router02 public uniswapV2Router;

    string private  _name = "Vemate";
    string private _symbol = "V";

    // Pack variables together for gas optimization
    uint8   private _decimals = 18;
    uint8   public constant maxFeePercent = 5;
    uint8   public swapSlippageTolerancePercent = 10;
    bool    private antiBot = true;
    bool    private inSwapAndLiquify;
    bool    public swapAndLiquifyEnabled = true;
    uint32  private blockTimestampLast;

    address public uniswapV2Pair;

    uint256 private _totalSupply = 150000000 * 10**_decimals; // 150 million;

    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) private _isPrivileged;
    mapping (address => uint) private _addressToLastSwapTime;

    uint256 public lockedBetweenSells = 60;
    uint256 public lockedBetweenBuys = 60;
    uint256 public maxTxAmount = _totalSupply;
    uint256 public numTokensSellToAddToLiquidity = 10000 * 10**_decimals; // 10000 Token

    // We will depend on external price for the token to protect the sandwich attack.
    uint256 public tokenPerBNB = 23810;


    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    constructor(
        address router,
        address payable devAddress,
        address payable marketingAddress,
        address payable charityAddress
    ){
        require(owner() != address(0), "Owner must be set");
        require(router != address(0), "Router must be set");
        require(devAddress != address(0), "Dev wallet must be set");
        require(marketingAddress != address(0), "Marketing wallet must be set");
        require(charityAddress != address(0), "Charity wallet must be set");

        _isPrivileged[owner()] = true;
        _isPrivileged[devAddress] = true;
        _isPrivileged[marketingAddress] = true;
        _isPrivileged[charityAddress] = true;
        _isPrivileged[address(this)] = true;

        // set wallets for collecting fees
        feeWallets = FeeWallet(devAddress, marketingAddress, charityAddress);

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(router);
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH());
        uniswapV2Router = _uniswapV2Router;

        _balances[_msgSender()] = _totalSupply;

        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    function setRouterAddress(address newRouter) external onlyOwner {
        IUniswapV2Router02 _newPancakeRouter = IUniswapV2Router02(newRouter);
        IUniswapV2Factory factory = IUniswapV2Factory(_newPancakeRouter.factory()
        );
        address pair = factory.getPair(address(this), _newPancakeRouter.WETH());
        if (pair == address(0)) {
            uniswapV2Pair = factory.createPair(address(this), _newPancakeRouter.WETH());
        } else {
            uniswapV2Pair = pair;
        }

        uniswapV2Router = _newPancakeRouter;

        emit UpdatePancakeRouter(uniswapV2Router, uniswapV2Pair);
    }

    function setDevWallet(address payable devWallet) external onlyOwner{
        require(devWallet != address(0),  "Dev wallet must be set");
        address devWalletPrev = feeWallets.dev;
        feeWallets.dev = devWallet;

        _isPrivileged[devWallet] = true;
        delete _isPrivileged[devWalletPrev];

        emit UpdateDevWallet(devWallet, devWalletPrev);
    }

    function setMarketingWallet(address payable marketingWallet) external onlyOwner{
        require(marketingWallet != address(0),  "Marketing wallet must be set");
        address marketingWalletPrev = feeWallets.marketing;
        feeWallets.marketing = marketingWallet;

        _isPrivileged[marketingWallet] = true;
        delete _isPrivileged[marketingWalletPrev];

        emit UpdateMarketingWallet(marketingWallet, marketingWalletPrev);
    }

    function setCharityWallet(address payable charityWallet) external onlyOwner{
        require(charityWallet != address(0),  "Charity wallet must be set");
        address charityWalletPrev = feeWallets.charity;
        feeWallets.charity = charityWallet;

        _isPrivileged[charityWallet] = true;
        delete _isPrivileged[charityWalletPrev];

        emit UpdateCharityWallet(charityWallet, charityWalletPrev);
    }

    function addPrivilegedWallet(address newPrivilegedAddress) external onlyOwner {
        require(newPrivilegedAddress != address(0), "privileged address can not be set zero address");
        require(_isPrivileged[newPrivilegedAddress] != true, "already privileged");
        _isPrivileged[newPrivilegedAddress] = true;

        emit PrivilegedWallet(newPrivilegedAddress, true);
    }

    function removePrivilegedWallet(address prevPrivilegedAddress) external onlyOwner {
        require(_isPrivileged[prevPrivilegedAddress] != false, "not privileged address");    
        delete _isPrivileged[prevPrivilegedAddress];

        emit PrivilegedWallet(prevPrivilegedAddress, false);
    }

    function privilegedAddress(address existingPrivilegedAddress) public view returns(bool){
        return _isPrivileged[existingPrivilegedAddress];
    }

    function setLpFeePercent(uint8 lpFeePercent) external onlyOwner {
        FeePercent memory currentFee = fee;
        uint8 totalFeePercent = currentFee.marketing + currentFee.dev + currentFee.charity + lpFeePercent;
        require(totalFeePercent <= maxFeePercent, "Total fee percent cannot be greater than maxFeePercent");
        uint8 previousFee = currentFee.lp;
        currentFee.lp = lpFeePercent;
        fee = currentFee;

        emit UpdateLpFeePercent(lpFeePercent, previousFee);
    }

    function setDevFeePercent(uint8 devFeePercent) external onlyOwner {
        FeePercent memory currentFee = fee;
        uint8 totalFeePercent = currentFee.marketing + currentFee.lp + currentFee.charity + devFeePercent;
        require(totalFeePercent <= maxFeePercent, "Total fee percent cannot be greater than maxFeePercent");
        uint8 previousFee = currentFee.dev;
        currentFee.dev = devFeePercent;
        fee = currentFee;

        emit UpdateDevFeePercent(devFeePercent, previousFee);
    }

    function setMarketingFeePercent(uint8 marketingFeePercent) external onlyOwner {
        FeePercent memory currentFee = fee;
        uint8 totalFeePercent = currentFee.lp + currentFee.dev + currentFee.charity + marketingFeePercent;
        require(totalFeePercent <= maxFeePercent, "Total fee percent cannot be greater than maxFeePercent");
        uint8 previousFee = currentFee.marketing;
        currentFee.marketing = marketingFeePercent;
        fee = currentFee;

        emit UpdateMarketingFeePercent(marketingFeePercent, previousFee);
    }

    function setCharityFeePercent(uint8 charityFeePercent) external onlyOwner {
        FeePercent memory currentFee = fee;
        uint8 totalFeePercent = currentFee.marketing + currentFee.dev + currentFee.lp + charityFeePercent;
        require(totalFeePercent <= maxFeePercent, "Total fee percent cannot be greater than maxFeePercent");
        uint8 previousFee = currentFee.charity;
        currentFee.charity = charityFeePercent;
        fee = currentFee;

        emit UpdateCharityFeePercent(charityFeePercent, previousFee);
    }

    function togglePauseBuyingFee() external onlyOwner{
        fee.enabledOnBuy = !fee.enabledOnBuy;
        emit UpdateBuyingFee(fee.enabledOnBuy);
    }

    function togglePauseSellingFee() external onlyOwner{
        fee.enabledOnSell = !fee.enabledOnSell;
        emit UpdateSellingFee(fee.enabledOnSell);
    }

    function setLockTimeBetweenSells(uint256 newLockSeconds) external onlyOwner {
        require(newLockSeconds <= 30, "Time between sells must be less than 30 seconds");
        uint256 _previous = lockedBetweenSells;
        lockedBetweenSells = newLockSeconds;
        emit UpdateLockedBetweenSells(lockedBetweenSells, _previous);
    }

    function setLockTimeBetweenBuys(uint256 newLockSeconds) external onlyOwner {
        require(newLockSeconds <= 30, "Time between buys be less than 30 seconds");
        uint256 _previous = lockedBetweenBuys;
        lockedBetweenBuys = newLockSeconds;
        emit UpdateLockedBetweenBuys(lockedBetweenBuys, _previous);
    }

    function toggleAntiBot() external onlyOwner {
        antiBot = !antiBot;
        emit UpdateAntibot(antiBot);
    }

    function setMaxTxAmount(uint256 amount) external onlyOwner{
        uint256 prevTxAmount = maxTxAmount;
        maxTxAmount = amount;
        emit UpdateMaxTxAmount(maxTxAmount, prevTxAmount);
    }

    function updateTokenPrice(uint256 _tokenPerBNB) external onlyOwner {
        tokenPerBNB = _tokenPerBNB;
        emit UpdateTokenPerBNB(tokenPerBNB);
    }

    function toggleSwapAndLiquify() external onlyOwner{
        swapAndLiquifyEnabled = !swapAndLiquifyEnabled;
        emit UpdateSwapAndLiquify(swapAndLiquifyEnabled);
    }

    function setSwapTolerancePercent(uint8 newTolerancePercent) external onlyOwner{
        require(newTolerancePercent <= 100, "Swap tolerance percent cannot be more than 100");
        uint8 swapTolerancePercentPrev = swapSlippageTolerancePercent;
        swapSlippageTolerancePercent = newTolerancePercent;
        emit UpdateSwapTolerancePercent(swapSlippageTolerancePercent, swapTolerancePercentPrev);
    }

    function setMinTokenToSwapAndLiquify(uint256 amount) external onlyOwner{
        uint256 numTokensSellToAddToLiquidityPrev = numTokensSellToAddToLiquidity;
        numTokensSellToAddToLiquidity = amount;
        emit UpdateMinTokenToSwapAndLiquify(numTokensSellToAddToLiquidity, numTokensSellToAddToLiquidityPrev);
    }

    function withdrawResidualBNB(address newAddress) external onlyOwner() {
        payable(newAddress).transfer(address(this).balance);
    }

    function withdrawResidualToken(address newAddress) external onlyOwner() {
        _transfer(address(this), newAddress, _balances[address(this)]);
    }

    function withdrawResidualErc20(IBEP20 token, address to) external onlyOwner {
        require(address(token) != address(this), "Cannot withdraw own tokens");
        uint256 erc20balance = token.balanceOf(address(this));
        token.transfer(to, erc20balance);
    }

    /**
    * @dev Returns the bep token owner.
    */
    function getOwner() external override view returns (address) {
        return owner();
    }

    /**
    * @dev Returns the token decimals.
    */
    function decimals() external override view returns (uint8) {
        return _decimals;
    }

    /**
    * @dev Returns the token symbol.
    */
    function symbol() external override view returns (string memory) {
        return _symbol;
    }

    /**
    * @dev Returns the token name.
    */
    function name() external override view returns (string memory) {
        return _name;
    }

    /**
    * @dev See {BEP20-totalSupply}.
    */
    function totalSupply() external override view returns (uint256) {
        return _totalSupply;
    }

    /**
    * @dev See {BEP20-balanceOf}.
    */
    function balanceOf(address account) external override view returns(uint256){
        return _balances[account];
    }

    /**
    * @dev See {BEP20-transfer}.
    *
    * Requirements:
    *
    * - `recipient` cannot be the zero address.
    * - the caller must have a balance of at least `amount`.
    */
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
    * @dev See {BEP20-allowance}.
    */
    function allowance(address owner, address spender) external override view returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
    * @dev See {BEP20-approve}.
    *
    * Requirements:
    *
    * - `spender` cannot be the zero address.
    */
    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
    * @dev See {BEP20-transferFrom}.
    *
    * Emits an {Approval} event indicating the updated allowance. This is not
    * required by the EIP. See the note at the beginning of {BEP20};
    *
    * Requirements:
    * - `sender` and `recipient` cannot be the zero address.
    * - `sender` must have a balance of at least `amount`.
    * - the caller must have allowance for `sender`'s tokens of at least
    * `amount`.
    */
    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        _transfer(sender, recipient, amount);
        uint256 _currentAllowance = _allowances[sender][_msgSender()];
        // this check is not mandatory. but to return exact overflow reason we can use it.
        require(_currentAllowance >= amount, "BEP20: transfer amount exceeds allowance");
        _approve(sender, _msgSender(), _currentAllowance - amount);
        return true;
    }

    /**
    * @dev Atomically increases the allowance granted to `spender` by the caller.
    *
    * This is an alternative to {approve} that can be used as a mitigation for
    * problems described in {BEP20-approve}.
    *
    * Emits an {Approval} event indicating the updated allowance.
    *
    * Requirements:
    *
    * - `spender` cannot be the zero address.
    */
    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    /**
    * @dev Atomically decreases the allowance granted to `spender` by the caller.
    *
    * This is an alternative to {approve} that can be used as a mitigation for
    * problems described in {BEP20-approve}.
    *
    * Emits an {Approval} event indicating the updated allowance.
    *
    * Requirements:
    *
    * - `spender` cannot be the zero address.
    * - `spender` must have allowance for the caller of at least
    * `subtractedValue`.
    */
    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
        uint256 _currentAllowance = _allowances[_msgSender()][spender];
        // this check is not mandatory. but to return exact overflow reason we can use it.
        require(_currentAllowance >= subtractedValue, "BEP20: decreased allowance below zero");
        _approve(_msgSender(), spender, _currentAllowance - subtractedValue);
        return true;
    }

    /**
    * @dev Moves tokens `amount` from `sender` to `recipient`.
    *
    * This is internal function is equivalent to {transfer}, and can be used to
    * e.g. implement automatic token fees, slashing mechanisms, etc.
    *
    * Emits a {Transfer} event.
    *
    * Requirements:
    *
    * - `sender` cannot be the zero address.
    * - `recipient` cannot be the zero address.
    * - `sender` must have a balance of at least `amount`.
    */
    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "BEP20: transfer from the zero address");
        require(recipient != address(0), "BEP20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        require(_balances[sender] >= amount, "BEP20: transfer amount exceeds balance");

        bool takeFee = false;

        if (_isPrivileged[sender] || _isPrivileged[recipient]){
            // takeFee already false. Do nothing and reduce gas fee.
        } else if (recipient == uniswapV2Pair) { // sell : fee and restrictions for non-privileged wallet
            require(amount <= maxTxAmount, "Amount larger than max tx amount!");
            checkSwapFrequency(sender);
            if (fee.enabledOnSell){
                takeFee = true;
                if (shouldSwap()){
                    swapAndLiquify(numTokensSellToAddToLiquidity);
                }
            }
        } else if (sender == uniswapV2Pair){  // buy : fee and restrictions for non-privileged wallet
            require(amount <= maxTxAmount, "Amount larger than max tx amount!");
            checkSwapFrequency(recipient);
            if (fee.enabledOnBuy){
                takeFee = true;
                if (shouldSwap()){
                    swapAndLiquify(numTokensSellToAddToLiquidity);
                }
            }
        }
        _tokenTransfer(sender, recipient, amount, takeFee);
    }

    function shouldSwap() private view returns(bool)  {
        uint256 contractTokenBalance = _balances[(address(this))];
        bool overMinTokenBalance = contractTokenBalance >= numTokensSellToAddToLiquidity;

        if (overMinTokenBalance && !inSwapAndLiquify && swapAndLiquifyEnabled) {
            return true;
        }
        return false;
    }

    // to recieve ETH from uniswapV2Router when swapping
    receive() external payable {}

    function swapAndLiquify(uint256 amount) private lockTheSwap {
        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // We need to collect Bnb from the token amount
        // dev + marketing + charity will be send to the wallet
        // the rest(for liquid pool) will be divided into two and be used to addLiquidity
        uint8 totalFee = fee.dev + fee.lp + fee.charity + fee.marketing;
        uint256 lpHalf =  (amount*fee.lp)/(totalFee*2);

        // swap dev + marketing + charity + lpHalf
        swapTokensForEth(amount - lpHalf);

        // how much ETH did we just swap into?
        uint256 receivedBnb = address(this).balance - initialBalance;

        // get the Bnb amount for lpHalf
        uint256 lpHalfBnbShare = (receivedBnb*fee.lp)/(totalFee*2 - fee.lp); // to avoid possible floating point error
        uint256 devBnbShare = (receivedBnb*2*fee.dev)/(totalFee*2 - fee.lp);
        uint256 marketingBnbShare = (receivedBnb*2*fee.marketing)/(totalFee*2 - fee.lp);
        uint256 charityBnbShare = (receivedBnb*2*fee.charity)/(totalFee*2 - fee.lp);


        // feeWallets.lp.transfer(lpHalfBnbShare);
        feeWallets.dev.transfer(devBnbShare);
        feeWallets.marketing.transfer(marketingBnbShare);
        feeWallets.charity.transfer(charityBnbShare);

        addLiquidity(lpHalf, lpHalfBnbShare);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uint ethAmount = tokenAmount/tokenPerBNB;

        uint minETHAmount = ethAmount - (ethAmount* swapSlippageTolerancePercent)/100;

        // make the swap
        try uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            minETHAmount, // this will protect sandwich attack
            path,
            address(this),
            getCurrentTime()
        ){
            emit SwapAndLiquifyStatus("Success");
        }catch {
            emit SwapAndLiquifyStatus("Failed");
        }
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // require(msg.value>0, "No eth found in this account");
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uint minETHAmount = ethAmount - (ethAmount* swapSlippageTolerancePercent)/100;
        uint minTokenAmount = tokenAmount - (tokenAmount* swapSlippageTolerancePercent)/100;

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            minTokenAmount,
            minETHAmount,
            address(this),
            getCurrentTime()
        );
        emit LiquidityAdded(tokenAmount, ethAmount);
    }

    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 amount,
        bool takeFee
    ) internal {
        uint256 transferAmount = amount;
        if (takeFee) {
            uint8 totalFeePercent = fee.lp + fee.marketing + fee.charity + fee.dev;
            uint256 totalFee = (amount*totalFeePercent)/100;

            // send the fee token to the contract address.
            _balances[address(this)] = _balances[address(this)] + totalFee;
            transferAmount = transferAmount - totalFee;
            emit Transfer(sender, address(this), totalFee);
        }
        _balances[sender] = _balances[sender] - amount;
        _balances[recipient] = _balances[recipient] + transferAmount;
        emit Transfer(sender, recipient, transferAmount);
    }

    /**
    * @dev Sets `amount` as the allowance of `spender` over the `owner`s tokens.
    *
    * This is internal function is equivalent to `approve`, and can be used to
    * e.g. set automatic allowances for certain subsystems, etc.
    *
    * Emits an {Approval} event.
    *
    * Requirements:
    *
    * - `owner` cannot be the zero address.
    * - `spender` cannot be the zero address.
    */
    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "BEP20: approve from the zero address");
        require(spender != address(0), "BEP20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function checkSwapFrequency(address whom) internal{
        uint currentTime = getCurrentTime();
        if (antiBot) {
            uint lastSwapTime = _addressToLastSwapTime[whom];
            require(currentTime - lastSwapTime >= lockedBetweenSells, "Lock time has not been released from last swap"
            );
        }
        _addressToLastSwapTime[whom] = currentTime;
    }

    function getCurrentTime() internal virtual view returns(uint){
        return block.timestamp;
    }

    event UpdatePancakeRouter(IUniswapV2Router02 router, address pair);
    event UpdateDevWallet(address current, address previous);
    event UpdateMarketingWallet(address current, address previous);
    event UpdateCharityWallet(address current, address previous);

    event PrivilegedWallet(address _privilegedAddress, bool isPrivileged);

    event UpdateLpFeePercent(uint8 current, uint8 previous);
    event UpdateDevFeePercent(uint8 current, uint8 previous);
    event UpdateMarketingFeePercent(uint8 current, uint8 previous);
    event UpdateCharityFeePercent(uint8 current, uint8 previous);

    event UpdateSellingFee(bool isEnabled);
    event UpdateBuyingFee(bool isEnabled);

    event UpdateLockedBetweenBuys(uint256 cooldown, uint256 previous);
    event UpdateLockedBetweenSells(uint256 cooldown, uint256 previous);

    event UpdateAntibot(bool isEnabled);

    event UpdateMaxTxAmount(uint256 maxTxAmount, uint256 prevTxAmount);

    event UpdateTokenPerBNB(uint256 tokenPerBNB);
    event UpdateSwapAndLiquify(bool swapAndLiquifyEnabled);
    event UpdateSwapTolerancePercent(uint8 swapTolerancePercent, uint8 swapTolerancePercentPrev);
    event UpdateMinTokenToSwapAndLiquify(uint256 numTokensSellToAddToLiquidity, uint256 numTokensSellToAddToLiquidityPrev);
    event LiquidityAdded(uint256 tokenAmount, uint256 bnbAmount);
    event SwapAndLiquifyStatus(string status);
}
