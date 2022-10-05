// SPDX-License-Identifier: GPL-2.0
pragma solidity >=0.8.15;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import "../src/PFP.sol";
import "../lib/murky.git/src/Merkle.sol";

contract PFPTest is Test {
    PFP public pfp;
    address address1 = vm.addr(1);
    address address2 = vm.addr(2);
    address address3 = vm.addr(3);
    address address29 = vm.addr(30);
    bytes32[] whitelistedAddressHashes;

    event Mint(address indexed to, uint256 indexed quantity);
    event PresaleMint(address indexed to, uint256 indexed quantity);
    event FreeMint(address indexed to, uint256 indexed quantity);
    event FounderMint(address indexed to, uint256 indexed quantity);
    event ExecTransaction(address target, bytes data, uint256 weiAmount);
    event FlagSwitched(bool indexed isActive);
    event PreRevealURIUpdated(string indexed uri);
    event BaseURIUpdated(string indexed uri);
    event PresaleMerkleRootUpdated(bytes32 indexed root);
    event PublicPriceUpdated(uint256 indexed price);
    event PresalePriceUpdated(uint256 indexed price);
    event MaxPerAddressUpdated(uint32 indexed quantity);
    event PresaleSupplyUpdated(uint32 indexed quantity);
    event FreeMintSupplyUpdated(uint32 indexed quantity);
    event RevealNumberUpdated(uint256 indexed amount);

    function setUp() public {
        pfp = new PFP("NFTName", "NFTN", "1.0", 10_000);

        pfp.switchPublicFlag();
        // price is 0.001 eth
        pfp.setPublicPrice(10**15);
        pfp.setPublicMaxPerAddress(300);

        vm.stopPrank();
    }

    function testMint(uint256 amount) public {
        amount = bound(amount, 1, 300);
        vm.deal(address1, 100 ether);
        vm.prank(address1);

        vm.expectEmit(true, true, false, false);
        emit Mint(address2, amount);
        pfp.mint{value: 1 ether}(address2, amount);

        assertEq(address(pfp).balance, 10**15 * amount);
        assertEq(pfp.publicMinted(address1), amount);
        assertEq(pfp.balanceOf(address2), amount);
        assertEq(pfp.totalSupply(), amount);
    }

    function testCannotMint() public {
        vm.expectRevert("Insufficient token supply");
        pfp.mint(address1, 15_000);

        pfp.switchPublicFlag();
        vm.prank(address2);
        vm.expectRevert("Public sale is not active");
        pfp.mint(address2, 20);

        pfp.switchPublicFlag();
        vm.prank(address2);
        vm.expectRevert("Mint: Insufficient ETH");
        pfp.mint(address2, 15);

        vm.prank(address2);
        vm.deal(address2, 10 ether);
        vm.expectRevert("Mint: Amount exceeds max per address");
        pfp.mint{value: 1 ether}(address2, 500);
    }

    function testPresaleMint(uint256 amount) public {
        amount = bound(amount, 1, 100);
        Merkle merkle = new Merkle();
        pfp.switchPresaleFlag();

        _setPresaleMerkleRoot();
        // get proof for address3
        bytes32[] memory proof = merkle.getProof(whitelistedAddressHashes, 2);

        vm.prank(address3);
        vm.deal(address3, 100 ether);
        vm.expectEmit(true, true, false, false);
        emit PresaleMint(address3, amount);
        pfp.presaleMint{value: 1 ether}(address3, amount, proof);

        assertEq(address(pfp).balance, 10**14 * amount);
        assertEq(pfp.presaleMinted(address3), amount);
        assertEq(pfp.balanceOf(address3), amount);
        assertEq(pfp.totalSupply(), amount);
    }

    function testCannotPresaleMint() public {
        Merkle merkle = new Merkle();
        _setPresaleMerkleRoot();
        // get proof for address3
        bytes32[] memory proof = merkle.getProof(whitelistedAddressHashes, 2);
        vm.deal(address3, 100 ether);

        vm.expectRevert("Presale mint is not active");
        pfp.presaleMint(address3, 10, proof);

        pfp.switchPresaleFlag();
        vm.expectRevert("Presale mint: Insufficient ETH");
        pfp.presaleMint{value: 100}(address3, 40, proof);

        vm.expectRevert("Insufficient presale token supply");
        pfp.presaleMint{value: 10 ether}(address2, 1100, proof);

        vm.deal(vm.addr(40), 10 ether);
        vm.prank(vm.addr(40));
        vm.expectRevert("Invalid merkle proof");
        pfp.presaleMint{value: 1 ether}(vm.addr(40), 10, proof);

        vm.expectRevert("Presale mint: Amount exceeds max per address");
        vm.prank(address3);
        pfp.presaleMint{value: 10 ether}(address2, 150, proof);
    }

    function testFreeMint(uint256 amount) public {
        amount = bound(amount, 1, 50);
        Merkle merkle = new Merkle();
        pfp.switchFreemintFlag();

        _setFreeMintMerkleRoot();
        // get proof for address29
        bytes32[] memory proof = merkle.getProof(whitelistedAddressHashes, 0);

        vm.prank(address29);
        vm.expectEmit(true, true, false, false);
        emit FreeMint(address29, amount);
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

        pfp.switchFreemintFlag();
        vm.expectRevert("Insufficient free-mint token supply");
        pfp.freeMint(address2, 600, proof);

        vm.expectRevert("Invalid merkle proof");
        pfp.freeMint(vm.addr(40), 10, proof);

        vm.expectRevert("Free mint: Amount exceeds max per address");
        vm.prank(address29);
        pfp.freeMint(address29, 51, proof);
    }

    function testFounderMint(uint256 amount) public {
        amount = bound(amount, 1, 10_000);

        vm.expectEmit(true, true, false, false);
        emit FounderMint(address2, amount);
        pfp.founderMint(address2, amount);

        assertEq(pfp.balanceOf(address2), amount);
        assertEq(pfp.totalSupply(), amount);
    }

    function testExecTransaction() public {
        vm.deal(address(pfp), 200 ether);
        pfp.execTransaction(address1, new bytes(0), 100 ether);
        assertEq(address(pfp).balance, 100 ether);
        assertEq(address1.balance, 100 ether);

        pfp.execTransaction(address1, new bytes(0), address(pfp).balance);
        assertEq(address(pfp).balance, 0);
        assertEq(address1.balance, 200 ether);
    }

    function testCannotExecTransaction() public {
        vm.prank(address1);
        vm.expectRevert("Ownable: caller is not the owner");
        pfp.execTransaction(address(this), "", 1 ether);
    }

    function testCannotFounderMint() public {
        vm.expectRevert("Insufficient token supply");
        pfp.founderMint(address1, 20_000);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address1);
        pfp.founderMint(address1, 100);
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
        // price is 0.0001 eth
        pfp.setPresalePrice(10**14);
        pfp.setPresaleMerkleRoot(root);
        pfp.setPresaleSupply(1000);
        pfp.setPresaleMaxPerAddress(100);
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
        pfp.setFreeMintMerkleRoot(root);
        pfp.setFreeMintSupply(500);
        pfp.setFreeMintMaxPerAddress(50);
    }
}
