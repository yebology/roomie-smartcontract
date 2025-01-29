// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {ERC1155URIStorage} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Roomie is ERC1155URIStorage, ReentrancyGuard {
    //
    mapping(bytes32 lodgeId => address host) private s_lodgeHost;

    mapping(uint256 tokenId => bytes32 lodgeId) private s_lodgeToken;
    mapping(uint256 tokenId => uint256 price) private s_tokenPricePerNight;

    mapping(bytes32 orderId => address user) private s_customerOrder;
    mapping(bytes32 orderId => uint256 checkIn) private s_customerCheckInTimestamp;
    mapping(bytes32 orderId => uint256 checkOut) private s_customerCheckOutTimestamp;
    mapping(bytes32 orderId => uint256 duration) private s_customerStayDurationInDays;
    mapping(bytes32 orderId => bool checkIn) private s_customerAlreadyCheckIn;

    error LodgeAlreadyRegistered();
    error TokenAlreadyExistence();
    error InvalidAuthorization();
    error InvalidTokenOwnership();
    error TransferError();
    error InvalidTime();
    error InvalidCommitmentFee();
    error MissingCheckIn();

    event Transfer();
    event NewLodgeRegistered();

    modifier checkLodgeStatus(bytes32 _lodgeId) {
        if (lodgeHost(_lodgeId) != address(0)) {
            revert LodgeAlreadyRegistered();
        }
        _;
    }

    modifier checkAuthorization(bytes32 _id, address _host, address _customer) {
        if (
            (_customer == address(0) && lodgeHost(_id) != _host)
                || (_host == address(0) && s_customerOrder[_id] != _customer)
        ) {
            revert InvalidAuthorization();
        }
        _;
    }

    modifier checkTokenExistence(bytes32 _lodgeId, uint256 _tokenId) {
        if (bytes32(s_lodgeToken[_tokenId]).length != 0) {
            revert TokenAlreadyExistence();
        }
        _;
    }

    modifier checkTokenOwnership(bytes32 _lodgeId, uint256 _tokenId) {
        if (keccak256(abi.encodePacked(s_lodgeToken[_tokenId])) != keccak256(abi.encodePacked(_lodgeId))) {
            revert InvalidTokenOwnership();
        }
        _;
    }

    modifier verifyStayPeriod(bytes32 _orderId) {
        uint256 checkInTimestamp = s_customerCheckInTimestamp[_orderId];
        uint256 checkOutTimestamp = s_customerCheckOutTimestamp[_orderId];

        if ((block.timestamp < checkInTimestamp) || (block.timestamp < checkOutTimestamp)) {
            revert InvalidTime();
        }
        _;
    }

    // CURRENT FORMULA : tokenPricePerNight * mintSupply
    modifier validateStaking(uint256 _tokenId, uint256 _mintAmount, uint256 _value) {
        uint256 tokenPricePerNight = s_tokenPricePerNight[_tokenId];
        uint256 expectedValue = tokenPricePerNight * _mintAmount;

        if (expectedValue != _value) {
            revert InvalidCommitmentFee();
        }
        _;
    }

    constructor(string memory _ipfsURL) ERC1155("") {
        _setBaseURI(_ipfsURL);
    }

    function reserve(
        bytes32 _lodgeId,
        bytes32 _orderId,
        uint256 _tokenId,
        uint256 _days,
        uint256 _checkInTimestamp,
        uint256 _checkOutTimestamp
    ) external payable nonReentrant {
        _safeTransferFrom(lodgeHost(_lodgeId), _msgSender(), _tokenId, _days, "");
        _placeFunds(_tokenId, _days);
        _addToOrder(_orderId, _checkInTimestamp, _checkOutTimestamp, _days);
    }

    function registerLodge(bytes32 _lodgeId) external checkLodgeStatus(_lodgeId) {
        s_lodgeHost[_lodgeId] = _msgSender();
        emit NewLodgeRegistered();
    }

    function registerToken(bytes32 _lodgeId, string memory _tokenURI, uint256 _tokenId, uint256 _tokenPrice)
        external
        checkAuthorization(_lodgeId, _msgSender(), address(0))
        checkTokenExistence(_lodgeId, _tokenId)
        nonReentrant
    {
        s_lodgeToken[_tokenId] = _lodgeId;
        s_tokenPricePerNight[_tokenId] = _tokenPrice;
        _setURI(_tokenId, _tokenURI);
    }

    function mint(bytes32 _lodgeId, uint256 _tokenId, uint256 _value, bytes memory _data)
        external
        payable
        checkAuthorization(_lodgeId, _msgSender(), address(0))
        checkTokenOwnership(_lodgeId, _tokenId)
        validateStaking(_tokenId, _value, msg.value)
        nonReentrant
    {
        _mint(_msgSender(), _tokenId, _value, _data);
        _placeFunds(_tokenId, _value);
    }

    function checkIn(bytes32 _orderId)
        external
        checkAuthorization(_orderId, address(0), _msgSender())
        verifyStayPeriod(_orderId)
    {
        s_customerAlreadyCheckIn[_orderId] = true;
    }

    function checkOut(bytes32 _lodgeId, bytes32 _orderId, uint256 _tokenId)
        external
        checkAuthorization(_lodgeId, _msgSender(), address(0))
        checkTokenOwnership(_lodgeId, _tokenId)
        verifyStayPeriod(_orderId)
        nonReentrant
    {
        uint256 burnAmount = s_customerStayDurationInDays[_orderId];
        uint256 transferAmount = s_tokenPricePerNight[_tokenId] * burnAmount;
        address customer = s_customerOrder[_orderId];
        require(s_customerAlreadyCheckIn[_orderId], MissingCheckIn());
        _burn(customer, _tokenId, burnAmount);
        _transferFunds(lodgeHost(_lodgeId), transferAmount, 2);
    }

    function uri(uint256 _tokenId) public view override returns (string memory) {
        return super.uri(_tokenId);
    }

    function balanceOf(address _account, uint256 _tokenId) public view override returns (uint256) {
        return super.balanceOf(_account, _tokenId);
    }

    function orderDetail(bytes32 _orderId) external view returns (address, uint256, uint256, uint256, bool) {
        return (
            s_customerOrder[_orderId],
            s_customerCheckInTimestamp[_orderId],
            s_customerCheckOutTimestamp[_orderId],
            s_customerStayDurationInDays[_orderId],
            s_customerAlreadyCheckIn[_orderId]
        );
    }

    function tokenDetail(uint256 _tokenId) external view returns (bytes32, uint256) {
        return (s_lodgeToken[_tokenId], s_tokenPricePerNight[_tokenId]);
    }

    function lodgeHost(bytes32 _lodgeId) public view returns (address) {
        return s_lodgeHost[_lodgeId];
    }

    function _addToOrder(bytes32 _orderId, uint256 _checkInTimestamp, uint256 _checkOutTimestamp, uint256 _days)
        private
    {
        s_customerOrder[_orderId] = _msgSender();
        s_customerCheckInTimestamp[_orderId] = _checkInTimestamp;
        s_customerCheckOutTimestamp[_orderId] = _checkOutTimestamp;
        s_customerStayDurationInDays[_orderId] = _days;
    }

    function _placeFunds(uint256 _tokenId, uint256 _amount) private {
        uint256 amount = s_tokenPricePerNight[_tokenId] * _amount;
        _transferFunds(address(this), amount, 1);
    }

    function _transferFunds(address _recipient, uint256 _amount, uint256 _time) private {
        uint256 amountToTransfer = _amount * _time;
        (bool success,) = payable(_recipient).call{value: amountToTransfer}("");
        require(success, TransferError());
        emit Transfer();
    }

    receive() external payable {}

    //
}
