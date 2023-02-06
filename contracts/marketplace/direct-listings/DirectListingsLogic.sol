// SPDX-License-Identifier: Apache-2.0
/// @author thirdweb

pragma solidity ^0.8.11;

import "./DirectListingsStorage.sol";

// ====== External imports ======
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";

// ====== Internal imports ======

import "../../extension/plugin/PlatformFeeLogic.sol";
import "../../extension/plugin/ERC2771ContextConsumer.sol";
import "../../extension/plugin/ReentrancyGuardLogic.sol";
import "../../extension/plugin/PermissionsEnumerableLogic.sol";
import { CurrencyTransferLib } from "../../lib/CurrencyTransferLib.sol";

/* 
    $$\     $$\       $$\                 $$\                         $$\       
    $$ |    $$ |      \__|                $$ |                        $$ |      
  $$$$$$\   $$$$$$$\  $$\  $$$$$$\   $$$$$$$ |$$\  $$\  $$\  $$$$$$\  $$$$$$$\  
  \_$$  _|  $$  __$$\ $$ |$$  __$$\ $$  __$$ |$$ | $$ | $$ |$$  __$$\ $$  __$$\ 
    $$ |    $$ |  $$ |$$ |$$ |  \__|$$ /  $$ |$$ | $$ | $$ |$$$$$$$$ |$$ |  $$ |
    $$ |$$\ $$ |  $$ |$$ |$$ |      $$ |  $$ |$$ | $$ | $$ |$$   ____|$$ |  $$ |
    \$$$$  |$$ |  $$ |$$ |$$ |      \$$$$$$$ |\$$$$$\$$$$  |\$$$$$$$\ $$$$$$$  |
     \____/ \__|  \__|\__|\__|       \_______| \_____\____/  \_______|\_______/ 
*/

