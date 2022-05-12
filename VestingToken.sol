// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "https://github.com/sadiq1971/sol-contracts/blob/main/lib/Ownable.sol";

contract Vesting is Ownable {
    struct VestingSchedule{
        // to of tokens after they are released
        address  to;
        // start time of the vesting period
        uint256  start;
        // end time of the vesting period in seconds
        uint256  end;
        // total amount of tokens to be released at the end of the vesting
        uint256 amountTotal;
        // amount of tokens released
        bool  released;
    }
    mapping(bytes32 => VestingSchedule) private vestingSchedules;
    mapping(address => uint256) private holdersVestingCount;

    /**
    * @notice Creates a new vesting schedule for a address.
    * @param _to address of the beneficiary to whom vested tokens are transferred
    * @param _start start time of the vesting period
    * @param _end duration in seconds of the cliff in which tokens will begin to vest
    * @param _amount total amount of tokens to be released at the end of the vesting
    */
    function createVestingSchedule(
        address _to,
        uint256 _start,
        uint256 _end,
        uint256 _amount
    ) internal {
        require(_amount > 0, "TokenVesting: amount must be > 0");

        bytes32 vestingScheduleId = computeNextVestingScheduleIdForHolder(_to);
        vestingSchedules[vestingScheduleId] = VestingSchedule(
            _to,
            _start,
            _end,
            _amount,
            false
        );
        uint256 currentVestingCount = holdersVestingCount[_to];
        holdersVestingCount[_to] = currentVestingCount + 1;
    }

    /**
    * @notice Returns the total amount withdrawble from vesting schedules.
    * @param account for which the amount will be calculated
    * @return the total amount of vesting schedules
    */
    function getWithdrawbleAmount(address account)
    external
    view
    returns(uint256){
        uint256 currentTime = getCurrentTime();
        uint256 amountUnlocked = 0;
        uint256 totalVestingShedules = getVestingSchedulesCount(account);
        for (uint256 i = 0 ; i < totalVestingShedules; i++) {
            VestingSchedule storage vestingSchedule = vestingSchedules[computeVestingScheduleIdForAddressAndIndex(account, i)];
            if (vestingSchedule.released) {
                if (vestingSchedule.end <= currentTime) {
                    amountUnlocked += vestingSchedule.amountTotal;
                }
            }
        }

        return amountUnlocked;
    }

    /**
    * @notice claim transfer the withdrawble amount to the buyers address
    */
    function claim(address account) internal returns (uint256) {
        uint256 currentTime = getCurrentTime();
        uint256 amountUnlocked = 0;
        uint256 totalVestingShedules = getVestingSchedulesCount(account);
        for (uint256 i = 0 ; i < totalVestingShedules; i++) {
            bytes32 vid = computeVestingScheduleIdForAddressAndIndex(account, i);
            VestingSchedule storage vestingSchedule = vestingSchedules[vid];
            if (!vestingSchedule.released) {
                if (vestingSchedule.end <= currentTime) {
                    amountUnlocked += vestingSchedule.amountTotal;
                    vestingSchedules[vid].released = true;
                }
            }
        }
        return amountUnlocked;
    }

    /**
    * @dev Returns the number of vesting schedules associated to a account
    * @return the number of vesting schedules
    */
    function getVestingSchedulesCount(address account)
    public
    view
    returns(uint256){
        return holdersVestingCount[account];
    }

    /**
    * @notice Returns the vesting schedule information for a given holder and index.
    * @return the vesting schedule structure information
    */
    function getVestingScheduleByAddressAndIndex(address holder, uint256 index)
    external
    view
    returns(VestingSchedule memory){
        return getVestingSchedule(computeVestingScheduleIdForAddressAndIndex(holder, index));
    }

    /**
    * @notice Returns the vesting schedule information for a given identifier.
    * @return the vesting schedule structure information
    */
    function getVestingSchedule(bytes32 vestingScheduleId)
    internal
    view
    returns(VestingSchedule memory){
        return vestingSchedules[vestingScheduleId];
    }

    /**
   * @dev Computes the next vesting schedule identifier for a given holder address.
    */
    function computeNextVestingScheduleIdForHolder(address holder)
    internal
    view
    returns(bytes32){
        return computeVestingScheduleIdForAddressAndIndex(holder, holdersVestingCount[holder]);
    }


    /**
    * @dev Computes the vesting schedule identifier for an address and an index.
    */
    function computeVestingScheduleIdForAddressAndIndex(address holder, uint256 index)
    internal
    pure
    returns(bytes32){
        return keccak256(abi.encodePacked(holder, index));
    }

    function getCurrentTime()
    internal
    virtual
    view
    returns(uint256){
        return block.timestamp;
    }
}