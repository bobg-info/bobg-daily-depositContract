// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

abstract contract TokenPaymentSplitter {
    event PayeeAdded(address account, uint256 shares);
    event PaymentReleased(address to, uint256 amount);
    
    using SafeERC20Upgradeable for IERC20Upgradeable;
    address internal paymentToken;
    uint256 internal releaseTime;
    uint256 internal vestingMonth;
    uint256 internal _totalShares;
    uint256 internal _totalTokenReleased;
    address[] internal _payees;
    mapping(address => bool) accountExists;
    mapping(address => uint) public addressesEntityIndex;
    mapping(address => uint256) internal _shares;
    mapping(address => uint256) internal _tokenReleased;
    bool internal locked;

    // Re-Entry対策
    modifier noReentrant() {
        require(!locked, "No re-entrancy");
        locked = true;
        _;
        locked = false;
    }

    // 初期化の際に使用する（引き出し可能なアドレスと分配率を指定する）
    function _addPayee(address account, uint256 shares_) internal {
        require(
            account != address(0),
            "TokenPaymentSplitter: account is the zero address"
        );
        require(shares_ > 0, "TokenPaymentSplitter: shares are 0");
        require(
            _shares[account] == 0,
            "TokenPaymentSplitter: account already has shares"
        );
        uint entityIndex = _payees.length;
        _payees.push(account);
        _shares[account] = shares_;
        _totalShares = _totalShares + shares_;
        accountExists[account] = true;
        addressesEntityIndex[account] = entityIndex;
        emit PayeeAdded(account, shares_);
    }
    
    // 現時点でClaim可能なトークンバランスを確認する
    function claimableAmount(address account) public view returns (uint256) {
        require(block.timestamp >= releaseTime, "Still in lock-up period"); //ロックアップ期間中に引き出すことはできない
        uint256 tokenTotalReceived = IERC20Upgradeable(paymentToken).balanceOf(address(this)) + _totalTokenReleased; //Deposit Contractに送られた総トークン量
        uint256 totalAsset = (tokenTotalReceived * _shares[account]) / _totalShares; //アドレスに割り当てられた総トークン量
        uint256 vestingTotalDays = 365 * vestingMonth / 12; //ベスティングの総日数
        uint256 vestingDaysElapsed = (block.timestamp - releaseTime) / 60 / 60 / 24; //ベスティングの経過日数
        uint256 claimable; //claim可能なトークン量
        if (vestingDaysElapsed > vestingTotalDays) {
            claimable =  totalAsset - _tokenReleased[account]; //ベスティング期間が終わった後にはclaimable amountが増加しない
        } else {
            claimable =  (totalAsset * vestingDaysElapsed) / vestingTotalDays - _tokenReleased[account];
        }
        return claimable;
    }

    // DepositContractから引き出し可能な総残高を確認する（Claim解放されていない分も含む）
    function totalBalance(address account) public view returns (uint256) {
        uint256 tokenTotalReceived = IERC20Upgradeable(paymentToken).balanceOf(address(this)) + _totalTokenReleased;
        uint256 totalAsset = (tokenTotalReceived * _shares[account]) / _totalShares - _tokenReleased[account];
        return totalAsset;
    }

    // 引き出し量を指定してClaimをする
    function claim(uint256 amount) public virtual noReentrant {
        address account = msg.sender;
        require(block.timestamp >= releaseTime, "Still in lock-up period"); //ロックアップ期間中に引き出すことはできない
        require(
            _shares[account] > 0, "TokenPaymentSplitter: account has no shares" //指定されたアドレスではない
        );
        uint256 tokenTotalReceived = IERC20Upgradeable(paymentToken).balanceOf(address(this)) + _totalTokenReleased; //Deposit Contractに送られた総トークン量
        uint256 totalAsset = (tokenTotalReceived * _shares[account]) / _totalShares; //アドレスに割り当てられた総トークン量
        require(totalAsset >= amount, "More than total assets"); //アドレスに割り当てられた総トークン量より多くのamountをclaimできない
        uint256 vestingTotalDays = 365 * vestingMonth / 12; //ベスティングの総日数
        uint256 vestingDaysElapsed = (block.timestamp - releaseTime) / 60 / 60 / 24; //ベスティングの経過日数
        uint256 claimable; //claim可能なトークン量
        if (vestingDaysElapsed > vestingTotalDays) {
            claimable =  totalAsset - _tokenReleased[account]; //ベスティング期間が終わった後にはclaimable amountが増加しない
        } else {
            claimable =  (totalAsset * vestingDaysElapsed) / vestingTotalDays - _tokenReleased[account];
        }
        require(claimable != 0, "TokenPaymentSplitter: account is not due payment"); //claim可能なトークン量が現時点でゼロ
        require(claimable >= amount, "More than claimable amount"); //指定amountが現在claim可能なトークン量を超えている
        _tokenReleased[account] = _tokenReleased[account] + amount; //claim済みトークンを更新
        _totalTokenReleased = _totalTokenReleased + amount; //Deposit Contract全体のclaim済みトークンを更新
        IERC20Upgradeable(paymentToken).safeTransfer(account, amount); //指定amountを指定アドレスに送金
        emit PaymentReleased(account, amount);
    }
}