contract DirectListingsLogic is IDirectListings, ReentrancyGuardLogic, ERC2771ContextConsumer {
    /*///////////////////////////////////////////////////////////////
                        Constants / Immutables
    //////////////////////////////////////////////////////////////*/

    /// @dev Only lister role holders can create listings, when listings are restricted by lister address.
    bytes32 private constant LISTER_ROLE = keccak256("LISTER_ROLE");
    /// @dev Only assets from NFT contracts with asset role can be listed, when listings are restricted by asset address.
    bytes32 private constant ASSET_ROLE = keccak256("ASSET_ROLE");

    /// @dev The max bps of the contract. So, 10_000 == 100 %
    uint64 public constant MAX_BPS = 10_000;

    /// @dev The address of the native token wrapper contract.
    address private immutable nativeTokenWrapper;

    /*///////////////////////////////////////////////////////////////
                            Modifier
    //////////////////////////////////////////////////////////////*/

    /// @dev Checks whether the caller has LISTER_ROLE.
    modifier onlyListerRole() {
        require(PermissionsEnumerableLogic(address(this)).hasRoleWithSwitch(LISTER_ROLE, _msgSender()), "!LISTER_ROLE");
        _;
    }

    /// @dev Checks whether the caller has ASSET_ROLE.
    modifier onlyAssetRole(address _asset) {
        require(PermissionsEnumerableLogic(address(this)).hasRoleWithSwitch(ASSET_ROLE, _asset), "!ASSET_ROLE");
        _;
    }

    /// @dev Checks whether caller is a listing creator.
    modifier onlyListingCreator(uint256 _listingId) {
        DirectListingsStorage.Data storage data = DirectListingsStorage.directListingsStorage();
        require(data.listings[_listingId].listingCreator == _msgSender(), "Marketplace: not listing creator.");
        _;
    }

    /// @dev Checks whether a listing exists.
    modifier onlyExistingListing(uint256 _listingId) {
        DirectListingsStorage.Data storage data = DirectListingsStorage.directListingsStorage();
        require(data.listings[_listingId].status == IDirectListings.Status.CREATED, "Marketplace: invalid listing.");
        _;
    }

    /*///////////////////////////////////////////////////////////////
                            Constructor logic
    //////////////////////////////////////////////////////////////*/

    constructor(address _nativeTokenWrapper) {
        nativeTokenWrapper = _nativeTokenWrapper;
    }

    /*///////////////////////////////////////////////////////////////
                            External functions
    //////////////////////////////////////////////////////////////*/

    /// @notice List NFTs (ERC721 or ERC1155) for sale at a fixed price.
    function createListing(ListingParameters calldata _params)
        external
        onlyListerRole
        onlyAssetRole(_params.assetContract)
        returns (uint256 listingId)
    {
        listingId = _getNextListingId();
        address listingCreator = _msgSender();
        TokenType tokenType = _getTokenType(_params.assetContract);

        uint128 startTime = _params.startTimestamp;
        uint128 endTime = _params.endTimestamp;
        require(startTime < endTime, "Marketplace: endTimestamp not greater than startTimestamp.");
        if (startTime < block.timestamp) {
            require(startTime + 60 minutes >= block.timestamp, "Marketplace: invalid startTimestamp.");

            startTime = uint128(block.timestamp);
            endTime = endTime == type(uint128).max
                ? endTime
                : startTime + (_params.endTimestamp - _params.startTimestamp);
        }

        _validateNewListing(_params, tokenType);

        Listing memory listing = Listing({
            listingId: listingId,
            listingCreator: listingCreator,
            assetContract: _params.assetContract,
            tokenId: _params.tokenId,
            quantity: _params.quantity,
            currency: _params.currency,
            pricePerToken: _params.pricePerToken,
            startTimestamp: startTime,
            endTimestamp: endTime,
            reserved: _params.reserved,
            tokenType: tokenType,
            status: IDirectListings.Status.CREATED
        });

        DirectListingsStorage.Data storage data = DirectListingsStorage.directListingsStorage();

        data.listings[listingId] = listing;

        emit NewListing(listingCreator, listingId, _params.assetContract, listing);
    }

    /// @notice Update parameters of a listing of NFTs.
    function updateListing(uint256 _listingId, ListingParameters memory _params)
        external
        onlyExistingListing(_listingId)
        onlyAssetRole(_params.assetContract)
        onlyListingCreator(_listingId)
    {
        DirectListingsStorage.Data storage data = DirectListingsStorage.directListingsStorage();

        address listingCreator = _msgSender();
        Listing memory listing = data.listings[_listingId];
        TokenType tokenType = _getTokenType(_params.assetContract);

        require(listing.endTimestamp > block.timestamp, "Marketplace: listing expired.");

        require(
            listing.assetContract == _params.assetContract && listing.tokenId == _params.tokenId,
            "Marketplace: cannot update what token is listed."
        );

        uint128 startTime = _params.startTimestamp;
        uint128 endTime = _params.endTimestamp;
        require(startTime < endTime, "Marketplace: endTimestamp not greater than startTimestamp.");
        require(
            listing.startTimestamp > block.timestamp ||
                (startTime == listing.startTimestamp && endTime > block.timestamp),
            "Marketplace: listing already active."
        );
        if (startTime != listing.startTimestamp && startTime < block.timestamp) {
            require(startTime + 60 minutes >= block.timestamp, "Marketplace: invalid startTimestamp.");

            startTime = uint128(block.timestamp);

            endTime = endTime == listing.endTimestamp || endTime == type(uint128).max
                ? endTime
                : startTime + (_params.endTimestamp - _params.startTimestamp);
        }

        {
            uint256 _approvedCurrencyPrice = data.currencyPriceForListing[_listingId][_params.currency];
            require(
                _approvedCurrencyPrice == 0 || _params.pricePerToken == _approvedCurrencyPrice,
                "Marketplace: price different from approved price"
            );
        }

        _validateNewListing(_params, tokenType);

        listing = Listing({
            listingId: _listingId,
            listingCreator: listingCreator,
            assetContract: _params.assetContract,
            tokenId: _params.tokenId,
            quantity: _params.quantity,
            currency: _params.currency,
            pricePerToken: _params.pricePerToken,
            startTimestamp: startTime,
            endTimestamp: endTime,
            reserved: _params.reserved,
            tokenType: tokenType,
            status: IDirectListings.Status.CREATED
        });

        data.listings[_listingId] = listing;

        emit UpdatedListing(listingCreator, _listingId, _params.assetContract, listing);
    }

    /// @notice Cancel a listing.
    function cancelListing(uint256 _listingId) external onlyExistingListing(_listingId) onlyListingCreator(_listingId) {
        DirectListingsStorage.Data storage data = DirectListingsStorage.directListingsStorage();

        data.listings[_listingId].status = IDirectListings.Status.CANCELLED;
        emit CancelledListing(_msgSender(), _listingId);
    }

    /// @notice Approve a buyer to buy from a reserved listing.
    function approveBuyerForListing(
        uint256 _listingId,
        address _buyer,
        bool _toApprove
    ) external onlyExistingListing(_listingId) onlyListingCreator(_listingId) {
        DirectListingsStorage.Data storage data = DirectListingsStorage.directListingsStorage();

        require(data.listings[_listingId].reserved, "Marketplace: listing not reserved.");

        data.isBuyerApprovedForListing[_listingId][_buyer] = _toApprove;

        emit BuyerApprovedForListing(_listingId, _buyer, _toApprove);
    }

    /// @notice Approve a currency as a form of payment for the listing.
    function approveCurrencyForListing(
        uint256 _listingId,
        address _currency,
        uint256 _pricePerTokenInCurrency
    ) external onlyExistingListing(_listingId) onlyListingCreator(_listingId) {
        DirectListingsStorage.Data storage data = DirectListingsStorage.directListingsStorage();

        Listing memory listing = data.listings[_listingId];
        require(
            _currency != listing.currency || _pricePerTokenInCurrency == listing.pricePerToken,
            "Marketplace: approving listing currency with different price."
        );
        require(
            data.currencyPriceForListing[_listingId][_currency] != _pricePerTokenInCurrency,
            "Marketplace: price unchanged."
        );

        data.currencyPriceForListing[_listingId][_currency] = _pricePerTokenInCurrency;

        emit CurrencyApprovedForListing(_listingId, _currency, _pricePerTokenInCurrency);
    }

    /// @notice Buy NFTs from a listing.
    function buyFromListing(
        uint256 _listingId,
        address _buyFor,
        uint256 _quantity,
        address _currency,
        uint256 _expectedTotalPrice
    ) external payable nonReentrant onlyExistingListing(_listingId) {
        DirectListingsStorage.Data storage data = DirectListingsStorage.directListingsStorage();

        Listing memory listing = data.listings[_listingId];
        address buyer = _msgSender();

        require(!listing.reserved || data.isBuyerApprovedForListing[_listingId][buyer], "buyer not approved");
        require(_quantity > 0 && _quantity <= listing.quantity, "Buying invalid quantity");
        require(
            block.timestamp < listing.endTimestamp && block.timestamp >= listing.startTimestamp,
            "not within sale window."
        );

        require(
            _validateOwnershipAndApproval(
                listing.listingCreator,
                listing.assetContract,
                listing.tokenId,
                _quantity,
                listing.tokenType
            ),
            "Marketplace: not owner or approved tokens."
        );

        uint256 targetTotalPrice;

        if (data.currencyPriceForListing[_listingId][_currency] > 0) {
            targetTotalPrice = _quantity * data.currencyPriceForListing[_listingId][_currency];
        } else {
            require(_currency == listing.currency, "Paying in invalid currency.");
            targetTotalPrice = _quantity * listing.pricePerToken;
        }

        require(targetTotalPrice == _expectedTotalPrice, "Unexpected total price");

        // Check: buyer owns and has approved sufficient currency for sale.
        if (_currency == CurrencyTransferLib.NATIVE_TOKEN) {
            require(msg.value == targetTotalPrice, "Marketplace: msg.value must exactly be the total price.");
        } else {
            _validateERC20BalAndAllowance(buyer, _currency, targetTotalPrice);
        }

        if (listing.quantity == _quantity) {
            data.listings[_listingId].status = IDirectListings.Status.COMPLETED;
        }
        data.listings[_listingId].quantity -= _quantity;

        _payout(buyer, listing.listingCreator, _currency, targetTotalPrice, listing);
        _transferListingTokens(listing.listingCreator, _buyFor, _quantity, listing);

        emit NewSale(
            listing.listingCreator,
            listing.listingId,
            listing.assetContract,
            listing.tokenId,
            buyer,
            _quantity,
            targetTotalPrice
        );
    }

    /*///////////////////////////////////////////////////////////////
                            View functions
    //////////////////////////////////////////////////////////////*/

    /**
     *  @notice Returns the total number of listings created.
     *  @dev At any point, the return value is the ID of the next listing created.
     */
    function totalListings() external view returns (uint256) {
        DirectListingsStorage.Data storage data = DirectListingsStorage.directListingsStorage();
        return data.totalListings;
    }

    /// @notice Returns whether a buyer is approved for a listing.
    function isBuyerApprovedForListing(uint256 _listingId, address _buyer) external view returns (bool) {
        DirectListingsStorage.Data storage data = DirectListingsStorage.directListingsStorage();
        return data.isBuyerApprovedForListing[_listingId][_buyer];
    }

    /// @notice Returns whether a currency is approved for a listing.
    function isCurrencyApprovedForListing(uint256 _listingId, address _currency) external view returns (bool) {
        DirectListingsStorage.Data storage data = DirectListingsStorage.directListingsStorage();
        return data.currencyPriceForListing[_listingId][_currency] > 0;
    }

    /// @notice Returns the price per token for a listing, in the given currency.
    function currencyPriceForListing(uint256 _listingId, address _currency) external view returns (uint256) {
        DirectListingsStorage.Data storage data = DirectListingsStorage.directListingsStorage();

        if (data.currencyPriceForListing[_listingId][_currency] == 0) {
            revert("Currency not approved for listing");
        }

        return data.currencyPriceForListing[_listingId][_currency];
    }

    /// @notice Returns all non-cancelled listings.
    function getAllListings(uint256 _startId, uint256 _endId) external view returns (Listing[] memory _allListings) {
        DirectListingsStorage.Data storage data = DirectListingsStorage.directListingsStorage();

        require(_startId <= _endId && _endId < data.totalListings, "invalid range");

        _allListings = new Listing[](_endId - _startId + 1);

        for (uint256 i = _startId; i <= _endId; i += 1) {
            _allListings[i - _startId] = data.listings[i];
        }
    }

    /**
     *  @notice Returns all valid listings between the start and end Id (both inclusive) provided.
     *          A valid listing is where the listing creator still owns and has approved Marketplace
     *          to transfer the listed NFTs.
     */
    function getAllValidListings(uint256 _startId, uint256 _endId)
        external
        view
        returns (Listing[] memory _validListings)
    {
        DirectListingsStorage.Data storage data = DirectListingsStorage.directListingsStorage();

        require(_startId <= _endId && _endId < data.totalListings, "invalid range");

        Listing[] memory _listings = new Listing[](_endId - _startId + 1);
        uint256 _listingCount;

        for (uint256 i = _startId; i <= _endId; i += 1) {
            _listings[i - _startId] = data.listings[i];
            if (_validateExistingListing(_listings[i - _startId])) {
                _listingCount += 1;
            }
        }

        _validListings = new Listing[](_listingCount);
        uint256 index = 0;
        uint256 count = _listings.length;
        for (uint256 i = 0; i < count; i += 1) {
            if (_validateExistingListing(_listings[i])) {
                _validListings[index++] = _listings[i];
            }
        }
    }

    /// @notice Returns a listing at a particular listing ID.
    function getListing(uint256 _listingId) external view returns (Listing memory listing) {
        DirectListingsStorage.Data storage data = DirectListingsStorage.directListingsStorage();

        listing = data.listings[_listingId];
    }

    /*///////////////////////////////////////////////////////////////
                            Internal functions
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns the next listing Id.
    function _getNextListingId() internal returns (uint256 id) {
        DirectListingsStorage.Data storage data = DirectListingsStorage.directListingsStorage();

        id = data.totalListings;
        data.totalListings += 1;
    }

    /// @dev Returns the interface supported by a contract.
    function _getTokenType(address _assetContract) internal view returns (TokenType tokenType) {
        if (IERC165(_assetContract).supportsInterface(type(IERC1155).interfaceId)) {
            tokenType = TokenType.ERC1155;
        } else if (IERC165(_assetContract).supportsInterface(type(IERC721).interfaceId)) {
            tokenType = TokenType.ERC721;
        } else {
            revert("Marketplace: listed token must be ERC1155 or ERC721.");
        }
    }

    /// @dev Checks whether the listing creator owns and has approved marketplace to transfer listed tokens.
    function _validateNewListing(ListingParameters memory _params, TokenType _tokenType) internal view {
        require(_params.quantity > 0, "Marketplace: listing zero quantity.");
        require(_params.quantity == 1 || _tokenType == TokenType.ERC1155, "Marketplace: listing invalid quantity.");

        require(
            _validateOwnershipAndApproval(
                _msgSender(),
                _params.assetContract,
                _params.tokenId,
                _params.quantity,
                _tokenType
            ),
            "Marketplace: not owner or approved tokens."
        );
    }

    /// @dev Checks whether the listing exists, is active, and if the lister has sufficient balance.
    function _validateExistingListing(Listing memory _targetListing) internal view returns (bool isValid) {
        isValid =
            _targetListing.startTimestamp <= block.timestamp &&
            _targetListing.endTimestamp > block.timestamp &&
            _targetListing.status == IDirectListings.Status.CREATED &&
            _validateOwnershipAndApproval(
                _targetListing.listingCreator,
                _targetListing.assetContract,
                _targetListing.tokenId,
                _targetListing.quantity,
                _targetListing.tokenType
            );
    }

    /// @dev Validates that `_tokenOwner` owns and has approved Marketplace to transfer NFTs.
    function _validateOwnershipAndApproval(
        address _tokenOwner,
        address _assetContract,
        uint256 _tokenId,
        uint256 _quantity,
        TokenType _tokenType
    ) internal view returns (bool isValid) {
        address market = address(this);

        if (_tokenType == TokenType.ERC1155) {
            isValid =
                IERC1155(_assetContract).balanceOf(_tokenOwner, _tokenId) >= _quantity &&
                IERC1155(_assetContract).isApprovedForAll(_tokenOwner, market);
        } else if (_tokenType == TokenType.ERC721) {
            isValid =
                IERC721(_assetContract).ownerOf(_tokenId) == _tokenOwner &&
                (IERC721(_assetContract).getApproved(_tokenId) == market ||
                    IERC721(_assetContract).isApprovedForAll(_tokenOwner, market));
        }
    }

    /// @dev Validates that `_tokenOwner` owns and has approved Markeplace to transfer the appropriate amount of currency
    function _validateERC20BalAndAllowance(
        address _tokenOwner,
        address _currency,
        uint256 _amount
    ) internal view {
        require(
            IERC20(_currency).balanceOf(_tokenOwner) >= _amount &&
                IERC20(_currency).allowance(_tokenOwner, address(this)) >= _amount,
            "!BAL20"
        );
    }

    /// @dev Transfers tokens listed for sale in a direct or auction listing.
    function _transferListingTokens(
        address _from,
        address _to,
        uint256 _quantity,
        Listing memory _listing
    ) internal {
        if (_listing.tokenType == TokenType.ERC1155) {
            IERC1155(_listing.assetContract).safeTransferFrom(_from, _to, _listing.tokenId, _quantity, "");
        } else if (_listing.tokenType == TokenType.ERC721) {
            IERC721(_listing.assetContract).safeTransferFrom(_from, _to, _listing.tokenId, "");
        }
    }

    /// @dev Pays out stakeholders in a sale.
    function _payout(
        address _payer,
        address _payee,
        address _currencyToUse,
        uint256 _totalPayoutAmount,
        Listing memory _listing
    ) internal {
        (address platformFeeRecipient, uint16 platformFeeBps) = PlatformFeeLogic(address(this)).getPlatformFeeInfo();
        uint256 platformFeeCut = (_totalPayoutAmount * platformFeeBps) / MAX_BPS;

        uint256 royaltyCut;
        address royaltyRecipient;

        // Distribute royalties. See Sushiswap's https://github.com/sushiswap/shoyu/blob/master/contracts/base/BaseExchange.sol#L296
        try IERC2981(_listing.assetContract).royaltyInfo(_listing.tokenId, _totalPayoutAmount) returns (
            address royaltyFeeRecipient,
            uint256 royaltyFeeAmount
        ) {
            if (royaltyFeeRecipient != address(0) && royaltyFeeAmount > 0) {
                require(royaltyFeeAmount + platformFeeCut <= _totalPayoutAmount, "fees exceed the price");
                royaltyRecipient = royaltyFeeRecipient;
                royaltyCut = royaltyFeeAmount;
            }
        } catch {}

        // Distribute price to token owner
        address _nativeTokenWrapper = nativeTokenWrapper;

        CurrencyTransferLib.transferCurrencyWithWrapper(
            _currencyToUse,
            _payer,
            platformFeeRecipient,
            platformFeeCut,
            _nativeTokenWrapper
        );
        CurrencyTransferLib.transferCurrencyWithWrapper(
            _currencyToUse,
            _payer,
            royaltyRecipient,
            royaltyCut,
            _nativeTokenWrapper
        );
        CurrencyTransferLib.transferCurrencyWithWrapper(
            _currencyToUse,
            _payer,
            _payee,
            _totalPayoutAmount - (platformFeeCut + royaltyCut),
            _nativeTokenWrapper
        );
    }
}
