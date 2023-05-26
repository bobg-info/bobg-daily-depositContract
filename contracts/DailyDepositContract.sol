// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./TokenPaymentSplitter.sol";

contract DailyDepositContract is Initializable, OwnableUpgradeable, TokenPaymentSplitter {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    function initialize(address newOwner, address[] memory _payees, uint256[] memory _shares,
    address _paymentToken, uint256 _releaseTime, uint256 _vestingMonth) public initializer {
        __Ownable_init();
        require(_releaseTime > block.timestamp);
        require(
            _payees.length == _shares.length,
            "TokenPaymentSplitter: payees and shares length mismatch"
        );
        require(_payees.length > 0, "TokenPaymentSplitter: no payees");
        for (uint256 i = 0; i < _payees.length; i++) {
            _addPayee(_payees[i], _shares[i]);
        }
        require(_paymentToken != address(0), "ERC20: zero address");
        transferOwnership(newOwner);
        paymentToken = _paymentToken;
        releaseTime = _releaseTime;
        vestingMonth = _vestingMonth;
    }

    // renounceOwnership関数を以下で無効化する（Owner権限は常に必要なため）
    function renounceOwnership() public virtual onlyOwner override  {}

    // Owner権限により資産を他のコントラクトへ移行する（緊急用）
    function transfer(address recipient, uint256 amount) external onlyOwner {
        IERC20Upgradeable(paymentToken).safeTransfer(recipient, amount);
    }

    // Owner権限により指定アドレスを変更する
    function changeAddress(address oldAccount, address newAccount) external onlyOwner {
        require(accountExists[oldAccount], "Account does not exist");
        require(!accountExists[newAccount], "Account already exists"); //既に登録済みのアドレスを指定できない（以下の処理が無効となってしまうため）
        uint addressEntityIndex = addressesEntityIndex[oldAccount];
        // アップデート処理
        _payees[addressEntityIndex] = newAccount;
        _shares[newAccount] = _shares[oldAccount];
        _tokenReleased[newAccount] = _tokenReleased[oldAccount];
        accountExists[newAccount] = true;
        addressesEntityIndex[newAccount] = addressesEntityIndex[oldAccount];
        // 旧アカウント処理
        _shares[oldAccount] = 0;
        _tokenReleased[oldAccount] = 0;
        accountExists[oldAccount] = false;
    }
}