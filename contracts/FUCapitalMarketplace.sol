// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface fuCapitalPriceModule {
    function getPriceInUSD(address) external view returns (uint256);

    function getPriceInEUR(address) external view returns (uint256);
}

interface fuLoanNFT {
    function floorPrice() external view returns (uint256);

    function getCurrentPrice(uint256 _nftId) external view returns (uint256);

    function updateCurrentPrice(uint256 _nftId, uint256 _newPrice) external;
}

contract FUCapitalMarketplace is Ownable, ReentrancyGuard {
    using Address for address payable;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /// @notice Events for the contract
    event ItemListed(
        address indexed owner,
        address indexed nft,
        uint256 tokenId,
        address payToken,
        uint256 price,
        uint96 startingTime
    );
    event ItemSold(
        address indexed seller,
        address indexed buyer,
        address indexed nft,
        uint256 tokenId,
        address payToken,
        uint256 price
    );
    event ItemUpdated(
        address indexed owner,
        address indexed nft,
        uint256 tokenId,
        address payToken,
        uint256 newPrice
    );
    event ItemCanceled(
        address indexed owner,
        address indexed nft,
        uint256 tokenId
    );
    event EsketitSell(
        address indexed _nftAddress,
        address indexed esketitUser,
        uint256 totalPrice,
        address payToken
    );
    event EsketitBuy(
        address indexed _nftAddress,
        address indexed esketitUser,
        uint256 totalPrice,
        address payToken
    );
    event UpdatePlatformFeeRecipient(
        address payable indexed platformFeeRecipient
    );
    event UpdatePlatformFee(uint16 platformFee);
    event UpdateEsketitLoanBasket(address indexed _esketitLoanBasket);
    event UpdateEsketitTreasury(address indexed esketitTreasury);
    event UpdatePayToken(address indexed payToken, bool status);
    event UpdateMaxBuyLimit(uint16 _maxBuyLimit);
    event UserAdded(address indexed _userAddress);

    /// Structure for listed items
    struct Listing {
        address payToken;
        uint96 startingTime;
        uint256 price;
    }

    bytes4 private constant INTERFACE_ID_ERC721 = 0x80ac58cd;

    ////////////////
    /// MAPPINGS ///
    ////////////////

    /// NftAddress -> Token ID -> Owner -> Listing item
    mapping(address => mapping(uint256 => mapping(address => Listing)))
        public listings;

    /// UserAddress -> Bool
    mapping(address => bool) public esketitUser;

    /// Esketit Loan Baskets
    mapping(address => bool) public esketitLoanBasket;

    /// Verified PayToken Address.
    mapping(address => bool) public payTokens;

    ///////////////////////
    /// STATE VARIABLES ///
    ///////////////////////

    /// Max buy limit in single call.
    uint16 private _maxBuyLimit;

    /// Platform Fee Or Esketit Fee.
    uint16 public platformFee;

    /// Fee Recipient Address.
    address payable public feeRecipient;

    /// Esketit treasury wallet address.
    address payable public esketitTreasury;

    address public esketitPriceModule; //TODO :- add setter

    address public payoutToken; //TODO:- add payout token setter
    /////////////////
    /// MODIFIERS ///
    /////////////////

    modifier isListed(
        address _nftAddress,
        uint256[] memory _tokenId,
        address _owner
    ) {
        for (uint256 itr = 0; itr < _tokenId.length; itr++) {
            Listing memory listing = listings[_nftAddress][_tokenId[itr]][
                _owner
            ];
            require(listing.price != 0, "not listed item");
        }
        _;
    }

    modifier notListed(
        address _nftAddress,
        uint256[] memory _tokenId,
        address _owner
    ) {
        for (uint256 itr = 0; itr < _tokenId.length; itr++) {
            Listing memory listing = listings[_nftAddress][_tokenId[itr]][
                _owner
            ];
            require(listing.price == 0, "already listed");
        }
        _;
    }

    modifier validListing(
        address _nftAddress,
        uint256[] memory _tokenId,
        address _owner
    ) {
        for (uint256 itr = 0; itr < _tokenId.length; itr++) {
            Listing memory listedItem = listings[_nftAddress][_tokenId[itr]][
                _owner
            ];
            _validOwner(_nftAddress, _tokenId[itr], _owner);
            require(_getNow() >= listedItem.startingTime, "item not buyable");
        }
        _;
    }

    constructor(
        address payable _feeRecipient,
        address payable _esketitTreasury,
        address _esketitPriceModule,
        address _payToken,
        address _payoutToken,
        uint16 _platformFee,
        uint16 _maxLimit
    ) {
        platformFee = _platformFee;
        feeRecipient = _feeRecipient;
        esketitTreasury = _esketitTreasury;
        payTokens[_payToken] = true;
        esketitPriceModule = _esketitPriceModule;
        _maxBuyLimit = _maxLimit;
        payoutToken = _payoutToken;
    }

    struct Accruals {
        uint256 deposit; // amount deposited in euro
        uint256 ab; // average balance;
        uint256 interest; //interest for average balance
        uint256 principal;
    }

    //User -> Basket -> Accruals

    mapping(address => mapping(address => Accruals)) public investorAccruals;

    //User ->Erc20 ->Balance
    mapping(address => mapping(address => uint256)) public balances;

    /// Buying from esketit loanBaskets directly.
    function buyFromEsketit(
        address _nftAddress,
        uint256[] calldata _tokenId,
        address _payToken
    ) external nonReentrant {
        /**
                Accruals storage newAccruals = investorAccruals[_user][_depositToken][
            _basket
        ];
         */

        require(esketitUser[_msgSender()], "not esketit user");
        require(payTokens[_payToken], "not verified payToken");

        require(esketitLoanBasket[_nftAddress], "not esketit nftAddress");
        require(_tokenId.length <= _maxBuyLimit, "more than buy limit");

        uint256 _priceInEUR = fuCapitalPriceModule(esketitPriceModule)
            .getPriceInEUR(_payToken);
        uint256 _priceInToken = fuLoanNFT(_nftAddress)
            .floorPrice()
            .mul(_priceInEUR)
            .div(1e4);

        uint256 _normalized;
        _normalized = (uint256(_priceInToken))
            .mul(10 ** uint256(IERC20Metadata(_payToken).decimals()))
            .div(1e4);
        /******************************************** */

        IERC20(_payToken).safeTransferFrom(
            _msgSender(),
            esketitTreasury,
            _normalized.mul(_tokenId.length)
        );

        balances[_msgSender()][_payToken] =
            balances[_msgSender()][_payToken] +
            _normalized.mul(_tokenId.length);

        for (uint256 itr = 0; itr < _tokenId.length; itr++) {
            IERC721(_nftAddress).safeTransferFrom(
                _nftAddress,
                _msgSender(),
                _tokenId[itr]
            );
        }

        emit EsketitSell(
            _nftAddress,
            _msgSender(),
            _normalized.mul(_tokenId.length),
            _payToken
        );
    }

    //TODO:- Write batch function as well. Check permissions
    function esketitPayoutInterest(address _basket) external {
        uint256 payoutTokenPrice = fuCapitalPriceModule(esketitPriceModule)
            .getPriceInEUR(payoutToken);
        IERC20(payoutToken).safeApprove(_msgSender(), 0);

        Accruals storage accruals = investorAccruals[_msgSender()][_basket];
        uint256 interest = accruals.interest; //THIS VALUE IS IN EURO

        uint256 _priceInToken = interest.mul(payoutTokenPrice).div(1e4);
        uint256 _normalized = (uint256(_priceInToken))
            .mul(10 ** uint256(IERC20Metadata(payoutToken).decimals()))
            .div(1e4);

        IERC20(payoutToken).safeApprove(_msgSender(), _normalized);
        IERC20(payoutToken).safeTransfer(_msgSender(), _normalized);
    }

    function esketitBuyBack(
        uint256[] calldata _tokenId,
        address _nftAddress,
        address _payToken,
        address _esketitUser
    ) external onlyOwner {
        uint256 _totalPrice;
        for (uint256 itr = 0; itr < _tokenId.length; itr++) {
            IERC721(_nftAddress).safeTransferFrom(
                _esketitUser,
                _nftAddress,
                _tokenId[itr]
            );
            uint256 price = fuLoanNFT(_nftAddress).getCurrentPrice(
                _tokenId[itr]
            );
            _totalPrice += price;
        }

        IERC20(_payToken).safeTransferFrom(
            esketitTreasury,
            _esketitUser,
            _totalPrice
        );

        emit EsketitBuy(_nftAddress, _esketitUser, _totalPrice, _payToken);
    }

    /// Change max purchased limit.
    function updateMaxBuyLimit(uint16 _maxLimit) external onlyOwner {
        require(_maxLimit != 0, "can't set to zero");
        require(_maxLimit != _maxBuyLimit, "same value passed");

        _maxBuyLimit = _maxLimit;

        emit UpdateMaxBuyLimit(_maxBuyLimit);
    }

    /// Add new esketit user to marketplace
    function addEsketitUser(address _userAddress) external onlyOwner {
        require(_userAddress != address(0), "zero address");
        require(!esketitUser[_userAddress], "address already exists");

        esketitUser[_userAddress] = true;

        emit UserAdded(_userAddress);
    }

    //TODO:- RECHECK LOGIC
    /**
     * Update The Platform Fee, Should be more than zero.
     * Platform fee will deduct when someone buy from marketplace.
     */
    function updatePlatformFee(uint16 _platformFee) external onlyOwner {
        require(_platformFee != 0, "can't set to zero");
        require(_platformFee != platformFee, "same value passed");

        platformFee = _platformFee;

        emit UpdatePlatformFee(_platformFee);
    }

    //TODO:- RECHECK LOGIC
    /// Change the esketit treasury wallet address.
    /// Change the fee recipient wallet address.
    function updateFeeRecipient(
        address payable _feeRecipient
    ) external onlyOwner {
        require(_feeRecipient != address(0), "zero address");
        require(_feeRecipient != feeRecipient, "same address passed");

        feeRecipient = _feeRecipient;

        emit UpdatePlatformFeeRecipient(_feeRecipient);
    }

    //TODO:- RECHECK LOGIC
    /// Change the esketit treasury wallet address.
    function updateEsketitTreasury(
        address payable _esketitTreasury
    ) external onlyOwner {
        require(_esketitTreasury != address(0), "zero address");
        require(_esketitTreasury != esketitTreasury, "same address passed");

        esketitTreasury = _esketitTreasury;

        emit UpdateEsketitTreasury(esketitTreasury);
    }

    //TODO:- RECHECK LOGIC
    /// Change the verified payToken status.
    function updatePayToken(
        address _payToken,
        bool _status
    ) external onlyOwner {
        require(_payToken != address(0), "zero address");
        require(_status != payTokens[_payToken], "same status passed");

        payTokens[_payToken] = _status;

        emit UpdatePayToken(_payToken, _status);
    }

    function updateEsketitLoanBasket(
        address _esketitLoanBasket
    ) external onlyOwner {
        require(_esketitLoanBasket != address(0), "zero address");
        require(!esketitLoanBasket[_esketitLoanBasket], "already exist");

        esketitLoanBasket[_esketitLoanBasket] = true;

        emit UpdateEsketitLoanBasket(_esketitLoanBasket);
    }

    function addAccrued(
        address _basket,
        address _user,
        uint256 _deposit,
        uint256 _ab,
        uint256 _interest
    ) external {
        require(esketitUser[_user], "not esketit user");
        //TODO :- Check if deposit token is paytoken
        Accruals storage newAccruals = investorAccruals[_user][_basket];
        newAccruals.deposit = _deposit;
        newAccruals.ab = _ab;
        newAccruals.interest = _interest;
    }

    //////////////////////////////////////
    /// Secondary Marketplace Functions///
    //////////////////////////////////////

    /// List NFT on secondary marketplace
    function listItem(
        address _nftAddress,
        uint256[] calldata _tokenId,
        address _payToken,
        uint256 _price,
        uint96 _startingTime
    ) external notListed(_nftAddress, _tokenId, _msgSender()) {
        require(esketitUser[_msgSender()], "unknown user");
        require(esketitLoanBasket[_nftAddress], "unknown address");
        require(payTokens[_payToken], "unverified payToken");

        IERC721 nft = IERC721(_nftAddress);

        require(
            nft.isApprovedForAll(_msgSender(), address(this)),
            "Not Approved For All"
        );

        for (uint256 itr = 0; itr < _tokenId.length; itr++) {
            require(
                nft.ownerOf(_tokenId[itr]) == _msgSender(),
                "not owner"
            );

            listings[_nftAddress][_tokenId[itr]][_msgSender()] = Listing(
                _payToken,
                _startingTime,
                _price
            );
            emit ItemListed(
                _msgSender(),
                _nftAddress,
                _tokenId[itr],
                _payToken,
                _price,
                _startingTime
            );
        }
    }

    function cancelListing(
        address _nftAddress,
        uint256[] calldata _tokenId
    ) external nonReentrant isListed(_nftAddress, _tokenId, _msgSender()) {
        address _owner = _msgSender();

        for (uint256 itr = 0; itr < _tokenId.length; itr++) {
            _validOwner(_nftAddress, _tokenId[itr], _owner);

            delete (listings[_nftAddress][_tokenId[itr]][_owner]);
            emit ItemCanceled(_owner, _nftAddress, _tokenId[itr]);
        }
    }

    function updateListing(
        address _nftAddress,
        uint256[] calldata _tokenId,
        address _payToken,
        uint256 _newPrice
    ) external nonReentrant isListed(_nftAddress, _tokenId, _msgSender()) {
        require(payTokens[_payToken], "unverified payToken");
        for (uint256 itr = 0; itr < _tokenId.length; itr++) {
            Listing storage listedItem = listings[_nftAddress][_tokenId[itr]][
                _msgSender()
            ];
            _validOwner(_nftAddress, _tokenId[itr], _msgSender());

            listedItem.payToken = _payToken;
            listedItem.price = _newPrice;
            emit ItemUpdated(
                _msgSender(),
                _nftAddress,
                _tokenId[itr],
                _payToken,
                _newPrice
            );
        }
    }

    function buyItem(
        address _nftAddress,
        uint256[] calldata _tokenId,
        address _owner,
        address _payToken
    )
    external
    nonReentrant
    isListed(_nftAddress, _tokenId, _owner)
    validListing(_nftAddress, _tokenId, _owner)
    {
        require(esketitUser[_msgSender()], "unknown user");

        uint256 _totalPrice = 0;
        for(uint256 itr = 0; itr < _tokenId.length; itr++){
            Listing memory listedItem = listings[_nftAddress][_tokenId[itr]][_owner];
            require(listedItem.payToken == _payToken, "payToken not same");

            _totalPrice = _totalPrice.add(listedItem.price);
        }

        _buyItem(_nftAddress, _tokenId, _owner, _totalPrice, _payToken);
    }

    function _buyItem(
        address _nftAddress,
        uint256[] memory _tokenId,
        address _owner,
        uint256 _totalPrice,
        address _payToken
    ) private {

        uint256 feeAmount = _totalPrice.mul(platformFee).div(1e3);

        IERC20(_payToken).safeTransferFrom(
            _msgSender(),
            feeRecipient,
            feeAmount
        );
        IERC20(_payToken).safeTransferFrom(
            _msgSender(),
            _owner,
            _totalPrice.sub(feeAmount)
        );

        for(uint256 itr = 0; itr < _tokenId.length; itr++){
            Listing memory listedItem = listings[_nftAddress][_tokenId[itr]][_owner];

            IERC721(_nftAddress).safeTransferFrom(_owner, _msgSender(), _tokenId[itr]);

            fuLoanNFT(_nftAddress).updateCurrentPrice(_tokenId[itr], listedItem.price);

            emit ItemSold(
                _owner,
                _msgSender(),
                _nftAddress,
                _tokenId[itr],
                listedItem.payToken,
                listedItem.price
            );
            delete (listings[_nftAddress][_tokenId[itr]][_owner]);
        }
    }

    ////////////////////////////
    /// Internal and Private ///
    ////////////////////////////

    function _getNow() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    function _validOwner(
        address _nftAddress,
        uint256 _tokenId,
        address _owner
    ) internal view {
        require(
            IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC721),
            "invalid nft address"
        );

        IERC721 nft = IERC721(_nftAddress);
        require(nft.ownerOf(_tokenId) == _owner, "not owning item");
    }
}
