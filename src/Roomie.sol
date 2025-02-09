// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {ERC1155URIStorage} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Roomie is ERC1155URIStorage, ERC1155Holder, ReentrancyGuard {
    //
    mapping(bytes32 lodgeId => address host) private s_lodgeHost;

    mapping(uint256 tokenId => bytes32 lodgeId) private s_lodgeToken;
    mapping(uint256 tokenId => uint256 price) private s_tokenPricePerNight;

    mapping(uint256 tokenId => uint256 supply) private s_tokenSupply;
    mapping(uint256 tokenId => uint256 burn) private s_tokenBurn;

    mapping(bytes32 orderId => address user) private s_customerOrder;
    mapping(bytes32 orderId => uint256 tokenId) private s_orderToken;
    mapping(bytes32 orderId => bytes32 lodgeId) private s_lodgeOrder;
    mapping(bytes32 orderId => uint256 checkIn) private s_customerCheckInTimestamp;
    mapping(bytes32 orderId => uint256 checkOut) private s_customerCheckOutTimestamp;
    mapping(bytes32 orderId => uint256 duration) private s_customerStayDurationInDays;
    mapping(bytes32 orderId => bool checkIn) private s_customerAlreadyCheckIn;
    mapping(bytes32 orderId => bool checkOut) private s_customerAlreadyCheckOut;

    mapping(bytes32 caseId => bytes32 orderId) private s_problematicOrder;
    mapping(bytes32 caseId => uint256 hostVote) private s_hostVote;
    mapping(bytes32 caseId => uint256 customerVote) private s_customerVote;
    mapping(bytes32 caseId => uint256 timestamp) private s_caseCreated;
    mapping(bytes32 caseId => mapping(address voter => bool alreadyVote)) private s_voterStatus;

    error LodgeAlreadyRegistered();
    error TokenAlreadyExistence();
    error InvalidAuthorization();
    error InvalidTokenOwnership();
    error TransferError();
    error InvalidTime();
    error InvalidStakingAmount();
    error MissingCheckIn();
    error MissingCheckOut();

    error InvalidVoteInput();
    error CaseNotAvailable();
    error VoterAlreadyVote();

    event Transfer();
    event LodgeRegistered();
    event TokenRegistered();
    event ReservationPlaced();

    enum CheckTimestamp {
        CHECK_IN,
        CHECK_OUT
    }

    modifier checkLodgeStatus(bytes32 _lodgeId) {
        if (s_lodgeHost[_lodgeId] != address(0)) {
            revert LodgeAlreadyRegistered();
        }
        _;
    }

    modifier checkAuthorization(bytes32 _id, address _host, address _customer) {
        if (
            (_customer == address(0) && s_lodgeHost[_id] != _host)
                || (_host == address(0) && s_customerOrder[_id] != _customer)
        ) {
            revert InvalidAuthorization();
        }
        _;
    }

    modifier checkTokenExistence(bytes32 _lodgeId, uint256 _tokenId) {
        if (s_lodgeToken[_tokenId] != bytes32("")) {
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

    modifier verifyCheckInTime(bytes32 _orderId) {
        uint256 checkInTimestamp = s_customerCheckInTimestamp[_orderId];
        if (block.timestamp < checkInTimestamp) {
            revert InvalidTime();
        }
        _;
    }

    modifier verifyOrderStatus(bytes32 _orderId, CheckTimestamp check, bool expectedStatus) {
        if (check == CheckTimestamp.CHECK_IN && s_customerAlreadyCheckIn[_orderId] != expectedStatus) {
            revert MissingCheckIn();
        } else if (check == CheckTimestamp.CHECK_OUT && s_customerAlreadyCheckOut[_orderId] != expectedStatus) {
            revert MissingCheckOut();
        }
        _;
    }

    modifier checkOrderToken(bytes32 _orderId, uint256 _tokenId) {
        if (s_orderToken[_orderId] != _tokenId) {
            revert InvalidAuthorization();
        }
        _;
    }

    modifier onlyAuthorized(bytes32 _orderId, bytes32 _lodgeId) {
        require(
            _msgSender() == s_customerOrder[_orderId] || s_lodgeOrder[_orderId] == _lodgeId
                || _msgSender() == s_lodgeHost[_lodgeId],
            InvalidAuthorization()
        );
        _;
    }

    modifier caseAvailable(bytes32 _caseId) {
        require(
            block.timestamp < s_caseCreated[_caseId] + 7 days || s_problematicOrder[_caseId] != bytes32(""),
            CaseNotAvailable()
        );
        _;
    }

    modifier validVote(uint256 _side) {
        require(_side == 0 || _side == 1, InvalidVoteInput());
        _;
    }

    modifier notVotedYet(bytes32 _caseId) {
        require(!s_voterStatus[_caseId][_msgSender()], VoterAlreadyVote());
        _;
    }

    modifier withdrawAllowed(bytes32 _caseId) {
        require(block.timestamp >= s_caseCreated[_caseId] + 7 days, InvalidTime());
        _;
    }

    // CURRENT FORMULA : tokenPricePerNight * mintSupply
    modifier validateStaking(uint256 _tokenId, uint256 _amount, uint256 _value) {
        uint256 tokenPricePerNight = s_tokenPricePerNight[_tokenId];
        uint256 expectedValue = tokenPricePerNight * _amount;

        if (expectedValue != _value) {
            revert InvalidStakingAmount();
        }

        _;
    }

    constructor() ERC1155("") {
        _setBaseURI("https://gateway.pinata.cloud/ipfs/");
    }

    function registerLodge(bytes32 _lodgeId) external checkLodgeStatus(_lodgeId) {
        s_lodgeHost[_lodgeId] = _msgSender();
        emit LodgeRegistered();
    }

    function registerToken(bytes32 _lodgeId, string memory _tokenURI, uint256 _tokenId, uint256 _tokenPrice)
        external
        checkAuthorization(_lodgeId, _msgSender(), address(0))
        checkTokenExistence(_lodgeId, _tokenId)
        nonReentrant
    {
        _registerToken(_lodgeId, _tokenId, _tokenPrice);
        _setURI(_tokenId, _tokenURI);
        emit TokenRegistered();
    }

    function mint(bytes32 _lodgeId, uint256 _tokenId, uint256 _value, bytes memory _data)
        external
        payable
        checkAuthorization(_lodgeId, _msgSender(), address(0))
        checkTokenOwnership(_lodgeId, _tokenId)
        validateStaking(_tokenId, _value, msg.value)
        nonReentrant
    {
        _mint(address(this), _tokenId, _value, _data);
        _incrementTokenSupply(_tokenId, _value);
        _placeFunds(_tokenId, _value);
    }

    function reserve(bytes32 _lodgeId, bytes32 _orderId, uint256 _tokenId, uint256 _days, uint256 _checkInTimestamp)
        external
        payable
        checkTokenOwnership(_lodgeId, _tokenId)
        validateStaking(_tokenId, _days, msg.value)
        nonReentrant
    {
        _safeTransferFrom(address(this), _msgSender(), _tokenId, _days, "");
        _placeFunds(_tokenId, _days);
        _addToOrder(_orderId, _lodgeId, _tokenId, _checkInTimestamp, _days);
        emit ReservationPlaced();
    }

    function checkIn(bytes32 _orderId)
        external
        checkAuthorization(_orderId, address(0), _msgSender())
        verifyCheckInTime(_orderId)
    {
        s_customerAlreadyCheckIn[_orderId] = true;
    }

    function checkOut(bytes32 _orderId, uint256 _tokenId)
        external
        checkAuthorization(_orderId, address(0), _msgSender())
        verifyOrderStatus(_orderId, CheckTimestamp.CHECK_IN, true)
        checkOrderToken(_orderId, _tokenId)
    {
        uint256 burnAmount = s_customerStayDurationInDays[_orderId];
        _burn(_msgSender(), _tokenId, burnAmount);
        _decrementTokenSupply(_tokenId, burnAmount);
        s_customerCheckOutTimestamp[_orderId] = block.timestamp;
        s_customerAlreadyCheckOut[_orderId] = true;
    }

    function withdrawFromCustomerCheckOut(bytes32 _lodgeId, bytes32 _orderId, uint256 _tokenId)
        public
        checkAuthorization(_lodgeId, _msgSender(), address(0))
        checkTokenOwnership(_lodgeId, _tokenId)
        verifyOrderStatus(_orderId, CheckTimestamp.CHECK_OUT, true)
        nonReentrant
    {
        _transferHostFunds(_msgSender(), _orderId, _tokenId);
    }

    function openCase(bytes32 _caseId, bytes32 _orderId, bytes32 _lodgeId)
        external
        verifyOrderStatus(_orderId, CheckTimestamp.CHECK_OUT, false)
        onlyAuthorized(_orderId, _lodgeId)
    {
        _registerCase(_caseId, _orderId);
    }

    function voteOnCase(bytes32 _caseId, uint256 _side)
        external
        caseAvailable(_caseId)
        validVote(_side)
        notVotedYet(_caseId)
    {
        _recordVote(_caseId, _side);
    }

    function withdrawForCaseWinner(bytes32 _caseId, bytes32 _orderId, uint256 _tokenId)
        external
        withdrawAllowed(_caseId)
    {
        _processWithdrawal(_caseId, _orderId, _tokenId);
    }

    function supportsInterface(bytes4 _interfaceId) public view override(ERC1155, ERC1155Holder) returns (bool) {
        return super.supportsInterface(_interfaceId);
    }

    function uri(uint256 _tokenId) public view override returns (string memory) {
        return super.uri(_tokenId);
    }

    function balanceOf(address _account, uint256 _tokenId) public view override returns (uint256) {
        return super.balanceOf(_account, _tokenId);
    }

    function orderDetail(bytes32 _orderId)
        external
        view
        returns (address, bytes32, uint256, uint256, uint256, uint256, bool, bool)
    {
        return (
            s_customerOrder[_orderId],
            s_lodgeOrder[_orderId],
            s_orderToken[_orderId],
            s_customerCheckInTimestamp[_orderId],
            s_customerCheckOutTimestamp[_orderId],
            s_customerStayDurationInDays[_orderId],
            s_customerAlreadyCheckIn[_orderId],
            s_customerAlreadyCheckOut[_orderId]
        );
    }

    function caseDetail(bytes32 _caseId) external view returns (bytes32, uint256, uint256, uint256) {
        return (s_problematicOrder[_caseId], s_hostVote[_caseId], s_customerVote[_caseId], s_caseCreated[_caseId]);
    }

    function tokenDetail(uint256 _tokenId) external view returns (bytes32, uint256, uint256, uint256) {
        return (s_lodgeToken[_tokenId], s_tokenPricePerNight[_tokenId], s_tokenSupply[_tokenId], s_tokenBurn[_tokenId]);
    }

    function _addToOrder(bytes32 _orderId, bytes32 _lodgeId, uint256 _tokenId, uint256 _checkInTimestamp, uint256 _days)
        private
    {
        s_customerOrder[_orderId] = _msgSender();
        s_lodgeOrder[_orderId] = _lodgeId;
        s_orderToken[_orderId] = _tokenId;
        s_customerCheckInTimestamp[_orderId] = _checkInTimestamp;
        s_customerStayDurationInDays[_orderId] = _days;
    }

    function _registerToken(bytes32 _lodgeId, uint256 _tokenId, uint256 _tokenPrice) private {
        s_lodgeToken[_tokenId] = _lodgeId;
        s_tokenPricePerNight[_tokenId] = _tokenPrice;
    }

    function _incrementTokenSupply(uint256 _tokenId, uint256 _value) private {
        s_tokenSupply[_tokenId] += _value;
    }

    function _decrementTokenSupply(uint256 _tokenId, uint256 _value) private {
        s_tokenSupply[_tokenId] -= _value;
        s_tokenBurn[_tokenId] += _value;
    }

    function _placeFunds(uint256 _tokenId, uint256 _amount) private {
        uint256 amount = s_tokenPricePerNight[_tokenId] * _amount;
        _transferFunds(address(this), amount, 1);
    }

    function _registerCase(bytes32 _caseId, bytes32 _orderId) private {
        s_problematicOrder[_caseId] = _orderId;
        s_caseCreated[_caseId] = block.timestamp;
    }

    function _recordVote(bytes32 _caseId, uint256 _side) private {
        if (_side == 0) {
            s_hostVote[_caseId] += 1;
        } else {
            s_customerVote[_caseId] += 1;
        }

        s_voterStatus[_caseId][_msgSender()] = true;
    }

    function _processWithdrawal(bytes32 _caseId, bytes32 _orderId, uint256 _tokenId) private {
        bytes32 lodgeId = s_lodgeOrder[_orderId];
        address host = s_lodgeHost[lodgeId];
        address customer = s_customerOrder[_orderId];
        uint256 amount = s_customerStayDurationInDays[_orderId];
        bool customerIsWin = s_customerVote[_caseId] > s_hostVote[_caseId];

        if (_msgSender() == s_customerOrder[_orderId] && customerIsWin) {
            _transferCustomerFunds(_msgSender(), _tokenId, _orderId);
        } else if (_msgSender() == host && !customerIsWin) {
            _transferHostFunds(_msgSender(), _orderId, _tokenId);
            _burn(customer, _tokenId, amount);
            _decrementTokenSupply(_tokenId, amount);
        } else {
            revert InvalidAuthorization();
        }
    }

    function _transferCustomerFunds(address customer, uint256 _tokenId, bytes32 _orderId) private {
        uint256 amount = s_tokenPricePerNight[_tokenId];
        uint256 time = s_customerStayDurationInDays[_orderId];
        _transferFunds(customer, amount, time);
    }

    function _transferHostFunds(address _host, bytes32 _orderId, uint256 _tokenId) private {
        uint256 burnAmount = s_customerStayDurationInDays[_orderId];
        uint256 transferAmount = s_tokenPricePerNight[_tokenId] * burnAmount;
        _transferFunds(_host, transferAmount, 2);
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
