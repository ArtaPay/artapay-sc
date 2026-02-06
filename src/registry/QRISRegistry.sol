// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title QRISRegistry
 * @notice Registry for binding QRIS hashes to ArtaPay Smart Accounts (SA)
 * @dev One SA can register only one QRIS hash. Admin can revoke bindings.
 */
contract QRISRegistry is Ownable {
    struct QrisInfo {
        bytes32 qrisHash;
        address sa;
        string qrisPayload;
        string merchantName;
        string merchantId;
        string merchantCity;
        bool active;
    }

    mapping(bytes32 => QrisInfo) private qrisByHash;
    mapping(address => bytes32) private qrisBySa;
    mapping(address => bool) private admins;

    /// @notice Emitted when an admin is added/removed
    event AdminUpdated(address indexed admin, bool enabled);
    /// @notice Emitted when a QRIS hash is registered to a smart account
    event QrisRegistered(
        bytes32 indexed qrisHash, address indexed sa, string merchantName, string merchantId, string merchantCity
    );
    /// @notice Emitted when a QRIS hash is removed
    event QrisRemoved(bytes32 indexed qrisHash, address indexed sa, address indexed caller);

    /// @dev Restricts function to owner or admin
    modifier onlyAdmin() {
        require(msg.sender == owner() || admins[msg.sender], "QRIS: not admin");
        _;
    }

    /// @notice Initialize registry with deployer as owner
    constructor() Ownable(msg.sender) {}

    /**
     * @notice Add or remove admin address
     * @param admin Admin address
     * @param enabled Status
     */
    function setAdmin(address admin, bool enabled) external onlyOwner {
        require(admin != address(0), "QRIS: invalid admin");
        admins[admin] = enabled;
        emit AdminUpdated(admin, enabled);
    }

    /**
     * @notice Check if address is admin
     * @param account Address to check
     */
    function isAdmin(address account) external view returns (bool) {
        return account == owner() || admins[account];
    }

    /**
     * @notice Get QRIS info by hash
     * @param qrisHash QRIS hash
     */
    function getQris(bytes32 qrisHash) external view returns (QrisInfo memory) {
        return qrisByHash[qrisHash];
    }

    /**
     * @notice Get QRIS info by smart account
     * @param sa Smart account address
     */
    function getQrisBySa(address sa) external view returns (QrisInfo memory) {
        bytes32 qrisHash = qrisBySa[sa];
        if (qrisHash == bytes32(0)) {
            return QrisInfo({
                qrisHash: bytes32(0),
                sa: address(0),
                qrisPayload: "",
                merchantName: "",
                merchantId: "",
                merchantCity: "",
                active: false
            });
        }
        return qrisByHash[qrisHash];
    }

    /**
     * @notice Register a QRIS hash to caller smart account
     * @dev Caller can only register once (remove first to re-register)
     * @param qrisHash QRIS hash (normalized)
     * @param merchantName Merchant name
     * @param merchantId Merchant ID
     * @param merchantCity Merchant city
     */
    function registerQris(
        bytes32 qrisHash,
        string calldata qrisPayload,
        string calldata merchantName,
        string calldata merchantId,
        string calldata merchantCity
    ) external {
        require(qrisHash != bytes32(0), "QRIS: invalid hash");
        require(bytes(qrisPayload).length > 0, "QRIS: empty payload");
        require(qrisByHash[qrisHash].sa == address(0), "QRIS: hash already registered");
        require(qrisBySa[msg.sender] == bytes32(0), "QRIS: SA already registered");

        qrisByHash[qrisHash] = QrisInfo({
            qrisHash: qrisHash,
            sa: msg.sender,
            qrisPayload: qrisPayload,
            merchantName: merchantName,
            merchantId: merchantId,
            merchantCity: merchantCity,
            active: true
        });
        qrisBySa[msg.sender] = qrisHash;

        emit QrisRegistered(qrisHash, msg.sender, merchantName, merchantId, merchantCity);
    }

    /**
     * @notice Remove caller's QRIS hash
     */
    function removeMyQris() external {
        bytes32 qrisHash = qrisBySa[msg.sender];
        require(qrisHash != bytes32(0), "QRIS: not registered");
        _removeQris(qrisHash, msg.sender);
    }

    /**
     * @notice Remove a QRIS hash (admin-only)
     * @param qrisHash QRIS hash to remove
     */
    function removeQris(bytes32 qrisHash) external onlyAdmin {
        _removeQris(qrisHash, msg.sender);
    }

    function _removeQris(bytes32 qrisHash, address caller) internal {
        QrisInfo memory info = qrisByHash[qrisHash];
        require(info.sa != address(0), "QRIS: not found");
        delete qrisByHash[qrisHash];
        delete qrisBySa[info.sa];

        emit QrisRemoved(qrisHash, info.sa, caller);
    }
}
