// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IERC4494.sol";
import "./ERC721A.sol";

contract PFP is ERC721A, ERC2981, IERC4494, Ownable, ReentrancyGuard {
    using Strings for uint256;

    /*//////////////////////////////////////////////////////////////
                           PUBLIC VARIABLES
    //////////////////////////////////////////////////////////////*/

    // keccak256("Permit(address spender,uint256 tokenId,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH =
        0x49ecf333e5b8c95c40fdafc95c1ad136e8914a8fb55e9dc8bb01eaa83a2df9ad;
    bytes32 public constant SUFFIX = ".json";
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

    /*//////////////////////////////////////////////////////////////
                          PRIVATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    bytes32 private immutable NAME_HASH;
    bytes32 private immutable VERSION_HASH;
    bytes32 private immutable INITIAL_DOMAIN_SEPARATOR;
    uint256 private immutable INITIAL_CHAIN_ID;
    uint192 private _toReveal;
    bytes32 private _presaleMerkleRoot;
    bytes32 private _freeMintMerkleRoot;
    string private baseURI_;
    string private _preRevealURI;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier isSufficientSupply(uint256 quantity) {
        require(
            quantity + totalSupply() <= MAX_SUPPLY,
            "Insufficient token supply"
        );
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               MAPPINGS
    //////////////////////////////////////////////////////////////*/

    mapping(address => uint256) public publicMinted;
    mapping(address => uint256) public presaleMinted;
    mapping(address => uint256) public freeMintMinted;
    mapping(uint256 => uint256) private _nonces;

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        string memory name,
        string memory symbol,
        string memory version,
        uint256 maxSupply_
    ) ERC721A(name, symbol) {
        NAME_HASH = keccak256(bytes(name));
        VERSION_HASH = keccak256(bytes(version));
        INITIAL_DOMAIN_SEPARATOR = _computeDomainSeparator();
        INITIAL_CHAIN_ID = block.chainid;
        MAX_SUPPLY = maxSupply_;
    }

    /*//////////////////////////////////////////////////////////////
                          EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function mint(address to, uint256 quantity)
        external
        payable
        isSufficientSupply(quantity)
        nonReentrant
    {
        uint256 price = publicPrice * quantity;
        require(publicFlag, "Public sale is not active");
        require(msg.value >= price, "Mint: Insufficient ETH");

        if (publicMaxPerAddress > 0) {
            require(
                publicMinted[msg.sender] + quantity <= publicMaxPerAddress,
                "Mint: Amount exceeds max per address"
            );
        }

        unchecked {
            publicMinted[msg.sender] = publicMinted[msg.sender] + quantity;
        }

        if (msg.value > price) {
            (bool success, bytes memory reason) = msg.sender.call{
                value: msg.value - price
            }("");
            require(success, string(reason));
        }

        for (uint256 i = 0; i < quantity; i++) {
            (address receiver, uint256 royaltyAmount) = royaltyInfo(
                _nextTokenId() + i,
                price
            );

            (bool royaltySuccess, bytes memory returnedReason) = receiver.call{
                value: royaltyAmount
            }("");
            require(royaltySuccess, string(returnedReason));
        }

        _safeMint(to, quantity);

        emit Mint(to, quantity);
    }

    function presaleMint(
        address to,
        uint256 quantity,
        bytes32[] calldata proof
    ) external payable nonReentrant {
        uint256 price = presalePrice * quantity;
        require(presaleFlag, "Presale mint is not active");
        require(msg.value >= price, "Presale mint: Insufficient ETH");
        require(
            totalSupply() + quantity <= presaleSupply,
            "Insufficient presale token supply"
        );
        require(
            MerkleProof.verify(
                proof,
                _presaleMerkleRoot,
                keccak256(abi.encodePacked(msg.sender))
            ),
            "Invalid merkle proof"
        );

        if (presaleMaxPerAddress > 0) {
            require(
                presaleMinted[msg.sender] + quantity <= presaleMaxPerAddress,
                "Presale mint: Amount exceeds max per address"
            );
        }

        unchecked {
            presaleMinted[msg.sender] = presaleMinted[msg.sender] + quantity;
        }

        if (msg.value > price) {
            (bool success, bytes memory reason) = msg.sender.call{
                value: msg.value - price
            }("");
            require(success, string(reason));
        }

        for (uint256 i = 0; i < quantity; i++) {
            (address receiver, uint256 royaltyAmount) = royaltyInfo(
                _nextTokenId() + i,
                price
            );

            (bool royaltySuccess, bytes memory returnedReason) = receiver.call{
                value: royaltyAmount
            }("");
            require(royaltySuccess, string(returnedReason));
        }

        _safeMint(to, quantity, "");

        emit PresaleMint(to, quantity);
    }

    function freeMint(
        address to,
        uint256 quantity,
        bytes32[] calldata proof
    ) external {
        require(freeMintFlag, "Free mint is not active");
        require(
            totalSupply() + quantity <= freeMintSupply,
            "Insufficient free-mint token supply"
        );
        require(
            MerkleProof.verify(
                proof,
                _freeMintMerkleRoot,
                keccak256(abi.encodePacked(msg.sender))
            ),
            "Invalid merkle proof"
        );

        if (freeMintMaxPerAddress > 0) {
            require(
                freeMintMinted[msg.sender] + quantity <= freeMintMaxPerAddress,
                "Free mint: Amount exceeds max per address"
            );
        }

        unchecked {
            freeMintMinted[msg.sender] = freeMintMinted[msg.sender] + quantity;
        }

        _safeMint(to, quantity, "");

        emit FreeMint(to, quantity);
    }

    // NOTE: in current structure, must mint entire allotted quantity in one mint
    function founderMint(address to, uint256 quantity)
        external
        onlyOwner
        isSufficientSupply(quantity)
    {
        _safeMint(to, quantity, "");

        emit FounderMint(to, quantity);
    }

    function execTransaction(
        address target,
        bytes calldata data,
        uint256 weiAmount
    ) external payable onlyOwner {
        (bool success, bytes memory reason) = target.call{value: weiAmount}(
            data
        );
        require(success, string(reason));

        emit ExecTransaction(target, data, weiAmount);
    }

    function setRevealNumber(uint192 amount) external onlyOwner {
        uint192 preAmount = _toReveal;
        _toReveal = amount;
        emit RevealNumberUpdated(preAmount, amount);
    }

    function setPublicPrice(uint256 price) external onlyOwner {
        uint256 prePrice = publicPrice;
        publicPrice = price;

        emit PublicPriceUpdated(prePrice, price);
    }

    function setPresalePrice(uint256 price) external onlyOwner {
        uint256 prePrice = presalePrice;
        presalePrice = price;

        emit PresalePriceUpdated(prePrice, price);
    }

    function setPublicMaxPerAddress(uint32 quantity) external onlyOwner {
        uint32 preQuantity = publicMaxPerAddress;
        publicMaxPerAddress = quantity;

        emit PublicMaxPerAddressUpdated(preQuantity, quantity);
    }

    function setPresaleMaxPerAddress(uint32 quantity) external onlyOwner {
        uint32 preQuantity = presaleMaxPerAddress;
        presaleMaxPerAddress = quantity;

        emit PresaleMaxPerAddressUpdated(preQuantity, quantity);
    }

    function setFreeMintMaxPerAddress(uint32 quantity) external onlyOwner {
        uint32 preQuantity = freeMintMaxPerAddress;
        freeMintMaxPerAddress = quantity;

        emit FreeMintMaxPerAddressUpdated(preQuantity, quantity);
    }

    function setPresaleSupply(uint32 quantity) external onlyOwner {
        uint32 preQuantity = presaleSupply;
        presaleSupply = quantity;

        emit PresaleSupplyUpdated(preQuantity, quantity);
    }

    function setFreeMintSupply(uint32 quantity) external onlyOwner {
        uint32 preQuantity = freeMintSupply;
        freeMintSupply = quantity;

        emit FreeMintSupplyUpdated(preQuantity, quantity);
    }

    function setBaseURI(string memory uri) external onlyOwner {
        string memory preBaseURI = baseURI_;
        baseURI_ = uri;

        emit BaseURIUpdated(preBaseURI, uri);
    }

    function setPreRevealURI(string memory uri) external onlyOwner {
        string memory preURI = _preRevealURI;
        _preRevealURI = uri;

        emit PreRevealURIUpdated(preURI, uri);
    }

    function setPresaleMerkleRoot(bytes32 merkleRoot) external onlyOwner {
        _presaleMerkleRoot = merkleRoot;

        emit PresaleMerkleRootUpdated(merkleRoot);
    }

    function setFreeMintMerkleRoot(bytes32 merkleRoot) external onlyOwner {
        _freeMintMerkleRoot = merkleRoot;

        emit PresaleMerkleRootUpdated(merkleRoot);
    }

    function switchPublicFlag() external onlyOwner {
        bool publicFlag_ = publicFlag;

        publicFlag = !publicFlag_;

        emit FlagSwitched(!publicFlag_);
    }

    function switchPresaleFlag() external onlyOwner {
        bool presaleFlag_ = presaleFlag;

        presaleFlag = !presaleFlag_;

        emit FlagSwitched(!presaleFlag_);
    }

    function switchFreemintFlag() external onlyOwner {
        bool freeMintFlag_ = freeMintFlag;

        freeMintFlag = !freeMintFlag_;

        emit FlagSwitched(!freeMintFlag_);
    }

    /*//////////////////////////////////////////////////////////////
                      ERC721A RELATED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public payable override {
        ERC721A.transferFrom(from, to, tokenId);
        if (from != address(0)) {
            unchecked {
                _nonces[tokenId]++;
            }
        }
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(_exists(tokenId), "URI query for nonexistent token");

        if (bytes(baseURI_).length != 0 && tokenId <= _toReveal) {
            return
                string(abi.encodePacked(baseURI_, tokenId.toString(), SUFFIX));
        }

        return _preRevealURI;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI_;
    }

    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    /*//////////////////////////////////////////////////////////////
                      ERC2981 RELATED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721A, ERC2981, IERC165)
        returns (bool)
    {
        return
            ERC721A.supportsInterface(interfaceId) ||
            ERC2981.supportsInterface(interfaceId) ||
            interfaceId == type(IERC4494).interfaceId ||
            interfaceId == type(IERC721A).interfaceId;
    }

    function setDefaultRoyalty(address receiver, uint96 feeNumerator)
        external
        onlyOwner
    {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function deleteDefaultRoyalty() external onlyOwner {
        _deleteDefaultRoyalty();
    }

    function setTokenRoyalty(
        uint256 tokenId,
        address receiver,
        uint96 feeNumerator
    ) external onlyOwner {
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }

    function resetTokenRoyalty(uint256 tokenId) external onlyOwner {
        _resetTokenRoyalty(tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                      IERC4494 RELATED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

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
    ) external {
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
        emit Approval(owner, spender, tokenId);
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
