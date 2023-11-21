// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
//TODO:- Rename to FU Capital
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract FULoanNFT is ERC721, IERC721Receiver, Pausable, Ownable {
    using Address for address payable;
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;

    event UpdateMarketplace(
        address indexed lastMarketplace,
        address indexed newMarketplace
    );
    event UpdateFloorPrice(uint256 indexed newFloorPrice);
    event UpdateBaseURI(string newBaseURI);
    event UpdateCurrentPrice(
        uint256 indexed nftId,
        uint256 updatedCurrentPrice
    );

    // NFT_ID -> Price_Of_NFT
    mapping(uint256 => uint256) public currentPrice;
    uint256 public floorPrice;

    string public baseURI;
    address public esketitMarketplace;

    constructor(
        string memory name,
        string memory symbol,
        address _marketplace,
        uint256 _quantity,
        string memory _uri,
        uint256 _price
    ) ERC721(name, symbol) {
        esketitMarketplace = _marketplace;
        floorPrice = _price;
        baseURI = _uri;

        _setApprovalForAll(address(this), esketitMarketplace, true);

        for (uint256 itr = 0; itr < _quantity; itr++) {
            uint256 tokenId = _tokenIdCounter.current();
            _tokenIdCounter.increment();
            _mint(address(this), tokenId);
            currentPrice[tokenId] = _price;
        }
    }

    function safeMint(uint256 _quantity) external onlyOwner {
        for (uint256 itr = 0; itr < _quantity; itr++) {
            uint256 tokenId = _tokenIdCounter.current();
            _tokenIdCounter.increment();
            _mint(address(this), tokenId);
        }
    }

    function burn(uint256[] calldata _tokenId) external onlyOwner {
        for (uint256 itr = 0; itr < _tokenId.length; itr++) {
            require(
                _isApprovedOrOwner(_msgSender(), _tokenId[itr]),
                "ERC721: caller is not token owner or approved"
            );
            _burn(_tokenId[itr]);
        }
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) public pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    ///////////////////////////
    /// NFT Price Functions ///
    ///////////////////////////

    function updateFloorPrice(uint256 _floorPrice) external onlyOwner {
        require(_floorPrice != 0, "zero price");
        require(_floorPrice != floorPrice, "same value passed");

        floorPrice = _floorPrice;

        emit UpdateFloorPrice(floorPrice);
    }

    function getCurrentPrice(uint256 _nftId) external view returns (uint256) {
        return currentPrice[_nftId];
    }

    function updateCurrentPrice(uint256 _nftId, uint256 _newPrice) external {
        require(
            _msgSender() == esketitMarketplace,
            "caller is not esketit marketplace"
        );
        require(_newPrice != 0, "zero value passed");

        currentPrice[_nftId] = _newPrice;

        emit UpdateCurrentPrice(_nftId, currentPrice[_nftId]);
    }

    ////////////////////////
    /// Update Variables ///
    ////////////////////////

    function updateMarketplaceAddress(address _marketplace) external onlyOwner {
        require(_marketplace != address(0), "zero address");
        require(_marketplace != esketitMarketplace, "same address passed");

        esketitMarketplace = _marketplace;
        _setApprovalForAll(address(this), esketitMarketplace, true);

        emit UpdateMarketplace(esketitMarketplace, _marketplace);
    }

    function updateBaseURI(string calldata _uri) external onlyOwner {
        require(bytes(_uri).length != 0, "invalid string");

        baseURI = _uri;

        emit UpdateBaseURI(baseURI);
    }

    //////////////////////////
    /// Pausable Functions ///
    //////////////////////////

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    /////////////////////////
    /// Internal Function ///
    /////////////////////////

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override whenNotPaused {
        require(
            owner() == _msgSender() || esketitMarketplace == _msgSender(),
            "neither esketit admin nor esketit marketplace"
        );
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }
}
