// SPDX-License-Identifier: GPL-2.0
pragma solidity >=0.8.15;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import "../src/PFP.sol";
import "../lib/murky.git/src/Merkle.sol";

contract PFPTest is Test {
    PFP public pfp;
    address owner = vm.addr(1);
    address address1 = vm.addr(2);
    address address2 = vm.addr(3);
    address address29 = vm.addr(30);
    bytes32[] whitelistedAddressHashes;

    event FlagSwitched(bool indexed isActive);
    event RoyaltyRateUpdated(uint32 indexed amount);
    event PreRevealURIUpdated(string indexed uri);
    event BaseURIUpdated(string indexed uri);
    event PresaleMerkleRootUpdated(bytes32 indexed root);
    event PublicPriceUpdated(uint256 indexed price);
    event PresalePriceUpdated(uint256 indexed price);
    event MaxPerAddressUpdated(uint32 indexed quantity);
    event PresaleSupplyUpdated(uint32 indexed quantity);
    event FreeMintSupplyUpdated(uint32 indexed quantity);
    event RevealNumberUpdated(uint256 indexed amount);

    error WithdrawEthFailed();

    function setUp() public {
        pfp = new PFP("NFTName", "NFTN", "1.0", 10_000, owner);
        vm.startPrank(owner);

        pfp.switchPublicFlag();
        // price is 0.001 eth
        pfp.setPublicPrice(10**15);
        pfp.setPublicMaxPerAddress(100);

        vm.stopPrank();
    }

    function testMint(uint256 amount) public {
        amount = bound(amount, 1, 100);
        vm.deal(address1, 100 ether);
        vm.prank(address1);
        pfp.mint{value: 1 ether}(address1, amount);

        assertEq(pfp.publicMinted(address1), amount);
        assertEq(pfp.balanceOf(address1), amount);
        assertEq(pfp.totalSupply(), amount);
    }

    function testCannotMint() public {
        vm.prank(owner);
        pfp.switchPublicFlag();
        vm.prank(address1);
        vm.expectRevert("Public sale is not active");
        pfp.mint(address1, 20);

        vm.prank(owner);
        pfp.switchPublicFlag();
        vm.prank(address1);
        vm.expectRevert("Mint: Insufficient ETH");
        pfp.mint(address1, 15);

        vm.prank(address1);
        vm.deal(address1, 10 ether);
        vm.expectRevert("Mint: Amount exceeds max per address");
        pfp.mint{value: 1 ether}(address1, 200);
    }

    function testPresaleMint(uint256 amount) public {
        amount = bound(amount, 1, 100);
        Merkle merkle = new Merkle();
        vm.prank(owner);
        pfp.switchPresaleFlag();

        _setPresaleMerkleRoot();
        // get proof for address2
        bytes32[] memory proof = merkle.getProof(whitelistedAddressHashes, 2);

        vm.prank(address2);
        vm.deal(address2, 100 ether);
        pfp.presaleMint{value: 1 ether}(address2, amount, proof);
        assertEq(pfp.presaleMinted(address2), amount);
        assertEq(pfp.balanceOf(address2), amount);
        assertEq(pfp.totalSupply(), amount);
    }

    function testCannotPresaleMint() public {
        Merkle merkle = new Merkle();
        _setPresaleMerkleRoot();
        // get proof for address2
        bytes32[] memory proof = merkle.getProof(whitelistedAddressHashes, 2);
        vm.deal(address2, 100 ether);

        vm.expectRevert("Presale mint is not active");
        pfp.presaleMint(address2, 10, proof);

        vm.prank(owner);
        pfp.switchPresaleFlag();
        vm.expectRevert("Presale mint: Insufficient ETH");
        pfp.presaleMint{value: 100}(address2, 40, proof);

        vm.expectRevert("Insufficient presale token supply");
        pfp.presaleMint{value: 10 ether}(address1, 1100, proof);

        vm.deal(vm.addr(40), 10 ether);
        vm.prank(vm.addr(40));
        vm.expectRevert("Invalid merkle proof");
        pfp.presaleMint{value: 1 ether}(vm.addr(40), 10, proof);

        vm.expectRevert("Presale mint: Amount exceeds max per address");
        vm.prank(address2);
        pfp.presaleMint{value: 10 ether}(address1, 150, proof);
    }

    function testFreeMint(uint256 amount) public {
        amount = bound(amount, 1, 50);
        Merkle merkle = new Merkle();
        vm.prank(owner);
        pfp.switchFreemintFlag();

        _setFreeMintMerkleRoot();
        // get proof for address29
        bytes32[] memory proof = merkle.getProof(whitelistedAddressHashes, 0);

        vm.prank(address29);
        pfp.freeMint(address29, amount, proof);
        assertEq(pfp.freeMintMinted(address29), amount);
        assertEq(pfp.balanceOf(address29), amount);
        assertEq(pfp.totalSupply(), amount);
    }

    function testCannotFreeMint() public {
        Merkle merkle = new Merkle();
        _setFreeMintMerkleRoot();
        // get proof for address29
        bytes32[] memory proof = merkle.getProof(whitelistedAddressHashes, 0);

        vm.expectRevert("Free mint is not active");
        pfp.freeMint(address29, 10, proof);

        vm.prank(owner);
        pfp.switchFreemintFlag();
        vm.expectRevert("Insufficient free-mint token supply");
        pfp.freeMint(address1, 600, proof);

        vm.expectRevert("Invalid merkle proof");
        pfp.freeMint(vm.addr(40), 10, proof);

        vm.expectRevert("Free mint: Amount exceeds max per address");
        vm.prank(address29);
        pfp.freeMint(address29, 51, proof);
    }

    function testFounderMint() public {
        vm.startPrank(owner);
        pfp.founderMint(address1, 50);
        pfp.founderMint(address2, 2000);
        pfp.founderMint(owner, 3000);
        vm.stopPrank();
    }

    function testCannotFounderMint() public {
        vm.prank(owner);
        vm.expectRevert("Insufficient token supply");
        pfp.founderMint(owner, 20_000);

        vm.expectRevert("Ownable: caller is not the owner");
        pfp.founderMint(owner, 100);
    }

    function _setPresaleMerkleRoot() private {
        Merkle merkle = new Merkle();
        // generate whitelisted address hashes
        for (uint256 i = 1; i < 30; i++) {
            whitelistedAddressHashes.push(
                keccak256(abi.encodePacked(vm.addr(i)))
            );
        }
        bytes32 root = merkle.getRoot(whitelistedAddressHashes);
        vm.startPrank(owner);
        // price is 0.0001 eth
        pfp.setPresalePrice(10**14);
        pfp.setPresaleMerkleRoot(root);
        pfp.setPresaleSupply(1000);
        pfp.setPresaleMaxPerAddress(100);
        vm.stopPrank();
    }

    function _setFreeMintMerkleRoot() private {
        Merkle merkle = new Merkle();
        // generate whitelisted address hashes
        for (uint256 i = 30; i < 60; i++) {
            whitelistedAddressHashes.push(
                keccak256(abi.encodePacked(vm.addr(i)))
            );
        }
        bytes32 root = merkle.getRoot(whitelistedAddressHashes);
        vm.startPrank(owner);
        pfp.setFreeMintMerkleRoot(root);
        pfp.setFreeMintSupply(500);
        pfp.setFreeMintMaxPerAddress(50);
        vm.stopPrank();
    }
}
