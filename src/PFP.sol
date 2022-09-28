// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "./interfaces/IERC4494.sol";
import "./ERC721A.sol";

contract PFP is ERC721A, IERC2981, IERC4494, ReentrancyGuard, Ownable {
    using Strings for uint256;

    // PUBLIC VARIABLES

    // PERMIT_TYPEHASH value is equal to
    // keccak256("Permit(address spender,uint256 tokenId,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH =
        0x49ecf333e5b8c95c40fdafc95c1ad136e8914a8fb55e9dc8bb01eaa83a2df9ad;
    bytes32 public constant SUFFIX = ".json";
    uint256 public constant SCALE = 1e5;
    uint256 public immutable MAX_SUPPLY;
    uint256 public publicPrice;
    uint256 public presalePrice;
    uint32 public publicMaxPerAddress;
    uint32 public presaleMaxPerAddress;
    uint32 public freeMintMaxPerAddress;
    uint32 public presaleSupply;
    uint32 public freeMintSupply;
    bool public publicFlag;
    bool public presaleFlag;
    bool public freeMintFlag;

    // INTERNAL VARIABLES

    bytes32 internal immutable NAME_HASH;
    bytes32 internal immutable VERSION_HASH;
    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;
    uint256 internal immutable INITIAL_CHAIN_ID;

    // PRIVATE VARIABLES

    uint32 private _royaltyRate;
    bytes32 private _presaleMerkleRoot;
    bytes32 private _freeMintMerkleRoot;
    string private baseURI_;
    string private _preRevealURI;

    //EVENTS

    event FlagSwitched(bool isActive);
    event RoyaltyRateUpdated(uint32 amount);
    event PreRevealURIUpdated(string uri);
    event BaseURIUpdated(string uri);
    event PresaleMerkleRootUpdated(bytes32 root);
    event PublicPriceUpdated(uint256 price);
    event PresalePriceUpdated(uint256 price);
    event MaxPerAddressUpdated(uint32 quantity);
    event PresaleSupplyUpdated(uint32 quantity);
    event FreeMintSupplyUpdated(uint32 quantity);

    error WithdrawEthFailed();

    // MODIFIERS

    modifier isSufficientSupply(uint256 quantity) {
        require(
            quantity + totalSupply() <= MAX_SUPPLY,
            "Insufficient token supply"
        );
        _;
    }

    // MAPPINGS

    mapping(address => uint256) public publicMinted;
    mapping(address => uint256) public presaleMinted;
    mapping(address => uint256) public freeMintMinted;
    mapping(uint256 => uint256) private _nonces;

    // CONSTRUCTOR

    constructor(
        string memory name,
        string memory symbol,
        string memory version,
        uint256 maxSupply_,
        address multisigAddress
    ) ERC721A(name, symbol) {
        NAME_HASH = keccak256(bytes(name));
        VERSION_HASH = keccak256(bytes(version));
        INITIAL_DOMAIN_SEPARATOR = _computeDomainSeparator();
        INITIAL_CHAIN_ID = block.chainid;
        MAX_SUPPLY = maxSupply_;

        transferOwnership(multisigAddress);
    }

    // EXTERNAL FUNCTIONS

    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        external
        view
        returns (address, uint256)
    {
        uint256 royaltyAmount = (salePrice * _royaltyRate) / SCALE;
        return (owner(), royaltyAmount);
    }

    /// @notice gets the global royalty rate
    /// @dev divide rate by scale to get the percentage taken as royalties
    /// @return a tuple of (rate, scale)
    function royaltyRate() external view returns (uint256, uint256) {
        return (_royaltyRate, SCALE);
    }

    // PUBLIC FUNCTIONS

    function setPublicPrice(uint256 price) public onlyOwner {
        publicPrice = price;

        emit PublicPriceUpdated(price);
    }

    function setPresalePrice(uint256 price) public onlyOwner {
        presalePrice = price;

        emit PresalePriceUpdated(price);
    }

    function setPublicMaxPerAddress(uint32 quantity) public onlyOwner {
        publicMaxPerAddress = quantity;

        emit MaxPerAddressUpdated(quantity);
    }

    function setPresaleMaxPerAddress(uint32 quantity) public onlyOwner {
        presaleMaxPerAddress = quantity;

        emit MaxPerAddressUpdated(quantity);
    }

    function setFreeMintMaxPerAddress(uint32 quantity) public onlyOwner {
        freeMintMaxPerAddress = quantity;

        emit MaxPerAddressUpdated(quantity);
    }

    function setPresaleSupply(uint32 quantity) public onlyOwner {
        presaleSupply = quantity;

        emit PresaleSupplyUpdated(quantity);
    }

    function setFreeMintSupply(uint32 quantity) public onlyOwner {
        freeMintSupply = quantity;

        emit FreeMintSupplyUpdated(quantity);
    }

    function setRoyaltyRate(uint32 rate) public onlyOwner {
        _royaltyRate = rate;

        emit RoyaltyRateUpdated(rate);
    }

    function setBaseURI(string memory uri) public onlyOwner {
        baseURI_ = uri;

        emit BaseURIUpdated(uri);
    }

    function setPreRevealURI(string memory uri) public onlyOwner {
        _preRevealURI = uri;

        emit PreRevealURIUpdated(uri);
    }

    function setPresaleMerkleRoot(bytes32 merkleRoot) public onlyOwner {
        _presaleMerkleRoot = merkleRoot;

        emit PresaleMerkleRootUpdated(merkleRoot);
    }

    function setFreeMintMerkleRoot(bytes32 merkleRoot) public onlyOwner {
        _freeMintMerkleRoot = merkleRoot;

        emit PresaleMerkleRootUpdated(merkleRoot);
    }

    function switchPublicFlag() public onlyOwner {
        bool publicFlag_ = publicFlag;

        publicFlag = !publicFlag_;

        emit FlagSwitched(publicFlag_);
    }

    function switchPresaleFlag() public onlyOwner {
        bool presaleFlag_ = presaleFlag;

        presaleFlag = !presaleFlag_;

        emit FlagSwitched(presaleFlag_);
    }

    function switchFreemintFlag() public onlyOwner {
        bool freeMintFlag_ = freeMintFlag;

        freeMintFlag = !freeMintFlag_;

        emit FlagSwitched(freeMintFlag_);
    }

    function mint(address to, uint256 quantity)
        public
        payable
        nonReentrant
        isSufficientSupply(quantity)
    {
        require(publicFlag, "Public sale not active");
        require(msg.value >= publicPrice * quantity, "Mint: Insufficient ETH");

        if (publicMaxPerAddress > 0) {
            require(
                quantity + publicMinted[msg.sender] <= publicMaxPerAddress,
                "Mint: Amount exceeds max per address"
            );
        }

        publicMinted[msg.sender] = publicMinted[msg.sender] + quantity;
        _safeMint(to, quantity);

        (bool success, ) = owner().call{value: msg.value}("");
        require(success, "Mint: ETH transfer failed");
    }

    function presaleMint(
        address to,
        uint256 quantity,
        bytes32[] calldata proof
    ) public payable nonReentrant {
        address sender = msg.sender;

        require(presaleFlag, "Presale mint is not active");
        require(
            msg.value >= presalePrice * quantity,
            "Presale mint: Insufficient ETH"
        );
        require(
            quantity + totalSupply() <= presaleSupply,
            "Insufficient presale token supply"
        );
        require(
            MerkleProof.verify(
                proof,
                _presaleMerkleRoot,
                keccak256(abi.encodePacked(sender))
            ),
            "Invalid merkle proof"
        );

        if (presaleMaxPerAddress > 0) {
            require(
                quantity + presaleMinted[sender] <= presaleMaxPerAddress,
                "Presale mint: Amount exceeds max per address"
            );
        }

        presaleMinted[sender] = presaleMinted[sender] + quantity;
        _safeMint(to, quantity, "");

        (bool success, ) = owner().call{value: msg.value}("");
        require(success, "Presale mint: ETH transfer failed");
    }

    function freeMint(
        address to,
        uint256 quantity,
        bytes32[] calldata proof
    ) public payable nonReentrant {
        address sender = msg.sender;

        require(freeMintFlag, "Free mint is not active");
        require(
            quantity + totalSupply() <= freeMintSupply,
            "Insufficient free-mint token supply"
        );
        require(
            MerkleProof.verify(
                proof,
                _freeMintMerkleRoot,
                keccak256(abi.encodePacked(sender))
            ),
            "Invalid merkle proof"
        );

        if (freeMintMaxPerAddress > 0) {
            require(
                quantity + freeMintMinted[sender] <= freeMintMaxPerAddress,
                "Free mint: Amount exceeds max per address"
            );
        }

        freeMintMinted[sender] = freeMintMinted[sender] + quantity;
        _safeMint(to, quantity, "");
    }

    // NOTE: in current structure, must mint entire allotted quantity in one mint
    function founderMint(address to, uint256 quantity)
        public
        payable
        onlyOwner
        nonReentrant
        isSufficientSupply(quantity)
    {
        _safeMint(to, quantity, "");
    }

    function crossmint(address to, uint256 quantity) public payable {
        require(
            msg.sender == 0xdAb1a1854214684acE522439684a145E62505233,
            "This function is for Crossmint only."
        );
        mint(to, quantity);
    }

    function withdrawFunds() public onlyOwner {
        (bool success, ) = owner().call{value: address(this).balance}("");
        if (!success) revert WithdrawEthFailed();
    }

    // ERC721A RELATED FUNCTIONS

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public payable override {
        ERC721A.transferFrom(from, to, tokenId);
        if (from != address(0)) {
            _nonces[tokenId]++;
        }
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721A, IERC165)
        returns (bool)
    {
        return
            ERC721A.supportsInterface(interfaceId) ||
            interfaceId == type(IERC2981).interfaceId ||
            interfaceId == type(IERC4494).interfaceId;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(_exists(tokenId), "URI query for nonexistent token");

        if (bytes(baseURI_).length != 0) {
            return
                string(abi.encodePacked(baseURI_, tokenId.toString(), SUFFIX));
        }

        return _preRevealURI;
    }

    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI_;
    }

    // IERC4494 RELATED FUNCTIONS

    function nonces(uint256 tokenId) external view returns (uint256) {
        require(_exists(tokenId), "Nonces: Query for nonexistent token");

        return _nonces[tokenId];
    }

    function transferWithPermit(
        address from,
        address to,
        uint256 tokenId,
        uint256 deadline,
        bytes memory sig
    ) public {
        permit(to, tokenId, deadline, sig);
        safeTransferFrom(from, to, tokenId, "");
    }

    function permit(
        address spender,
        uint256 tokenId,
        uint256 deadline,
        bytes memory sig
    ) public {
        require(block.timestamp <= deadline, "Permit has expired");

        bytes32 digest = ECDSA.toTypedDataHash(
            DOMAIN_SEPARATOR(),
            keccak256(
                abi.encode(
                    PERMIT_TYPEHASH,
                    spender,
                    tokenId,
                    _nonces[tokenId],
                    deadline
                )
            )
        );

        (address recoveredAddress, ) = ECDSA.tryRecover(digest, sig);
        address owner = ownerOf(tokenId);

        require(recoveredAddress != address(0), "Invalid signature");
        require(spender != owner, "ERC721Permit: Approval to current owner");

        if (owner != recoveredAddress) {
            require(
                // checks for both EIP2098 sigs and EIP1271 approvals
                SignatureChecker.isValidSignatureNow(owner, digest, sig),
                "ERC721Permit: Unauthorized"
            );
        }

        _tokenApprovals[tokenId].value = spender;
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return
            block.chainid == INITIAL_CHAIN_ID
                ? INITIAL_DOMAIN_SEPARATOR
                : _computeDomainSeparator();
    }

    function _computeDomainSeparator() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    NAME_HASH,
                    VERSION_HASH,
                    block.chainid,
                    address(this)
                )
            );
    }
}
