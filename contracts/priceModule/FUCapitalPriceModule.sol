// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract FUCapitalPriceModule {
    using SafeMath for uint256;

    address public priceModuleManager; // Address of tnphe Price Module Manager

    mapping(address => uint256) tokenPriceInEUR;
    mapping(address => bool) isSupportedToken;

    /// @dev Function to initialize priceModuleManager and curveAddressProvider.
    // function initialize() public {
    //     priceModuleManager = msg.sender;
    // }

    constructor() {
        priceModuleManager = msg.sender;
    }

    /// @dev Function to set new Price Module Manager.
    /// @param _manager Address of new Manager.
    function setManager(address _manager) external {
        require(msg.sender == priceModuleManager, "Not Authorized");
        priceModuleManager = _manager;
    }

    /// @dev Function to add a token to Price Module.
    /// @param _tokenAddress Address of the token.
    /// @param _currentPriceEUR current price of token in eur

    function addToken(
        address _tokenAddress,
        uint256 _currentPriceEUR
    ) external {
        require(msg.sender == priceModuleManager, "Not Authorized");
        tokenPriceInEUR[_tokenAddress] = _currentPriceEUR;
        isSupportedToken[_tokenAddress] = true;
    }

    /// @dev Function to add tokens to Price Module in batch.
    /// @param _tokenAddresses Address List of the tokens.
    /// @param _currentPricesEUR current price of token in eur

    function addTokenInBatches(
        address[] memory _tokenAddresses,
        uint256[] memory _currentPricesEUR
    ) external {
        require(msg.sender == priceModuleManager, "Not Authorized");
        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            tokenPriceInEUR[_tokenAddresses[i]] = _currentPricesEUR[i];
            isSupportedToken[_tokenAddresses[i]] = true;
        }
    }

    /// @dev Function to get price of a token in EUR.
    /// @param _tokenAddress Address of the token.
    function getPriceInEUR(
        address _tokenAddress
    ) public view returns (uint256) {
        require(isSupportedToken[_tokenAddress], "Token not supported");
        return (tokenPriceInEUR[_tokenAddress]);
    }

    function updatePrice(
        address _tokenAddress,
        uint256 _currentPriceEUR
    ) external {
        require(msg.sender == priceModuleManager, "Not Authorized");
        tokenPriceInEUR[_tokenAddress] = _currentPriceEUR;
    }
}
