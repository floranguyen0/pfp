// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {PFP} from "../../src/PFP.sol";

contract SigUtils {
    /// @notice The ERC-20 token domain separator
    bytes32 internal immutable DOMAIN_SEPARATOR;
    PFP pfp;

    constructor(bytes32 _DOMAIN_SEPARATOR, address PFPAddress) {
        DOMAIN_SEPARATOR = _DOMAIN_SEPARATOR;
        pfp = PFP(PFPAddress);
    }

    // keccak256("Permit(address spender,uint256 tokenId,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH =
        0x49ecf333e5b8c95c40fdafc95c1ad136e8914a8fb55e9dc8bb01eaa83a2df9ad;

    struct Permit {
        address spender;
        uint256 tokenId;
        uint256 nonce;
        uint256 deadline;
    }

    /// @dev Computes the hash of a permit
    /// @param _permit The approval to execute on-chain
    /// @return The encoded permit
    function getStructHash(Permit memory _permit)
        internal
        view
        returns (bytes32)
    {
        return
            keccak256(
                abi.encode(
                    PERMIT_TYPEHASH,
                    _permit.spender,
                    _permit.tokenId,
                    pfp.nonces(_permit.tokenId),
                    _permit.deadline
                )
            );
    }

    /// @notice Computes the hash of a fully encoded EIP-712 message for the domain
    /// @param _permit The approval to execute on-chain
    /// @return The digest to sign and use to recover the signer
    function getTypedDataHash(Permit memory _permit)
        public
        view
        returns (bytes32)
    {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    getStructHash(_permit)
                )
            );
    }
}
