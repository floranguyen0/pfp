// SPDX-License-Identifier: GPL-2.0
pragma solidity >=0.8.15;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import "./utils/SigUtils.sol";
import "../src/PFP.sol";
import "../lib/murky.git/src/Merkle.sol";
import "../src/interfaces/IERC4494.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract PFPTest is Test {
    PFP public pfp;
    SigUtils public sigUtils;
    address address1 = vm.addr(1);
    address address2 = vm.addr(2);
    address address3 = vm.addr(3);
    address address29 = vm.addr(30);
    bytes32[] whitelistedAddressHashes;

    event Mint(address indexed to, uint256 indexed quantity);
    event PresaleMint(address indexed to, uint256 indexed quantity);
    event FreeMint(address indexed to, uint256 indexed quantity);
    event FounderMint(address indexed to, uint256 indexed quantity);
    event ExecTransaction(
        address indexed target,
        bytes indexed data,
        uint256 indexed weiAmount
    );
    event FlagSwitched(bool indexed isActive);
    event PreRevealURIUpdated(string indexed preURI, string indexed uri);
    event BaseURIUpdated(string indexed preURI, string indexed uri);
    event PresaleMerkleRootUpdated(bytes32 indexed root);
    event PublicPriceUpdated(uint256 indexed prePrice, uint256 indexed price);
    event PresalePriceUpdated(uint256 indexed prePrice, uint256 indexed price);
    event PublicMaxPerAddressUpdated(
        uint32 indexed preQuantity,
        uint32 indexed quantity
    );
    event PresaleMaxPerAddressUpdated(
        uint32 indexed preQuantity,
        uint32 indexed quantity
    );
    event FreeMintMaxPerAddressUpdated(
        uint32 indexed preQuantity,
        uint32 indexed quantity
    );
    event PresaleSupplyUpdated(
        uint32 indexed preQuantity,
        uint32 indexed quantity
    );
    event FreeMintSupplyUpdated(
        uint32 indexed preQuantity,
        uint32 indexed quantity
    );
    event RevealNumberUpdated(
        uint256 indexed preAmount,
        uint256 indexed amount
    );

    function setUp() public {
        pfp = new PFP("NFTName", "NFTN", "1.0", 10_000);
        sigUtils = new SigUtils(pfp.DOMAIN_SEPARATOR(), address(pfp));

        pfp.switchPublicFlag();
        // price is 0.001 eth
        pfp.setPublicPrice(10**15);
        pfp.setPublicMaxPerAddress(200);

        vm.stopPrank();
    }

    function testMint(uint256 amount) public {
        amount = bound(amount, 1, 200);
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

        _presaleSetup();
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
        _presaleSetup();
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

        _freeMintSetUp();
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
        _freeMintSetUp();
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

    function testSetRevealNumber() public {}

    function testSetPublicPrice() public {
        vm.expectEmit(true, true, false, true);
        emit PublicPriceUpdated(10**15, 10**18);
        pfp.setPublicPrice(10**18);
        assertEq(pfp.publicPrice(), 10**18);
    }

    function testSetPresalePrice() public {
        vm.expectEmit(true, true, false, true);
        emit PresalePriceUpdated(0, 10**17);
        pfp.setPresalePrice(10**17);
        assertEq(pfp.presalePrice(), 10**17);
    }

    function testSetPublicMaxPerAddress() public {
        vm.expectEmit(true, true, false, true);
        emit PublicMaxPerAddressUpdated(200, 300);
        pfp.setPublicMaxPerAddress(300);
        assertEq(pfp.publicMaxPerAddress(), 300);
    }

    function testSetPresaleMaxPerAddress() public {
        vm.expectEmit(true, true, false, true);
        emit PresaleMaxPerAddressUpdated(0, 200);
        pfp.setPresaleMaxPerAddress(200);
        assertEq(pfp.presaleMaxPerAddress(), 200);
    }

    function testSetFreeMintMaxPerAddress() public {
        vm.expectEmit(true, true, false, true);
        emit FreeMintMaxPerAddressUpdated(0, 50);
        pfp.setFreeMintMaxPerAddress(50);
        assertEq(pfp.freeMintMaxPerAddress(), 50);
    }

    function testSetPresaleSupply() public {
        vm.expectEmit(true, true, false, true);
        emit PresaleSupplyUpdated(0, 1000);
        pfp.setPresaleSupply(1000);
        assertEq(pfp.presaleSupply(), 1000);
    }

    function testSetFreeMintSupply() public {
        vm.expectEmit(true, true, false, true);
        emit FreeMintSupplyUpdated(0, 500);
        pfp.setFreeMintSupply(500);
        assertEq(pfp.freeMintSupply(), 500);
    }

    function testSwitchPublicFlag() public {
        assertEq(pfp.publicFlag(), true);
        vm.expectEmit(true, false, false, false);
        emit FlagSwitched(false);
        pfp.switchPublicFlag();
        assertEq(pfp.publicFlag(), false);
    }

    function testSwitchPresaleFlag() public {
        assertEq(pfp.presaleFlag(), false);
        vm.expectEmit(true, false, false, false);
        emit FlagSwitched(true);
        pfp.switchPresaleFlag();
        assertEq(pfp.presaleFlag(), true);
    }

    function testSwitchFreemintFlag() public {
        assertEq(pfp.freeMintFlag(), false);
        vm.expectEmit(true, false, false, false);
        emit FlagSwitched(true);
        pfp.switchFreemintFlag();
        assertEq(pfp.freeMintFlag(), true);
    }

    function testTokenURI() public {
        string memory baseURI = "ipfs://ThisIsTheBaseURI/";
        string memory preRevealURI = "ipfs://PreRevealURI/";
        pfp.founderMint(address1, 1000);
        pfp.setRevealNumber(10);

        assertEq(pfp.tokenURI(20), "");

        pfp.setPreRevealURI(preRevealURI);
        assertEq(pfp.tokenURI(20), preRevealURI);

        assertEq(pfp.tokenURI(5), preRevealURI);

        pfp.setBaseURI(baseURI);
    }

    function testSupportInterface() public {
        assertEq(pfp.supportsInterface(type(IERC4494).interfaceId), true);
        assertEq(pfp.supportsInterface(type(IERC2981).interfaceId), true);
        assertEq(pfp.supportsInterface(type(IERC165).interfaceId), true);
        assertEq(pfp.supportsInterface(type(IERC721).interfaceId), true);
        assertEq(
            pfp.supportsInterface(type(IERC721Metadata).interfaceId),
            true
        );
        assertEq(pfp.supportsInterface(type(IERC721A).interfaceId), true);
    }

    function testSetDefaultRoyalty() public {
        (address receiver, uint256 royaltyAmount) = pfp.royaltyInfo(5, 300);
        assertEq(receiver, address(0));
        assertEq(royaltyAmount, 0);
        // 1% royalty
        pfp.setDefaultRoyalty(address2, 100);
        (address receiverA, uint256 royaltyAmountA) = pfp.royaltyInfo(5, 300);
        assertEq(receiverA, address2);
        assertEq(royaltyAmountA, 3);
    }

    function testDeleteDefaultRoyalty() public {
        pfp.setDefaultRoyalty(address2, 100);
        pfp.deleteDefaultRoyalty();

        (address receiver, uint256 royaltyAmount) = pfp.royaltyInfo(1, 100);
        assertEq(receiver, address(0));
        assertEq(royaltyAmount, 0);
    }

    function testSetTokenRoyalty() public {
        // 1% royalty
        pfp.setDefaultRoyalty(address2, 100);
        // 10% royalty
        pfp.setTokenRoyalty(10, address1, 1000);

        (address receiver, uint256 royaltyAmount) = pfp.royaltyInfo(5, 500);
        assertEq(receiver, address2);
        assertEq(royaltyAmount, 5);

        (address receiverA, uint256 royaltyAmountA) = pfp.royaltyInfo(10, 300);
        assertEq(receiverA, address1);
        assertEq(royaltyAmountA, 30);
    }

    function testResetTokenRoyalty() public {
        pfp.setTokenRoyalty(10, address1, 1000);
        (address receiver, uint256 royaltyAmount) = pfp.royaltyInfo(10, 500);
        assertEq(receiver, address1);
        assertEq(royaltyAmount, 50);

        pfp.resetTokenRoyalty(10);
        (address receiverA, uint256 royaltyAmountA) = pfp.royaltyInfo(10, 200);
        assertEq(receiverA, address(0));
        assertEq(royaltyAmountA, 0);
    }

    function _presaleSetup() private {
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

    function _freeMintSetUp() private {
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

    function testTransferWithPermit() public {
        vm.deal(address1, 100 ether);
        vm.prank(address1);

        pfp.mint{value: 1 ether}(address2, 100);

        SigUtils.Permit memory permit = SigUtils.Permit({
            spender: address3,
            tokenId: 10,
            nonce: pfp.nonces(10),
            deadline: 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(2, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(address2);
        pfp.transferWithPermit(address2, address3, 10, 1 days, signature);

        assertEq(pfp.balanceOf(address2), 99);
        assertEq(pfp.balanceOf(address3), 1);
        assertEq(pfp.ownerOf(10), address3);
        assertEq(pfp.totalSupply(), 100);
    }

    function testCannotTransferWithPermit() public {
        vm.deal(address1, 100 ether);
        vm.prank(address1);

        pfp.mint{value: 1 ether}(address2, 100);

        SigUtils.Permit memory permit = SigUtils.Permit({
            spender: address3,
            tokenId: 10,
            nonce: pfp.nonces(10),
            deadline: 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(2, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert("ERC721Permit: Approval to current owner");
        pfp.transferWithPermit(address2, address2, 10, 1 days, signature);

        // wrong tokenId
        vm.expectRevert("ERC721Permit: Unauthorized");
        pfp.transferWithPermit(address2, address3, 20, 1 days, signature);

        // wrong dealine
        vm.expectRevert("ERC721Permit: Unauthorized");
        pfp.transferWithPermit(address2, address3, 10, 2 days, signature);

        // wrong token owner
        vm.expectRevert("ERC721Permit: Unauthorized");
        pfp.transferWithPermit(address1, address3, 10, 2 days, signature);

        skip(2 days);
        vm.startPrank(address2);
        vm.expectRevert("Permit has expired");
        pfp.transferWithPermit(address2, address3, 10, 1 days, signature);
    }
}
