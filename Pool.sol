// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./TokenPlus.sol";

///@title Pool contract for Borb Game
///@notice it rules all transfers and rewards in stablecoins and mints tokens (TokenPlus) for investors
contract Pool is ReentrancyGuard, Ownable {
    uint256 public constant MIN_USDT_PRICE = 100; //read as 1,00
    ///@notice count of allowed assets
    uint8 public allowedAssetsCount;

    struct Asset {
        string name;
        ERC20 stablecoin;
        TokenPlus tokenPlus;
        uint256 blockedStablecoinCount;
        uint256 totalStablecoinInvested;
        mapping(address => uint256) balances;
    }

    ///@notice allowed assets data by it number
    mapping(uint8 => Asset) public allowedAssets;

    ///@notice the address whithc will receive fees
    address public house;

    ///@notice rises when Buy price of Token+ has been changedd
    ///@param assetId id of stablecoin asset
    ///@param price new price
    ///@param changedAt time when price was changedd
    event BuyPriceChanged(
        uint8 indexed assetId,
        uint256 indexed price,
        uint256 changedAt
    );
    ///@notice rises when Sell price of Token+ has been changedd
    ///@param assetId id of stablecoin asset
    ///@param price new price
    ///@param changedAt time when price was changedd
    event SellPriceChanged(
        uint8 indexed assetId,
        uint256 indexed price,
        uint256 changedAt
    );
    ///@notice rises when User add investment
    ///@param user address of user who made investment
    ///@param amount amount of investment
    ///@param investedAt time when investment was added
    event InvestmentAdded(
        address indexed user,
        uint256 indexed amount,
        uint256 investedAt
    );
    ///@notice rises when User withdraw his reward
    ///@param user address of user who withdraws
    ///@param amount amount of withdraw
    ///@param investedAt time when investment was withdrawed
    event Withdrawed(
        address indexed user,
        uint256 indexed amount,
        uint256 investedAt
    );
    ///@notice rises when User earns reward from his referal bet
    ///@param betId id of bet that earns reward
    ///@param from address who make bet
    ///@param to address who receive reward
    ///@param amount amount of reward
    ///@param assetId id of stablecoin asset
    event ReferalRewardEarned(
        uint256 indexed betId,
        address indexed from,
        address indexed to,
        uint256 amount,
        uint8 assetId
    );

    error StablecoinIsAllreadyAddedError();
    error NotEnoughtTokenPlusBalanceError();
    error NotEnoughtPoolBalanceError();
    error MinimumAmountError();

    constructor(address _house) {
        house = _house;
    }

    ///@notice Adds new stablecoin
    function addAsset(address _stablecoinAddress) external onlyOwner {
        ERC20 stablecoin = ERC20(_stablecoinAddress);
        for (uint8 i = 0; i < allowedAssetsCount; ) {
            if (
                keccak256(bytes(allowedAssets[i].name)) ==
                keccak256(bytes(stablecoin.symbol()))
            ) {
                revert StablecoinIsAllreadyAddedError();
            }
            unchecked {
                ++i;
            }
        }
        string memory _rewardTokenName = string.concat(
            stablecoin.symbol(),
            "+"
        );
        string memory _rewardTokenSymbol = _rewardTokenName;
        TokenPlus tokenPlus = new TokenPlus(
            _rewardTokenName,
            _rewardTokenSymbol
        );

        createNewAsset(stablecoin.symbol(), stablecoin, tokenPlus);

        allowedAssetsCount++;
    }

    ///@notice creates new asset
    ///@return asset data
    function createNewAsset(
        string memory _symbol,
        ERC20 _stablecoin,
        TokenPlus _tokenPlus
    ) private returns (Asset storage) {
        Asset storage _newAsset = allowedAssets[allowedAssetsCount];
        _newAsset.name = _symbol;
        _newAsset.stablecoin = _stablecoin;
        _newAsset.tokenPlus = _tokenPlus;

        allowedAssetsCount++;
        return _newAsset;
    }

    ///@notice Gets allowed stablecoins
    ///@return array of allowed stablecoins names
    function getAllowedAssets() public view returns (string[] memory) {
        string[] memory allowedNames = new string[](allowedAssetsCount);
        for (uint8 i = 0; i < allowedAssetsCount; i++) {
            allowedNames[i] = allowedAssets[i].name;
        }
        return allowedNames;
    }

    ///@notice gets asset(stablecoin) address by its name
    ///@param _name stablecoin name, USDC for example
    function getAssetAddress(string calldata _name)
        public
        view
        returns (address)
    {
        for (uint8 i = 0; i < allowedAssetsCount; i++) {
            if (
                keccak256(bytes(allowedAssets[i].name)) ==
                keccak256(bytes(_name))
            ) {
                return address(allowedAssets[i].stablecoin);
            }
        }
        return address(0);
    }

    ///@notice Gets token+ address by stablecoin name
    ///@param _name stablecoin name, USDC for example
    ///@return address of stablecoin asset
    function getAssetTokenPlusAddress(string calldata _name)
        public
        view
        returns (address)
    {
        for (uint8 i = 0; i < allowedAssetsCount; i++) {
            if (
                keccak256(bytes(allowedAssets[i].name)) ==
                keccak256(bytes(_name))
            ) {
                return address(allowedAssets[i].tokenPlus);
            }
        }
        return address(0);
    }

    ///@notice function that checks is balance in selected stablecoin of pool enought for pay this bet in case of user wins
    ///@param _amount amount in stablecoin
    ///@param _assetId id of stablecoin asset
    ///@return true if enought, else false
    function poolBalanceEnough(uint256 _amount, uint8 _assetId)
        external
        view
        returns (bool)
    {
        return
            allowedAssets[_assetId].stablecoin.balanceOf(address(this)) -
                allowedAssets[_assetId].blockedStablecoinCount >=
            _amount;
    }

    ///@notice function that checks is balance in selected stablecoin of user enought for pay for this bet
    ///@notice _player address of player
    ///@param _amount amount in stablecoin
    ///@param _assetId id of stablecoin asset
    ///@return true if enought, else false
    function userBalanceEnough(
        address _player,
        uint256 _amount,
        uint8 _assetId
    ) external view returns (bool) {
        return allowedAssets[_assetId].stablecoin.balanceOf(_player) >= _amount;
    }

    ///@notice this function is calling by Game contract when user makes bet; it calculates fee and transfer and locks stablecoins
    ///@param _amount amount of bet in selected stablecoin asset
    ///@param _potentialReward potential reward in stablecoins
    ///@param _from address of user that makes bet
    ///@param _assetId id of stablecoin asset
    function makeBet(
        uint256 _amount,
        uint256 _potentialReward,
        address _from,
        uint8 _assetId
    ) external onlyOwner {
        uint256 houseFee = (_potentialReward * 100) / 10000;
        allowedAssets[_assetId].blockedStablecoinCount +=
            _potentialReward +
            houseFee;
        allowedAssets[_assetId].stablecoin.transferFrom(
            _from,
            address(this),
            _amount
        );
    }

    ///@notice Game contract calls this function in case of victory. We transfer the specified amount to the player and distribute the commission
    ///@param _betId id of bet
    ///@param _amount amount of reward to transfer (potentialReward value)
    ///@param _to address of reward receiver
    ///@param _ref address of referal reward for this bet
    ///@param _assetId id of stablecoin asset
    function transferReward(
        uint256 _betId,
        uint256 _amount,
        address _to,
        address _ref,
        uint8 _assetId
    ) external onlyOwner nonReentrant {
        uint256 houseFee = (_amount * 100) / 10000;
        if (
            allowedAssets[_assetId].stablecoin.balanceOf(address(this)) >=
            _amount
        ) {
            allowedAssets[_assetId].blockedStablecoinCount -= (_amount +
                houseFee);
            allowedAssets[_assetId].stablecoin.transfer(_to, _amount);
            if (_ref != address(0) && houseFee / 2 != 0) {
                allowedAssets[_assetId].balances[house] += houseFee / 2;
                allowedAssets[_assetId].balances[_ref] += houseFee / 2;
                emit ReferalRewardEarned(
                    _betId,
                    _to,
                    _ref,
                    houseFee / 2,
                    _assetId
                );
            } else {
                allowedAssets[_assetId].balances[house] += houseFee;
            }
        } else {
            revert NotEnoughtPoolBalanceError();
        }
    }

    ///@notice We call this function in case of loss
    ///@param _betId id of bet
    ///@param _amount amount of reward to unlock (potentialReward value)
    ///@param _user address of reward receiver
    ///@param _ref address of referal reward for this bet
    ///@param _assetId id of stablecoin asset
    function unlock(
        uint256 _betId,
        uint256 _amount,
        address _user,
        address _ref,
        uint8 _assetId
    ) external onlyOwner {
        uint256 houseFee = (_amount * 100) / 10000;
        allowedAssets[_assetId].blockedStablecoinCount -= (_amount + houseFee);
        if (_ref != address(0) && houseFee / 2 != 0) {
            allowedAssets[_assetId].balances[house] += houseFee / 2;
            allowedAssets[_assetId].balances[_ref] += houseFee / 2;
            emit ReferalRewardEarned(
                _betId,
                _user,
                _ref,
                houseFee / 2,
                _assetId
            );
        } else {
            allowedAssets[_assetId].balances[house] += houseFee;
        }
    }

    ///@notice collects refferal reward for msg.sender in selected asset
    ///@param _assetId id of stablecoin asset
    function claimReward(uint8 _assetId) external {
        if (
            allowedAssets[_assetId].balances[msg.sender] -
                allowedAssets[_assetId].blockedStablecoinCount >
            0
        ) {
            uint256 amountToWithdraw = allowedAssets[_assetId].balances[
                msg.sender
            ];
            allowedAssets[_assetId].balances[msg.sender] = 0;
            allowedAssets[_assetId].stablecoin.transfer(
                msg.sender,
                amountToWithdraw
            );
        }
    }

    ///@notice Gets referal balances
    ///@param _assetId id of stablecoin asset
    ///@param _addr ref address
    ///@return balance of referal
    function referalBalanceOf(uint8 _assetId, address _addr)
        public
        view
        returns (uint256)
    {
        return allowedAssets[_assetId].balances[_addr];
    }

    ///@notice Gets the price to buy the Token+. If the price is too low, then sets the minimum
    ///@param _assetId id of stablecoin asset
    ///@return buy price
    function getTokenPlusBuyPrice(uint8 _assetId)
        public
        view
        returns (uint256)
    {
        uint256 currentFreePoolBalance = allowedAssets[_assetId]
            .stablecoin
            .balanceOf(address(this)) -
            allowedAssets[_assetId].blockedStablecoinCount;
        if (
            allowedAssets[_assetId].totalStablecoinInvested == 0 ||
            currentFreePoolBalance == 0 ||
            allowedAssets[_assetId].tokenPlus.totalSupply() == 0
        ) {
            return MIN_USDT_PRICE;
        }
        uint256 price = (currentFreePoolBalance * 100) /
            allowedAssets[_assetId].totalStablecoinInvested;
        return price < MIN_USDT_PRICE ? MIN_USDT_PRICE : price;
    }

    ///@notice Gets the price to sell the token.
    ///@param _assetId id of stablecoin asset
    ///@return sell price
    function getTokenPlusSellPrice(uint8 _assetId)
        public
        view
        returns (uint256)
    {
        if (allowedAssets[_assetId].totalStablecoinInvested == 0) {
            return MIN_USDT_PRICE;
        }
        uint256 currentFreePoolBalance = allowedAssets[_assetId]
            .stablecoin
            .balanceOf(address(this)) -
            allowedAssets[_assetId].blockedStablecoinCount;
        return
            (currentFreePoolBalance * 100) /
            allowedAssets[_assetId].totalStablecoinInvested;
    }

    ///@notice Deposit funds to the pool account, you can deposit from one usdt or 1*10**6
    ///@param _assetId id of stablecoin asset
    ///@param _amount to deposit in stablecoins
    function makeDeposit(uint8 _assetId, uint256 _amount) external {
        uint256 tokenPlusToMintCount = (_amount * 100) /
            getTokenPlusBuyPrice(_assetId);
        if (_amount < 1 * 10**6 || tokenPlusToMintCount == 0) {
            revert MinimumAmountError();
        }
        allowedAssets[_assetId].tokenPlus.mint(
            msg.sender,
            tokenPlusToMintCount
        );
        allowedAssets[_assetId].totalStablecoinInvested += _amount;
        allowedAssets[_assetId].stablecoin.transferFrom(
            msg.sender,
            address(this),
            _amount
        );
        uint256 bp = getTokenPlusBuyPrice(_assetId);
        emit BuyPriceChanged(_assetId, bp, block.timestamp);
        emit InvestmentAdded(msg.sender, _amount * bp, block.timestamp);
    }

    ///@notice Withdraw the specified amount of USD
    ///@param _assetId id of stablecoin asset
    ///@param _tokenPlusAmount amount of Token+ that will be exchange to stablecoins
    function withdraw(uint8 _assetId, uint256 _tokenPlusAmount)
        external
        nonReentrant
    {
        if (
            allowedAssets[_assetId].tokenPlus.balanceOf(msg.sender) <
            _tokenPlusAmount
        ) {
            revert NotEnoughtTokenPlusBalanceError();
        }
        uint256 usdToWithdraw = (_tokenPlusAmount *
            getTokenPlusSellPrice(_assetId)) / 100;
        if (
            allowedAssets[_assetId].stablecoin.balanceOf(address(this)) <
            usdToWithdraw
        ) {
            revert NotEnoughtPoolBalanceError();
        }
        allowedAssets[_assetId].totalStablecoinInvested -= _tokenPlusAmount; //because we have a price of 1 to 1, so we can fix it
        allowedAssets[_assetId].tokenPlus.burn(msg.sender, _tokenPlusAmount);
        allowedAssets[_assetId].stablecoin.transfer(msg.sender, usdToWithdraw);

        emit SellPriceChanged(
            _assetId,
            getTokenPlusSellPrice(_assetId),
            block.timestamp
        );
        emit Withdrawed(msg.sender, usdToWithdraw, block.timestamp);
    }
}
