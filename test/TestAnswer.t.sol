// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "src/AVT.sol";
import "src/GAVT.sol";
import "src/interfaces/IWETH.sol";
import "src/interfaces/IV3Aggregator.sol";


// V3 Aggregator = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419 (Ethereum - ETH/USD)
// V3 Aggregator = 0x986b5E1e1755e3C2440e960477f25201B0a8bbD4 (Ethereum - USD/ETH)
contract Tests is Test {

    address admin = vm.addr(1);
    address alice = vm.addr(2);
    address bob = vm.addr(3);

    address exploiter = vm.addr(4);


    AVT avt;
    GAVT gavt;

    IWETH weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address priceFeed = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;


    function setUp() public {
        // Setup Scenario
        uint256 forkId = vm.createFork("[YOUR-API-KEY]");
        vm.selectFork(forkId);
        vm.rollFork(19687339);

        deal(address(weth), alice, 10 ether);
        deal(address(weth), bob, 10 ether);
        deal(address(weth), exploiter, 10 ether);


        vm.startPrank(admin);
        gavt = new GAVT(1_000_000 ether);
        avt = new AVT(address(weth), address(gavt), priceFeed);
        gavt.transfer(address(avt), 1_000_000 ether);
        vm.stopPrank();


        vm.startPrank(alice);
        weth.approve(address(avt), type(uint256).max);
        avt.deposit(10 ether, alice);
        vm.stopPrank();


        vm.startPrank(bob);
        weth.approve(address(avt), type(uint256).max);
        avt.deposit(10 ether, bob);
        vm.stopPrank();

    }


    function testAnswer() public {

        /*
        *
        * === YOUR EXPLOIT CODE HERE ===
        *
        */



       // ==== DO NOT CHANGE ====

        vm.prank(alice);
        avt.claimRewards();

        vm.prank(bob);
        avt.claimRewards();

        uint256 aliceRewards = gavt.balanceOf(alice);
        uint256 bobRewards = gavt.balanceOf(bob);
        uint256 exploiterRewards = gavt.balanceOf(exploiter);
        assertGt(exploiterRewards, aliceRewards);
        assertGt(exploiterRewards, bobRewards);


    }


}


