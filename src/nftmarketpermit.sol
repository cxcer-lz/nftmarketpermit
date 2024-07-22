// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract NFTMarket is Ownable(msg.sender), EIP712("OpenSpaceNFTMarket", "1") {
    address public constant ETH_FLAG = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    uint256 public constant feeBP = 30; // 30/10000 = 0.3%
    address public whiteListSigner;
    address public feeTo;

    struct SellOrder {
        address seller;
        address nft;
        uint256 tokenId;
        address payToken;
        uint256 price;
        uint256 deadline;
    }

    bytes32 constant LIST_TYPEHASH = keccak256("SellOrder(address seller,address nft,uint256 tokenId,address payToken,uint256 price,uint256 deadline)");
    mapping(bytes32 => bool) public cancelledOrders; // Blacklist for cancelled orders

    function buy(SellOrder calldata order, bytes calldata signature) public payable {
        buy(order, signature, feeTo);
    }

    function buy(SellOrder calldata order, bytes calldata signature, bytes calldata signatureForWL) external payable {
        _checkWL(signatureForWL);
        // trade fee is zero
        buy(order, signature, address(0));
    }

    function buy(SellOrder calldata order, bytes calldata signature, address feeReceiver) private {
        bytes32 orderId = _hashOrder(order);

        // Check if the order is cancelled
        require(!cancelledOrders[orderId], "MKT: order cancelled");

        // Verify the signature
        address signer = ECDSA.recover(_hashTypedDataV4(orderId), signature);
        require(signer == order.seller, "MKT: invalid signature");

        // Check order validity
        require(order.deadline > block.timestamp, "MKT: order expired");
        require(IERC721(order.nft).ownerOf(order.tokenId) == order.seller, "MKT: not owner");
        require(
            IERC721(order.nft).getApproved(order.tokenId) == address(this)
                || IERC721(order.nft).isApprovedForAll(order.seller, address(this)),
            "MKT: not approved"
        );

        // Transfer NFT
        IERC721(order.nft).safeTransferFrom(order.seller, msg.sender, order.tokenId);

        // Transfer payment
        uint256 fee = feeReceiver == address(0) ? 0 : order.price * feeBP / 10000;
        if (order.payToken == ETH_FLAG) {
            require(msg.value == order.price, "MKT: wrong eth value");
            _transferETH(order.seller, order.price - fee);
            if (fee > 0) _transferETH(feeReceiver, fee);
        } else {
            require(msg.value == 0, "MKT: wrong eth value");
            SafeERC20.safeTransferFrom(IERC20(order.payToken), msg.sender, order.seller, order.price - fee);
            if (fee > 0) SafeERC20.safeTransferFrom(IERC20(order.payToken), msg.sender, feeReceiver, fee);
        }

        emit Sold(orderId, msg.sender, fee);
    }

    function cancel(SellOrder calldata order, bytes calldata signature) external {
        bytes32 orderId = _hashOrder(order);

        // Verify the signature
        address signer = ECDSA.recover(_hashTypedDataV4(orderId), signature);
        require(signer == order.seller, "MKT: invalid signature");

        // Only the seller can cancel their own order
        require(signer == msg.sender, "MKT: not the seller");

        // Mark the order as cancelled
        cancelledOrders[orderId] = true;

        emit Cancel(orderId);
    }

    bytes32 constant WL_TYPEHASH = keccak256("IsWhiteList(address user)");
    function _checkWL(bytes calldata signature) private view {
        bytes32 wlHash = _hashTypedDataV4(keccak256(abi.encode(WL_TYPEHASH, msg.sender)));
        address signer = ECDSA.recover(wlHash, signature);
        require(signer == whiteListSigner, "MKT: not whiteListSigner");
    }

    function _hashOrder(SellOrder calldata order) private pure returns (bytes32) {
        return keccak256(abi.encode(LIST_TYPEHASH, order.seller, order.nft, order.tokenId, order.payToken, order.price, order.deadline));
    }

    function _transferETH(address to, uint256 amount) private {
        (bool success, ) = to.call{value: amount}("");
        require(success, "MKT: transfer failed");
    }

    function getListTypeHash() external pure returns (bytes32) {
        return LIST_TYPEHASH;
    }

    // admin functions
    function setWhiteListSigner(address signer) external onlyOwner {
        require(signer != address(0), "MKT: zero address");
        require(whiteListSigner != signer, "MKT: repeat set");
        whiteListSigner = signer;

        emit SetWhiteListSigner(signer);
    }

    function setFeeTo(address to) external onlyOwner {
        require(feeTo != to, "MKT: repeat set");
        feeTo = to;

        emit SetFeeTo(to);
    }

    event Sold(bytes32 orderId, address buyer, uint256 fee);
    event Cancel(bytes32 orderId);
    event SetFeeTo(address to);
    event SetWhiteListSigner(address signer);
}
