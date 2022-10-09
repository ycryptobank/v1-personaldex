// SPDX-License-Identifier: agpl-3.0


pragma solidity ^0.8.12;

import "./CurciferAsset.sol";
import "./utils/SafeERC20.sol";
import "./utils/Ownable.sol";

error UnknownAssetOwner();
error expiredOrNoSubscription();
error noSubscriptionExpired();
error NotEnoughAllowanceToPaySubcriptionFee(uint requiredAllowance);
error NotEnoughBalanceToPaySubscriptionFee(uint balance);

contract CurciferAssetList is Ownable {
	using SafeERC20 for IERC20;

	event AssetOwnerError(
		uint errorStatus
	);

	event AssetSubscriptionSuccess(
		bool subStatus
	);

	event PaidSubcription(
		uint256 timestamp
	);

	uint256 private subscriptionPeriod = 4 weeks; // need to subscribe 1 month to trade

	mapping(address => address) public assetList;
	mapping(address => uint256) public exchangeAccountExpirationList;

	address[] private providerList;
	address[] private feeTokenList;
	uint256[] private feePriceList;
	uint256 private nonce;
	uint256 private contractFee = 0.01 ether;

	function createNewOrder(
		address _providerTokenAddress, 
		address _desiredTokenAddress, 
		uint256 _providerTokenQuantity,
		uint256 _providerTokenRemainingQuantity,
		uint256 _desiredTokenQuantity,
		uint256 _desiredTokenRemainingQuantity,
		uint256 _indexSelectionFee,
		uint256 _chainNetworkDesiredToken,
		uint256 _chainNetworkProviderToken
		) public
	{
		createNewAsset();

		ICurciferAsset asset = ICurciferAsset(assetList[msg.sender]);

		address _feeToken = feeTokenList[_indexSelectionFee];
		uint256 _feePrice = feePriceList[_indexSelectionFee];

		asset.addOrder(
			_providerTokenAddress, 
			_desiredTokenAddress, 
			_providerTokenQuantity, 
			_providerTokenRemainingQuantity, 
			_desiredTokenQuantity, 
			_desiredTokenRemainingQuantity,
			_chainNetworkDesiredToken,
			_chainNetworkProviderToken,
			createOrderId(),
			_feeToken,
			_feePrice
			);
	}

	function createNewAsset() public {
		uint256 currentExchangeAccountExpiration = exchangeAccountExpirationList[msg.sender];
		bool isSubscribed = currentExchangeAccountExpiration > 0 && currentExchangeAccountExpiration >= block.timestamp;
		if (!isSubscribed) {
			revert expiredOrNoSubscription();
		}
		
		address selectedAsset = assetList[msg.sender];
		if (selectedAsset == address(0)) {
			address _selectedAsset = address(new CurciferAsset(msg.sender, address(this), _owner));
			assetList[msg.sender] = _selectedAsset;
			providerList.push(msg.sender);
		}
	}

	function customerTrading(address _assetOwner, uint _orderId, uint _soldQuantity, uint _receivedQuantity) public {
		uint256 currentExchangeAccountExpiration = exchangeAccountExpirationList[msg.sender];
		bool isSubscribed = currentExchangeAccountExpiration > 0 && currentExchangeAccountExpiration >= block.timestamp;
		if (!isSubscribed) {
			revert expiredOrNoSubscription();
		}
		
		address selectedAsset = assetList[_assetOwner];
		if (selectedAsset == address(0)) {
			emit AssetOwnerError(1);
			revert UnknownAssetOwner();
		}
		ICurciferAsset(selectedAsset).customerTrading(_orderId, _soldQuantity, _receivedQuantity, contractFee, msg.sender);
	}

	function securitySubcriptionCheck() external view returns (bool) {
		uint256 currentExchangeAccountExpiration = exchangeAccountExpirationList[msg.sender];
		return currentExchangeAccountExpiration > 0 && currentExchangeAccountExpiration >= block.timestamp;
	}

	function getSubscriptionAccount() external view returns (uint) {
		uint256 currentExchangeAccountExpiration = exchangeAccountExpirationList[msg.sender]; 
		return currentExchangeAccountExpiration;
	}

	function paySubsription(uint durationMontly, uint _selectedFeeIndex) external {
		uint256 currentExchangeAccountExpiration = exchangeAccountExpirationList[msg.sender];
		bool isSubscribed = currentExchangeAccountExpiration > 0 && currentExchangeAccountExpiration >= block.timestamp;
		if (isSubscribed) {
			revert expiredOrNoSubscription();
		}
		address selectedFeeToken = feeTokenList[_selectedFeeIndex];
		uint256 selectedSubcriptionFeePrice = feePriceList[_selectedFeeIndex];
		uint allowance = IERC20(selectedFeeToken).allowance(msg.sender, address(this));
		uint balance = IERC20(selectedFeeToken).balanceOf(msg.sender);
		if (allowance <= selectedSubcriptionFeePrice) {
			revert NotEnoughAllowanceToPaySubcriptionFee(selectedSubcriptionFeePrice);
		}
		if (balance <= selectedSubcriptionFeePrice) {
			revert NotEnoughBalanceToPaySubscriptionFee(selectedSubcriptionFeePrice);
		}
		IERC20(selectedFeeToken).safeTransferFrom(msg.sender, _owner, selectedSubcriptionFeePrice * durationMontly);
		exchangeAccountExpirationList[msg.sender] = block.timestamp + subscriptionPeriod * durationMontly;
		emit PaidSubcription(exchangeAccountExpirationList[msg.sender]);
	}

	function getCountProviderList() external view returns (uint) {
		return providerList.length;
	}

	function addFeeList(address _token, uint256 _fees) external onlyOwner {
		feeTokenList.push(_token);
		feePriceList.push(_fees);
	}

	function updateContractFee(uint256 _fee) external onlyOwner{
		contractFee = _fee;
	}

	function createOrderId() private returns (uint256) {
		nonce ++;
		return uint256(keccak256(abi.encode(msg.sender, block.timestamp, nonce)));
	}
}