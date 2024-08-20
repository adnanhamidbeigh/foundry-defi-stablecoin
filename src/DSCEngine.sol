// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DecentralisedStableCoin} from "src/DecentralisedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
/**
 * @title DSC Engine
 * @author Adnan Hamid
 * @notice This contract makes token maintain 1 token == 1$ peg
 * This stable coin has properties:
 * - Exogenous Collateral
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral <= the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */

contract DSCEngine is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    /*//////////////////////////////////////////////////////////////
                             STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralised

    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DscMinted;

    address[] private s_collateralTokens;

    DecentralisedStableCoin private immutable i_dsc;
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemer, address indexed token, uint256 indexed amount);
    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }
    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        // USD PriceFeeds
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralisedStableCoin(dscAddress);
    }
    ///////////////////////////////
    // External Functions   //////
    /**
     *
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param _amountCollateral   The amount of collateral to deposit
     * @param _amountDscToMint  The amount of DSC to mint
     * @notice This function is used to deposit collateral and mint DSC in one transaction
     */

    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 _amountCollateral,
        uint256 _amountDscToMint
    ) external {
        // 1. Deposit Collateral
        depositCollateral(tokenCollateralAddress, _amountCollateral);
        // 2. Mint DSC
        mintDSC(_amountDscToMint);
    }

    /**
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param _amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 _amountCollateral)
        public
        moreThanZero(_amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += _amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, _amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), _amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }
    /**
     *
     * @param _amountDscToMint The amount of DSC to mint
     * @notice Caller must have more collateral deposited than the minimum threshold
     * @notice follows CEI
     */

    function mintDSC(uint256 _amountDscToMint) public moreThanZero(_amountDscToMint) nonReentrant {
        s_DscMinted[msg.sender] += _amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, _amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function reedeemCollateralForDSC() external {}
    // 1. Check health factor is greater than 1
    // 2. Check health factor is greater than 1 after reedeeming
    function reedeemCollateral(address tokenCollateralAddress, uint256 _amountCollateral)
        external
        nonReentrant
        moreThanZero(_amountCollateral)
    {
        // CEI
        s_collateralDeposited[msg.sender][tokenCollateralAddress] -= _amountCollateral;
        emit CollateralRedeemed(msg.sender, tokenCollateralAddress, _amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(msg.sender, _amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();            
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDSC() external {}

    /**
     *  If you are undercollateralised, any user can pay you amount of dsc and they inturn get all your collateral
     *  Initially: 1eth -> $100[1 DSC = 1ETH]
     *           you bought DSC worth $70
     * after some time
     *          1eth -> $50
     *          DSC -> $70
     * ---------------UnderCollateralised----------------------------
     * Another user can pay you DSC worth $70 and inturn get your eth worth $50 at discount
     *
     */
    function liquidate() external {}

    function getHealthFactor() external view {}
    /*//////////////////////////////////////////////////////////////
                     PRIVATE AND INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 _totalDscMinted, uint256 _totalCollateralValueInUsd)
    {
        _totalDscMinted = s_DscMinted[user];
        _totalCollateralValueInUsd = getAccountCollateralValue(user);
    }
    /**
     *
     * @param user The address of the user who's health factor is to be calculated
     * @return How close user is to liquidation
     *
     */

    function _healthFactor(address user) private view returns (uint256) {
        // total dsc minted
        // total collateral value
        // total collateral value > total dsc minted good hf
        (uint256 totalDscMinted, uint256 totalCollateralValue) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (totalCollateralValue * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }
    // Check Collateral greater than dsc minted

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }
    /*//////////////////////////////////////////////////////////////
                       PUBLIC EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}
