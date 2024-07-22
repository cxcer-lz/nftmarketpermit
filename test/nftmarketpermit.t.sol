// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/nftmarketpermit.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestNFT is ERC721 {
    constructor() ERC721("TestNFT", "TNFT") {}

    function mint(address to, uint256 tokenId) public {
        _mint(to, tokenId);
    }
}

contract TestToken is ERC20 {
    constructor() ERC20("TestToken", "TTKN") {
        _mint(msg.sender, 10000 * 10 ** 18);
    }
}

contract NFTMarketTest is Test, EIP712 {
    NFTMarket public market;
    TestNFT public nft;
    TestToken public token;
    address public seller;
    address public buyer;
    uint256 public tokenId = 1;
    uint256 public price = 100 * 10 ** 18; // 100 TTKN

    constructor() EIP712("OpenSpaceNFTMarket", "1") {}

    function setUp() public {
        seller = address(0x1);
        buyer = address(0x2);
        market = new NFTMarket();
        nft = new TestNFT();
        token = new TestToken();

        // Mint NFT and transfer to seller
        nft.mint(seller, tokenId);

        // Approve market to transfer NFT
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        vm.stopPrank();

        // Transfer tokens to buyer
        token.transfer(buyer, price);
    }

    function testListNFT() public view {
        // Create a SellOrder struct
        NFTMarket.SellOrder memory order = NFTMarket.SellOrder({
            seller: seller,
            nft: address(nft),
            tokenId: tokenId,
            payToken: address(token),
            price: price,
            deadline: block.timestamp + 1 days
        });

        // Sign the order
        bytes32 orderHash = keccak256(abi.encode(
            market.getListTypeHash(),
            order.seller,
            order.nft,
            order.tokenId,
            order.payToken,
            order.price,
            order.deadline
        ));
        bytes memory signature = signOrder(seller, orderHash);

        // Check if the signature is valid
        address recovered = recoverSigner(orderHash, signature);
        assertEq(recovered, seller);
    }

    function testBuyNFT() public {
        // Create and sign the order
        NFTMarket.SellOrder memory order = createOrder();
        bytes memory signature = signOrder(seller, _hashOrder(order));

        // Approve tokens to the market
        vm.startPrank(buyer);
        token.approve(address(market), price);

        // Buy the NFT
        market.buy{value: 0}(order, signature);

        // Check the NFT ownership
        assertEq(nft.ownerOf(tokenId), buyer);
        vm.stopPrank();
    }

    function testCancelOrder() public {
        // Create and sign the order
        NFTMarket.SellOrder memory order = createOrder();
        bytes memory signature = signOrder(seller, _hashOrder(order));

        // Cancel the order
        vm.startPrank(seller);
        market.cancel(order, signature);
        vm.stopPrank();

        // Try to buy the NFT (should fail)
        vm.startPrank(buyer);
        token.approve(address(market), price);
        vm.expectRevert("MKT: order cancelled");
        market.buy{value: 0}(order, signature);
        vm.stopPrank();
    }

    function createOrder() internal view returns (NFTMarket.SellOrder memory) {
        return NFTMarket.SellOrder({
            seller: seller,
            nft: address(nft),
            tokenId: tokenId,
            payToken: address(token),
            price: price,
            deadline: block.timestamp + 1 days
        });
    }

    function signOrder(address signer, bytes32 hash) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(uint160(signer)), hash);
        return abi.encodePacked(r, s, v);
    }

    function _hashOrder(NFTMarket.SellOrder memory order) internal view returns (bytes32) {
        return keccak256(abi.encode(
            market.getListTypeHash(),
            order.seller,
            order.nft,
            order.tokenId,
            order.payToken,
            order.price,
            order.deadline
        ));
    }

    function recoverSigner(bytes32 hash, bytes memory signature) internal pure returns (address) {
        return ECDSA.recover(hash, signature);
    }
}
