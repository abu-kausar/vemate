// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./VemateToken.sol";
import "./VestingToken.sol";
import "https://github.com/sadiq1971/sol-contracts/blob/main/lib/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PrivateSale is Ownable, Vesting{
    Vemate immutable private vemate;
    IERC20 immutable private erc20;

    uint8 private _decimals = 18;
    uint8 public interestPercentageForDeposit = 27;

    bool public isInPrivateSale;
    bool public isPrivateSaleDone;
    bool public isPrivateSalePaused;

    uint256 private constant DAY = 24 * 60 * 60;
    uint256 private constant MONTH = DAY * 30;

    uint256 public totalSoldToken;
    uint256 public minimumPrivateSaleToken;
    uint256 public maximumPrivateSaleToken;
    uint256 public totalAmountInVesting;

    uint256 public initialTokenUnlockTime;

    uint256 public vematePerBUSD = 60;

    constructor(address payable vemateToken, address erc20Token){
        require(vemateToken != address(0x0));
        require(erc20Token != address(0x0));
        require(owner() != address(0), "Owner must be set");

        vemate = Vemate(vemateToken);
        erc20 = IERC20(erc20Token);

        isInPrivateSale = false;
        isPrivateSaleDone = false;
        isPrivateSalePaused = true;
    }

    function startPrivateSale(uint256 minTokenPerSale, uint256 maxTokenPerSale, uint256 initialTokenUnlkTime, uint8 _interestPercentageForDeposit) external onlyOwner {
        require(!isPrivateSaleDone, "PrivateSale finished");
        require(!isInPrivateSale, "Already In PrivateSale");

        isInPrivateSale = true;
        isPrivateSalePaused = false;

        minimumPrivateSaleToken = minTokenPerSale;
        maximumPrivateSaleToken = maxTokenPerSale;

        initialTokenUnlockTime = initialTokenUnlkTime;

        interestPercentageForDeposit = _interestPercentageForDeposit;
    }

    function stopPrivateSale() external onlyOwner {
        require(isInPrivateSale, "PrivateSale not started");

        isInPrivateSale = false;
        isPrivateSaleDone = true;
    }

    function togglePausePrivateSale() external onlyOwner {
        require(isInPrivateSale, "Not in a PrivateSale");
        isPrivateSalePaused = !isPrivateSalePaused;
    }

    /**
    * @notice setListingTime is to update the initial unlocking time
    * @param _setListingTime time what owner want to set
    */
    function setListingTime(uint256 _setListingTime) external onlyOwner {
        require(isInPrivateSale, "PrivateSale not started");
        initialTokenUnlockTime = _setListingTime;
    }

    function updateVematePrice(uint256 _vematePerBUSD) external onlyOwner{
        vematePerBUSD = _vematePerBUSD;
    }

    /**
    * @notice buyTokenForVesting is to buy token. token won't be sent to buyers wallet immediately, rather it will be unlock gradually and buyers need to claim it.
    * @param tokenAmount amount of token to be sold
    */
    function buyTokenForVesting(uint256 tokenAmount) external{
        address to = _msgSender();
        require(to != address(0), "Not a valid address");
        require(isInPrivateSale, "Not in a PrivateSale");
        require(!isPrivateSalePaused, "PrivateSale is Paused");
        require(tokenAmount >= minimumPrivateSaleToken, "Token is less than minimum");
        require(tokenAmount <= maximumPrivateSaleToken, "Token is greater than maximum");
        require(getAmountLeftForPrivateSale()>= tokenAmount, "Not enough amount left for sell");

        // check balance of the buyer
        uint256 priceInBUSD = tokenAmount/vematePerBUSD;
        require(erc20.balanceOf(to) >= priceInBUSD, "Not enough busd token on balance");

        uint256 time = getCurrentTime();
        //unlock 15% on initialTokenUnlockTime
        createVestingSchedule(to, time, initialTokenUnlockTime, (tokenAmount*15)/100);

        for (uint8 i = 1; i < 7; i++){
            // unlock 12.5% on each month
            createVestingSchedule(to, time, initialTokenUnlockTime + (MONTH*i), (tokenAmount*125)/1000);
        }
        // unlock last 10% on 8th month after initialTokenUnlockTime
        createVestingSchedule(to, time, initialTokenUnlockTime + (MONTH*7), (tokenAmount*10)/100);

        totalAmountInVesting += tokenAmount;
        totalSoldToken += tokenAmount;
        erc20.transferFrom(to, address(this), priceInBUSD);
    }  

    /**
    * @notice sellTokenForVesting is to buy token. token won't be sent to buyers wallet immediately, rather it will be unlock gradually and buyers need to claim it.
    * @param tokenAmount amount of token to be sold
    * @param receiver address of the token receiver
    */
    function sellTokenForVesting(uint256 tokenAmount, address receiver) external onlyOwner{
        address to = receiver;
        require(to != address(0), "Not a valid address");
        require(isInPrivateSale, "Not in a PrivateSale");
        require(!isPrivateSalePaused, "PrivateSale is Paused");
        require(tokenAmount >= minimumPrivateSaleToken, "Token is less than minimum");
        require(tokenAmount <= maximumPrivateSaleToken, "Token is greater than maximum");
        require(getAmountLeftForPrivateSale()>= tokenAmount, "Not enough amount left for sell");

        uint256 time = getCurrentTime();
         
        //unlock 15% on initialTokenUnlockTime
        createVestingSchedule(to, time, initialTokenUnlockTime, (tokenAmount*15)/100);

        for (uint8 i = 1; i < 7; i++){
            // unlock 12.5% on each month
            createVestingSchedule(to, time, initialTokenUnlockTime + (MONTH*i), (tokenAmount*125)/1000);
        }
        // unlock last 10% on 8th month after initialTokenUnlockTime
        createVestingSchedule(to, time, initialTokenUnlockTime + (MONTH*7), (tokenAmount*10)/100);

        totalAmountInVesting += tokenAmount;
        totalSoldToken += tokenAmount;
    }

    /**
    * @notice buyTokenForDeposit sells token to the buyers. buyers will be able to claim token with interest after deposit period.
    * @param tokenAmount amount of token to be sold
    */
    function buyTokenForDeposit(uint256 tokenAmount) external{
        address to = _msgSender();
        require(to != address(0), "Not a valid address");
        require(isInPrivateSale, "Not in a PrivateSale");
        require(!isPrivateSalePaused, "PrivateSale is Paused");
        require(tokenAmount >= minimumPrivateSaleToken, "Token is less than minimum");
        require(tokenAmount <= maximumPrivateSaleToken, "Token is greater than maximum");
        require(getAmountLeftForPrivateSale()>= tokenAmount, "Not enough amount left for sell");

        // check balance of the buyer
        uint256 priceInBUSD = tokenAmount/vematePerBUSD;
        require(erc20.balanceOf(to) >= priceInBUSD, "Not enough busd token on balance");

        uint256 interest = (tokenAmount*interestPercentageForDeposit)/100;
        uint256 totalToken = tokenAmount += interest;

        require(getAmountLeftForPrivateSale()>= totalToken, "Not enough amount left for sell");

        totalSoldToken+= totalToken;
        uint256 time = getCurrentTime();
        createVestingSchedule(to, time, time + (MONTH*12), totalToken);
        totalAmountInVesting += tokenAmount;
        erc20.transferFrom(to, address(this), priceInBUSD);
    }

    /**
    * @notice sellTokenForDeposit sells token to the buyers. buyers will be able to claim token with interest after deposit period.
    * @param tokenAmount amount of token to be sold
    * @param receiver address of the token receiver
    */
    function sellTokenForDeposit(uint256 tokenAmount, address receiver) external onlyOwner{
        address to = receiver;
        require(to != address(0), "Not a valid address");
        require(isInPrivateSale, "Not in a PrivateSale");
        require(!isPrivateSalePaused, "PrivateSale is Paused");
        require(tokenAmount >= minimumPrivateSaleToken, "Token is less than minimum");
        require(tokenAmount <= maximumPrivateSaleToken, "Token is greater than maximum");
        require(getAmountLeftForPrivateSale()>= tokenAmount, "Not enough amount left for sell");

        uint256 interest = (tokenAmount*interestPercentageForDeposit)/100;
        uint256 totalToken = tokenAmount += interest;

        require(getAmountLeftForPrivateSale()>= totalToken, "Not enough amount left for sell");

        totalSoldToken+= totalToken;
        uint256 time = getCurrentTime();
        createVestingSchedule(to, time, time + (MONTH*12), totalToken);
        totalAmountInVesting += tokenAmount;
    }

    /**
     * @notice sendTokensToMarketingWallet sends token to marketing wallet. 15% of token will be sent to marketing wallet immediately, 
       rest won't be sent immediately rather it will be unlocked gradually and that wallet need to claim it.
     * @param tokenAmount amount of token to be sent to Team wallet
     * @param receiver address of the token receiver
     */
    function sendTokensToMarketingWallet(uint256 tokenAmount, address receiver) external onlyOwner{
        address to = receiver;
        require(to != address(0), "Not a valid address");
        require(isInPrivateSale, "Not in a PrivateSale");
        require(!isPrivateSalePaused, "PrivateSale is Paused");
        require(getAmountLeftForPrivateSale()>= tokenAmount, "Not enough amount left for sell");

        uint256 time = getCurrentTime();
         
        //unlock 15% on initialTokenUnlockTime
        createVestingSchedule(to, time, initialTokenUnlockTime, (tokenAmount*15)/100);

        for (uint8 i = 1; i < 12; i++){
            // unlock 7% on each month
            createVestingSchedule(to, time, initialTokenUnlockTime + (MONTH*i), (tokenAmount*7)/100);
        }
        // unlock last 8% on 12th month after initialTokenUnlockTime
        createVestingSchedule(to, time, initialTokenUnlockTime + (MONTH*12), (tokenAmount*8)/100);

        totalAmountInVesting += tokenAmount;
        totalSoldToken += tokenAmount;
    }

    /**
     * @notice sendTokensToTeamWallet sends token to Team wallet. token won't be sent immediately rather it will be unlocked after 
       12 months and that wallet need to claim it.
     * @param tokenAmount amount of token to be sent to Team wallet
     * @param receiver address of the token receiver
     */
    function sendTokensToTeamWallet(uint256 tokenAmount, address receiver) external onlyOwner{
        address to = receiver;
        require(to != address(0), "Zero Address!");
        require(isInPrivateSale, "Not in PrivateSale");
        require(!isPrivateSalePaused, "PrivateSale is paused");
        require(getAmountLeftForPrivateSale() >= tokenAmount, "Not enough amount left for send");

        totalSoldToken += tokenAmount;
        uint256 time = getCurrentTime();
        createVestingSchedule(to, time, time + (MONTH*12), tokenAmount);
        totalAmountInVesting += tokenAmount;
    }

    /**
     * @notice sendTokensToReserveWallet sends token to some special wallet. 20% of token will be sent to reserve wallet immediately, 
       rest won't be sent immediately rather it will be unlocked gradually and that wallet need to claim it.
     * @param tokenAmount amount of token to be sent to Team wallet
     * @param receiver address of the token receiver
     */
    function sendTokensToReserveWallet(uint256 tokenAmount, address receiver) external onlyOwner{
        address to = receiver;
        require(to != address(0), "Not a valid address");
        require(isInPrivateSale, "Not in a PrivateSale");
        require(!isPrivateSalePaused, "PrivateSale is Paused");
        require(getAmountLeftForPrivateSale()>= tokenAmount, "Not enough amount left for sell");

        uint256 time = getCurrentTime();
         
        //unlock 20% on initialTokenUnlockTime
        createVestingSchedule(to, time, initialTokenUnlockTime, (tokenAmount*20)/100);

        for (uint8 i = 1; i < 11; i++){
            // unlock 7% on each month
            createVestingSchedule(to, time, initialTokenUnlockTime + (MONTH*i), (tokenAmount*7)/100);
        }
        // unlock last 10% on 11th month after initialTokenUnlockTime
        createVestingSchedule(to, time, initialTokenUnlockTime + (MONTH*11), (tokenAmount*10)/100);

        totalAmountInVesting += tokenAmount;
        totalSoldToken += tokenAmount;
    }

    function balanceBUSD() external view onlyOwner returns(uint256){
        return erc20.balanceOf(address(this));
    }

    function withdrawBUSD(uint256 amount, address where) external onlyOwner{
        require(where != address(0), "cannot withdraw to a zero address");
        require(erc20.balanceOf(address(this)) >= amount, "not enough balance");
        erc20.transfer(where, amount);
    }

    function withdrawToken(uint256 amount, address where) external onlyOwner{
        require(where != address(0), "cannot withdraw to a zero address");
        require(vemate.balanceOf(address(this)) >= amount, "not enough balance");
        vemate.transfer(where, amount);
    }

    /**
    * @dev Returns the amount of tokens that can be withdrawn by the owner.
    * @return the amount of tokens
    */
    function getAmountLeftForPrivateSale() public view returns(uint256){
        return vemate.balanceOf(address(this)) - totalAmountInVesting;
    }

    /**
    * @dev Claim the withdrawable tokens
    */
    function claimWithdrawableAmount() external {
        uint256 amount = claim(_msgSender());
        vemate.transfer(_msgSender(), amount);
        totalAmountInVesting -= amount;
    }

    receive() external payable {}
}