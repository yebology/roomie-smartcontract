// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {ERC1155URIStorage} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol";
import {ERC1155Burnable} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

contract Roomie is ERC1155URIStorage, ERC1155Burnable, ERC1155Holder {
    //
    constructor(string memory _ipfsURL) ERC1155("") {
        _setBaseURI(_ipfsURL);
    }

    function reserveRooms(uint256[] memory _tokenId) external {}

    function supportsInterface(bytes4 _interfaceId) public view override(ERC1155, ERC1155Holder) returns (bool) {
        return super.supportsInterface(_interfaceId);
    }

    function uri(uint256 _tokenId) public view override(ERC1155URIStorage, ERC1155) returns (string memory) {
        return super.uri(_tokenId);
    }

    function mintBatch(
        uint256[] memory _tokenIds,
        uint256[] memory _values,
        string[] memory _tokenURIs,
        bytes memory _data
    ) external {
        _mintBatch(address(this), _tokenIds, _values, _data);
        _setURIBatch(_tokenIds, _tokenURIs);
    }

    function mintSingle(uint256 _tokenId, uint256 _value, string memory _tokenURI, bytes memory _data) external {
        _mint(address(this), _tokenId, _value, _data);
        _setURI(_tokenId, _tokenURI);
    }

    function burnBatch(address _from, uint256[] memory _ids, uint256[] memory _values) public override {
        _burnBatch(_from, _ids, _values);
    }

    function burnSingle(address _from, uint256 _id, uint256 _value) external {
        _burn(_from, _id, _value);
    }

    function balanceOf(address _account, uint256 _tokenId) public view override returns (uint256) {
        return super.balanceOf(_account, _tokenId);
    }

    function _setURIBatch(uint256[] memory _tokenIds, string[] memory _tokenURIs) private {
        uint256 total = _tokenIds.length;
        for (uint256 i = 0; i < total; i++) {
            _setURI(_tokenIds[i], _tokenURIs[i]);
        }
    }

    //
}
