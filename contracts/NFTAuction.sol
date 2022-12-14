//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface INFTMarketplace {
    function fetchCreatorNft(uint tokenId) external view returns (address);

    function fetchRoyaltyPercentofNft(uint tokenId)
        external
        view
        returns (uint);

    function getlistingFee() external view returns (uint256);
}

contract NFTAuction {
    INFTMarketplace marketplace;
    address marketplaceAddress;
    address NFTMarketplaceOwner;
    mapping(uint256 => Auction) public IdtoAuction; // tokenid to auction
    mapping(uint256 => mapping(address => uint256)) public bids; // tokenid to bids of addresses

    uint listingfeeAccruel;

    // need to get some details from imported nftmarketplace contract
    struct Auction {
        // address marketplaceAddress;
        uint nftId;
        address payable seller;
        uint minPrice;
        uint endAt;
        bool started;
        bool ended;
        address highestBidder;
        uint highestBid;
        address payable creator;
        uint royaltyPercent;
    }

    constructor(address _marketplaceAddress, address _marketplaceOwner) {
        marketplace = INFTMarketplace(_marketplaceAddress);
        marketplaceAddress = _marketplaceAddress;
        NFTMarketplaceOwner = payable(_marketplaceOwner);
    }

    modifier onlyOwner() {
        require(
            msg.sender == NFTMarketplaceOwner,
            "only owner of the marketplace can perform this action"
        );
        _;
    }

    function start(
        uint nftId,
        uint _minPrice,
        uint8 auctiondays
    ) external payable {
        require(!IdtoAuction[nftId].started, "Started");
        require(
            msg.sender == IERC721(marketplaceAddress).ownerOf(nftId),
            "Not Owner"
        );
        require(
            msg.value == marketplace.getlistingFee(),
            "Must be equal to listing price"
        );
        require(
            auctiondays <= 7 && auctiondays >= 1,
            "auction time should be less than 7 days and more than 1 day"
        );
        // the seller should approve this contract to execute the below code
        // the approval function can be put in front-end

        IdtoAuction[nftId].started = true;
        IdtoAuction[nftId].ended = false;
        IdtoAuction[nftId].nftId = nftId;
        IdtoAuction[nftId].seller = payable(msg.sender);
        IdtoAuction[nftId].minPrice = _minPrice * 10**18;
        IdtoAuction[nftId].endAt = block.timestamp + auctiondays * 1 days;
        listingfeeAccruel += msg.value;

        IdtoAuction[nftId].creator = payable(
            marketplace.fetchCreatorNft(nftId)
        );

        IdtoAuction[nftId].royaltyPercent = marketplace
            .fetchRoyaltyPercentofNft(nftId);

        IERC721(marketplaceAddress).transferFrom(
            msg.sender,
            address(this),
            nftId
        );

        // emit start();
    }

    function withdrawListingFeeCommission() external onlyOwner {
        require(listingfeeAccruel > 0, "Zero balance in the account.");
        listingfeeAccruel = 0;
        payable(NFTMarketplaceOwner).transfer(listingfeeAccruel);
        // emit MarketplaceBalanceWithdrew();
    }

    function bid(uint nftId) external payable {
        require(IdtoAuction[nftId].started, "Not Started");
        require(block.timestamp < IdtoAuction[nftId].endAt, "ended");
        require(
            msg.value + bids[nftId][msg.sender] > IdtoAuction[nftId].highestBid,
            "value should be greater than current highest bid"
        );
        require(
            msg.value + bids[nftId][msg.sender] > IdtoAuction[nftId].minPrice,
            "value should be greater minprice"
        );

        if (IdtoAuction[nftId].highestBidder != address(0)) {
            bids[nftId][msg.sender] += msg.value;
            IdtoAuction[nftId].highestBidder = msg.sender;
            IdtoAuction[nftId].highestBid = bids[nftId][msg.sender];
        } else {
            bids[nftId][msg.sender] = msg.value;
            IdtoAuction[nftId].highestBidder = msg.sender;
            IdtoAuction[nftId].highestBid = bids[nftId][msg.sender];
        }

        // emit Bid();
    }

    function withdrawBid(uint nftId) external {
        require(
            block.timestamp > IdtoAuction[nftId].endAt,
            "Bid can be withdrawn only after auction has ended"
        );
        require(bids[nftId][msg.sender] > 0, "You have no amount in bid");
        uint bal = bids[nftId][msg.sender];
        bids[nftId][msg.sender] = 0;
        payable(msg.sender).transfer(bal);

        // emit Withdraw();
    }

    function end(uint nftId) external {
        require(IdtoAuction[nftId].started, "not started");
        require(
            block.timestamp > IdtoAuction[nftId].endAt,
            "auction still going"
        );
        require(!IdtoAuction[nftId].ended, "ended");
        IdtoAuction[nftId].ended = true;
        uint256 royaltyAmount = ((IdtoAuction[nftId].royaltyPercent *
            IdtoAuction[nftId].highestBid) / 100);
        uint256 SellerPayout = IdtoAuction[nftId].highestBid - royaltyAmount;

        IdtoAuction[nftId].started = false;
        IdtoAuction[nftId].minPrice = 0;

        if (IdtoAuction[nftId].highestBidder != address(0)) {
            IERC721(marketplaceAddress).safeTransferFrom(
                address(this),
                IdtoAuction[nftId].highestBidder,
                nftId
            );
            bids[nftId][IdtoAuction[nftId].highestBidder] = 0;
            IdtoAuction[nftId].highestBid = 0;
            IdtoAuction[nftId].highestBidder = address(0);
            IdtoAuction[nftId].seller.transfer(SellerPayout);
            IdtoAuction[nftId].creator.transfer(royaltyAmount);
        } else {
            IERC721(marketplaceAddress).safeTransferFrom(
                address(this),
                IdtoAuction[nftId].seller,
                nftId
            );
            IdtoAuction[nftId].highestBidder = address(0);
            IdtoAuction[nftId].highestBid = 0;
        }

        // emit End();
    }

    function fetchNftAuctionData(uint nftId)
        public
        view
        returns (Auction memory)
    {
        return IdtoAuction[nftId];
    }

    function fetchMyBidAmountDataForNft(uint nftId) public view returns (uint) {
        return bids[nftId][msg.sender];
    }
}
