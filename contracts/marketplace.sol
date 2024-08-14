// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {IERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title NftMarketplace
 * @author Rakmans
 * @notice A marketplace for buying and selling NFTs
 */
contract NftMarketplace is ERC1155Holder, ERC721Holder {
    using SafeERC20 for IERC20;

    /**
     * @dev Enum for token types
     */
    enum TokenType {
        ERC1155,
        ERC721
    }
    /**
     * @dev Enum for listing types
     */
    enum ListingType {
        Sale,
        Auction
    }
    /**
     * @dev Struct for bids
     */
    struct Bid {
        address bidder;
        uint256 bid;
        uint256 quantity;
    }

    /**
     * @dev Struct for listings
     */
    struct Listing {
        uint256 id;
        address tokenContract;
        uint256 tokenId;
        TokenType tokenType;
        address creator;
        address paymentToken;
        uint256 price;
        uint256 start;
        uint256 end;
        uint256 quantity;
        bool ended;
        bool isAuction;
    }

    /**
     * @dev Platform fee
     */
    uint256 public PLATFORM_FEE;
    /**
     * @dev Maximum basis points
     */
    uint256 public MAX_BPS;
    /**
     * @dev Bid buffer basis points
     */
    uint256 public BID_BUFFER_BPS;
    /**
     * @dev Platform owner
     */
    address public PLATFORM_OWNER;
    /**
     * @dev Time buffer
     */
    uint256 public TIME_BUFFER;

    /**
     * @dev Mapping of listing ID _to bids
     */
    mapping(uint256 => Bid[]) public bids;
    mapping(uint256 => mapping(address => Bid)) public bidsMap;

    /**
     * @dev Array of listings
     */
    Listing[] public listings;

    /**
     * @dev Event emitted when a listing is created
     */
    event CreatListingLog(
        uint256 indexed listingId,
        address indexed creator,
        address indexed tokenContract,
        uint256 tokenId,
        uint256 quantity,
        bool auction
    );
    /**
     * @dev Event emitted when a listing is edited
     */
    event EditListingLog(
        uint256 indexed listingId,
        address indexed creator,
        address indexed tokenContract,
        uint256 tokenId,
        uint256 quantity
    );
    /**
     * @dev Event emitted when a listing is bought
     */
    event BuyLog(
        uint256 indexed listingId,
        address indexed buyer,
        uint256 quantity,
        uint256 price
    );
    /**
     * @dev Event emitted when an auction is closed
     */
    event CloseAuctionLog(
        uint256 indexed listingId,
        address indexed highestBidder,
        uint256 quantity,
        uint256 price
    );
    /**
     * @dev Event emitted when an auction is canceld
     */
    event CancelAuctionLog(uint256 indexed listingId);
    /**
     * @dev Event emitted when a bid is placed
     */
    event BidLog(
        uint256 indexed listingId,
        address indexed bidder,
        uint256 bidPrice,
        uint256 quntity
    );

    event OfferLog(
        uint256 indexed listingId,
        address indexed offeror,
        uint256 offerPrice
    );

    /**
     * @dev Event emitted when the user withdraws her money
     */
    event Withdrawn(
        uint256 indexed listingId,
        address indexed harvester,
        uint256 value
    );

    error timeIsOver();
    error onlyOwner();
    error notApproved();
    error listingIsNotAuction();
    error listingIsAuction();
    error invalidBidPrice();
    error listingEnded();
    error listingNotEnded();
    error noZeroParameters();
    error invalidAddress();
    error onlyCreatorCanCall();
    error listingDeleted();

    /**
     * @dev Error thrown when only the creator can call a function
     */
    modifier onlyCreator(uint256 _listingId) {
        if (msg.sender != listings[_listingId].creator) {
            revert onlyCreatorCanCall();
        }
        _;
    }
    /**
     * @dev Error thrown when a listing has ended
     */
    modifier notEnded(uint256 _listingId) {
        if (listings[_listingId].ended) {
            revert listingEnded();
        }
        _;
    }
    /**
     * @dev Error thrown when a listing time is over
     */
    modifier timeIsNotOver(uint256 _listingId) {
        if (block.timestamp < listings[_listingId].end) {
            revert listingEnded();
        }
        _;
    }
    /**
     * @dev Error thrown when a listing is not auction
     */
    modifier isAuction(uint256 _listingId) {
        if (!listings[_listingId].isAuction) {
            revert listingIsNotAuction();
        }
        _;
    }
    /**
     * @dev Error thrown when a listing is auction
     */
    modifier isDirectListing(uint256 _listingId) {
        if (listings[_listingId].isAuction) {
            revert listingIsAuction();
        }
        _;
    }

    constructor(
        uint256 bidBufferBps,
        uint256 timeBuffer,
        uint256 platformFee,
        uint256 maxBps
    ) {
        PLATFORM_OWNER = msg.sender;
        PLATFORM_FEE = platformFee;
        BID_BUFFER_BPS = bidBufferBps;
        MAX_BPS = maxBps;
        TIME_BUFFER = timeBuffer;
    }

    /**
     * @dev Creates a new listing.
     * @param _tokenContract Address of the token contract
     * @param _tokenId Token ID
     * @param _paymentToken Address of the payment token
     * @param _price Listing _price
     * @param _durationUntilEnd Duration of the listing until it ends
     * @param _quantity Quantity available for sale
     * @param _isAuction Flag indicating if the listing is an auction
     */
    function createList(
        address _tokenContract,
        uint256 _tokenId,
        address _paymentToken,
        uint256 _price,
        uint256 _durationUntilEnd,
        uint256 _quantity,
        bool _isAuction
    ) external {
        if (_price == 0 || _durationUntilEnd == 0 || _quantity == 0) {
            revert noZeroParameters();
        }
        if (_paymentToken == address(0)) {
            revert invalidAddress();
        }
        address creator = msg.sender;
        TokenType tokenType = getTokenType(_tokenContract);
        _quantity = tokenType == TokenType.ERC721 ? 1 : _quantity;
        validateToken(_tokenContract, _tokenId, creator, _quantity, tokenType);
        if (_isAuction) {
            transferToken(
                _tokenContract,
                creator,
                address(this),
                _tokenId,
                _quantity,
                tokenType
            );
        }
        Listing memory newListing = Listing(
            listings.length,
            _tokenContract,
            _tokenId,
            tokenType,
            creator,
            _paymentToken,
            _price,
            block.timestamp,
            block.timestamp + _durationUntilEnd,
            _quantity,
            false,
            _isAuction
        );
        listings.push(newListing);
        emit CreatListingLog(
            newListing.id,
            creator,
            _tokenContract,
            _tokenId,
            _quantity,
            _isAuction
        );
    }

    /**
     * @dev Edits an existing listing.
     * @param _listingId Unique identifier of the listing
     * @param _paymentToken Address of the payment token
     * @param _price New listing _price
     * @param _durationUntilEnd New duration for the listing until it ends
     * @param _quantity New _quantity available for sale
     */
    function editListing(
        uint256 _listingId,
        address _paymentToken,
        uint256 _price,
        uint256 _durationUntilEnd,
        uint256 _quantity
    ) external onlyCreator(_listingId) {
        if (_price == 0 || _durationUntilEnd == 0 || _quantity == 0) {
            revert noZeroParameters();
        }
        if (_paymentToken == address(0)) {
            revert invalidAddress();
        }
        Listing memory targetListing = listings[_listingId];
        if (targetListing.tokenType == TokenType.ERC721) {
            _quantity = 1;
        }
        if (targetListing.isAuction) {
            _price = targetListing.price;
        }
        Listing memory newListing = Listing(
            _listingId,
            targetListing.tokenContract,
            targetListing.tokenId,
            targetListing.tokenType,
            targetListing.creator,
            _paymentToken,
            _price,
            targetListing.start,
            block.timestamp + _durationUntilEnd,
            _quantity,
            targetListing.isAuction,
            false
        );
        listings[_listingId] = newListing;
        if (targetListing.isAuction) {
            transferToken(
                targetListing.tokenContract,
                address(this),
                targetListing.creator,
                targetListing.tokenId,
                targetListing.quantity,
                targetListing.tokenType
            );
            validateToken(
                targetListing.tokenContract,
                targetListing.tokenId,
                targetListing.creator,
                _quantity,
                targetListing.tokenType
            );
            transferToken(
                targetListing.tokenContract,
                targetListing.creator,
                address(this),
                targetListing.tokenId,
                _quantity,
                targetListing.tokenType
            );
        }
        emit EditListingLog(
            _listingId,
            targetListing.creator,
            targetListing.tokenContract,
            targetListing.tokenId,
            targetListing.quantity
        );
    }

    /**
     * @dev Allows a user _to purchase tokens _from a listing.
     * @param _listingId Unique identifier of the listing
     * @param _quantity Quantity of tokens _to purchase
     */
    function buy(
        uint256 _listingId,
        uint256 _quantity
    )
        external
        notEnded(_listingId)
        isDirectListing(_listingId)
        timeIsNotOver(_listingId)
    {
        Listing memory targetListing = listings[_listingId];
        uint256 _totalPrice = targetListing.price * _quantity;
        targetListing.quantity -= _quantity;
        targetListing.ended = targetListing.quantity == 0;
        listings[_listingId] = targetListing;
        uint256 _platformFeeCut = (_totalPrice * PLATFORM_FEE) / MAX_BPS;
        (address _royaltyRecipient, uint256 _royaltyCut) = getRoyalty(
            targetListing.tokenContract,
            targetListing.tokenId,
            _totalPrice,
            _platformFeeCut
        );
        payout(
            msg.sender,
            targetListing.creator,
            _totalPrice,
            _platformFeeCut,
            _royaltyCut,
            _royaltyRecipient,
            targetListing.paymentToken
        );
        transferToken(
            targetListing.tokenContract,
            targetListing.creator,
            msg.sender,
            targetListing.tokenId,
            _quantity,
            targetListing.tokenType
        );
        emit BuyLog(_listingId, msg.sender, _quantity, targetListing.price);
    }

    /**
     * @dev Allows a user _to place a bid on a listing.
     * @param _listingId Unique identifier of the listing
     * @param _bidPrice Bid _price in the payment token
     * @param _quantity the number of token you want _to bid on
     */
    function bid(
        uint256 _listingId,
        uint256 _bidPrice,
        uint256 _quantity
    ) external isAuction(_listingId) timeIsNotOver(_listingId) {
        if (_bidPrice == 0 || _quantity == 0) {
            revert noZeroParameters();
        }
        Listing memory targetListing = listings[_listingId];
        if (targetListing.tokenType == TokenType.ERC721) {
            _quantity = 1;
        }
        Bid memory lastBid = bidsMap[_listingId][msg.sender];
        Bid memory newBid = Bid(msg.sender, _bidPrice, _quantity);
        Bid[] memory bidsOfListing = bids[_listingId];
        uint256 newBidPrice = newBid.bid;
        uint256 totalBidPrice = newBid.bid * newBid.quantity;
        if (bidsOfListing.length > 0) {
            Bid memory currentHighestBid = bidsOfListing[
                bidsOfListing.length - 1
            ];
            uint256 currentBidPrice = currentHighestBid.bid *
                currentHighestBid.quantity;
            if (
                totalBidPrice < currentBidPrice ||
                ((totalBidPrice - currentBidPrice) * MAX_BPS) /
                    currentBidPrice <
                BID_BUFFER_BPS
            ) {
                revert invalidBidPrice();
            }
        } else {
            if (newBidPrice < targetListing.price) {
                revert invalidBidPrice();
            }
        }
        IERC20(targetListing.paymentToken).safeTransfer(
            msg.sender,
            lastBid.bid * lastBid.quantity
        );
        bids[_listingId].push(newBid);
        bidsMap[_listingId][msg.sender] = newBid;
        if (targetListing.end - block.timestamp <= TIME_BUFFER) {
            targetListing.end += TIME_BUFFER;
        }
        listings[_listingId] = targetListing;
        checkBalanceAndAllowance(
            msg.sender,
            targetListing.paymentToken,
            _bidPrice * _quantity
        );
        IERC20(targetListing.paymentToken).safeTransferFrom(
            msg.sender,
            address(this),
            _bidPrice * _quantity
        );
        emit BidLog(_listingId, msg.sender, newBidPrice, _quantity);
    }

    /**
     * @dev Allows the creator _to close an auction listing.
     * @param _listingId Unique identifier of the listing
     */
    function closeAuction(uint256 _listingId) external isAuction(_listingId) {
        Listing memory targetListing = listings[_listingId];
        if (block.timestamp < targetListing.end) {
            revert listingNotEnded();
        }
        if (targetListing.ended) {
            revert listingEnded();
        }
        targetListing.ended = true;
        listings[_listingId] = targetListing;
        Bid[] memory listingBids = bids[_listingId];
        if (listingBids.length == 0) {
            transferToken(
                targetListing.tokenContract,
                address(this),
                targetListing.creator,
                targetListing.tokenId,
                targetListing.quantity,
                targetListing.tokenType
            );
            emit CancelAuctionLog(_listingId);
        } else {
            Bid memory highestBid = listingBids[listingBids.length - 1];
            bidsMap[_listingId][highestBid.bidder] = Bid(
                highestBid.bidder,
                0,
                0
            );
            uint256 _totalPrice = highestBid.bid * highestBid.quantity;
            uint256 _platformFeeCut = (_totalPrice * PLATFORM_FEE) / MAX_BPS;
            (address _royaltyRecipient, uint256 _royaltyCut) = getRoyalty(
                targetListing.tokenContract,
                targetListing.tokenId,
                _totalPrice,
                _platformFeeCut
            );
            payout(
                address(this),
                targetListing.creator,
                _totalPrice,
                _platformFeeCut,
                _royaltyCut,
                _royaltyRecipient,
                targetListing.paymentToken
            );
            transferToken(
                targetListing.tokenContract,
                address(this),
                highestBid.bidder,
                targetListing.tokenId,
                highestBid.quantity,
                targetListing.tokenType
            );
            if (targetListing.quantity - highestBid.quantity > 0) {
                transferToken(
                    targetListing.tokenContract,
                    address(this),
                    targetListing.creator,
                    targetListing.tokenId,
                    targetListing.quantity - highestBid.quantity,
                    targetListing.tokenType
                );
            }
            emit CloseAuctionLog(
                _listingId,
                highestBid.bidder,
                highestBid.quantity,
                highestBid.bid
            );
        }
    }

    /**
     * @dev Withdraws the user's bid _from a listing.
     * @param _listingId The ID of the listing.
     */
    function withdrawal(uint256 _listingId) external isAuction(_listingId) {
        if (!listings[_listingId].ended) {
            revert listingNotEnded();
        }
        Bid memory userBal = bidsMap[_listingId][msg.sender];
        require(
            userBal.bid > 0 && userBal.quantity > 0,
            "you have not made an bid"
        );
        bidsMap[_listingId][msg.sender] = Bid(userBal.bidder, 0, 0);
        IERC20(listings[_listingId].paymentToken).safeTransfer(
            msg.sender,
            userBal.bid * userBal.quantity
        );
        emit Withdrawn(_listingId, msg.sender, userBal.bid * userBal.quantity);
    }

    /**
     * @dev Internal function _to transfer tokens (NFTs or ERC20) _from one address _to another.
     * @param _tokenContract Address of the token contract
     * @param _from Address _from which tokens are transferred
     * @param _to Address _to which tokens are transferred
     * @param _tokenId Token ID (for ERC721) or token type ID (for ERC1155)
     * @param _quantity Quantity of tokens (for ERC1155, set _to 1 for ERC721)
     * @param _tokenType Type of token (ERC721 or ERC1155)
     */
    function transferToken(
        address _tokenContract,
        address _from,
        address _to,
        uint256 _tokenId,
        uint256 _quantity,
        TokenType _tokenType
    ) internal {
        if (_tokenType == TokenType.ERC721) {
            IERC721(_tokenContract).safeTransferFrom(_from, _to, _tokenId);
        } else {
            IERC1155(_tokenContract).safeTransferFrom(
                _from,
                _to,
                _tokenId,
                _quantity,
                ""
            );
        }
    }

    function payout(
        address _from,
        address _to,
        uint256 _amount,
        uint256 _platformFeeCut,
        uint256 _royaltyCut,
        address _royaltyRecipient,
        address _paymentToken
    ) internal {
        if (_from == address(this)) {
            IERC20(_paymentToken).safeTransfer(PLATFORM_OWNER, _platformFeeCut);
            if (_royaltyCut != 0 && _royaltyRecipient != address(0)) {
                IERC20(_paymentToken).safeTransfer(
                    _royaltyRecipient,
                    _royaltyCut
                );
            }
            IERC20(_paymentToken).safeTransfer(
                _to,
                _amount - (_platformFeeCut + _royaltyCut)
            );
        } else {
            checkBalanceAndAllowance(_from, _paymentToken, _amount);
            IERC20(_paymentToken).safeTransferFrom(
                _from,
                PLATFORM_OWNER,
                _platformFeeCut
            );
            if (_royaltyCut != 0 && _royaltyRecipient != address(0)) {
                IERC20(_paymentToken).safeTransferFrom(
                    _from,
                    _royaltyRecipient,
                    _royaltyCut
                );
            }
            IERC20(_paymentToken).safeTransferFrom(
                _from,
                _to,
                _amount - (_platformFeeCut + _royaltyCut)
            );
        }
    }

    /**
     * @dev Internal function _to retrieve royalty information for a given token.
     * @param _tokenContract Address of the token contract
     * @param _tokenId Token ID
     * @param _totalPrice Total _price of the transaction
     * @param _platformFeeCut Platform fee cut
     * @return _royaltyRecipient Address of the royalty recipient
     * @return _royaltyCut Amount of royalty
     */
    function getRoyalty(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _totalPrice,
        uint256 _platformFeeCut
    ) internal view returns (address _royaltyRecipient, uint256 _royaltyCut) {
        try
            IERC2981(_tokenContract).royaltyInfo(_tokenId, _totalPrice)
        returns (address royaltyFeeRecipient, uint256 royaltyFeeAmount) {
            if (royaltyFeeRecipient != address(0) && royaltyFeeAmount > 0) {
                require(
                    royaltyFeeAmount + _platformFeeCut <= _totalPrice,
                    "fees exceed the price"
                );
                return (royaltyFeeRecipient, royaltyFeeAmount);
            }
        } catch {}
    }

    function getListing(
        uint256 _listingId
    ) external view returns (Listing memory) {
        return (listings[_listingId]);
    }

    function getListingBids(
        uint256 _listingId
    ) external view returns (Bid[] memory) {
        return (bids[_listingId]);
    }

    function getUserBidBalance(
        uint256 _listingId,
        address _userAddress
    ) external view returns (Bid memory) {
        return (bidsMap[_listingId][_userAddress]);
    }

    /**
     * @dev Internal function _to determine the type of a token (ERC721 or ERC1155).
     * @param _contractAddress Address of the token contract
     * @return tokenType Type of token (ERC721 or ERC1155)
     */ function getTokenType(
        address _contractAddress
    ) internal view returns (TokenType tokenType) {
        if (
            IERC165(_contractAddress).supportsInterface(
                type(IERC1155).interfaceId
            )
        ) {
            tokenType = TokenType.ERC1155;
        } else if (
            IERC165(_contractAddress).supportsInterface(
                type(IERC721).interfaceId
            )
        ) {
            tokenType = TokenType.ERC721;
        } else {
            revert("token must be ERC1155 or ERC721.");
        }
    }

    /**
     * @dev Internal function _to validate token ownership and approval.
     * @param _token Address of the token contract
     * @param _tokenId Token ID (for ERC721) or token type ID (for ERC1155)
     * @param _owner Expected owner address
     * @param _quantity Quantity of tokens (for ERC1155, set _to 1 for ERC721)
     * @param _tokenType Type of token (ERC721 or ERC1155)
     */
    function validateToken(
        address _token,
        uint256 _tokenId,
        address _owner,
        uint256 _quantity,
        TokenType _tokenType
    ) internal view {
        if (_tokenType == TokenType.ERC721) {
            IERC721 token721 = IERC721(_token);
            if (_owner != token721.ownerOf(_tokenId)) {
                revert onlyOwner();
            }
            address approved = token721.getApproved(_tokenId);
            if (approved != address(this)) {
                revert notApproved();
            }
        } else {
            IERC1155 token1155 = IERC1155(_token);
            uint256 balanceOf = token1155.balanceOf(_owner, _tokenId);
            if (balanceOf >= _quantity) {
                revert onlyOwner();
            }
            bool isApprove = token1155.isApprovedForAll(_owner, address(this));
            if (!isApprove) {
                revert notApproved();
            }
        }
    }

    /**
     * @dev Internal function _to check user's balance and allowance for a payment token.
     * @param _checkAddress Address _to check
     * @param _token Address of the payment token
     * @param _price Total _price of the transaction
     */
    function checkBalanceAndAllowance(
        address _checkAddress,
        address _token,
        uint256 _price
    ) internal view {
        require(
            _price <= IERC20(_token).balanceOf(_checkAddress) &&
                _price <=
                IERC20(_token).allowance(_checkAddress, address(this)),
            ""
        );
    }
}
