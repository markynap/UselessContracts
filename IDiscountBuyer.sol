//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

/**
 * Discount Buyer Interface
 */
interface IDiscountBuyer {
    function setReceiveForUser(address receiver) external;
}
