// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/**
 * @title Compatible
 * @notice Abstract contract that allows the contract to receive Ether and ERC721/1155 tokens.
 * @dev Implements `receive()` to accept Ether, and ERC721/1155 hooks for token reception.
 * @custom:security-contact security@multipli.com
 */
abstract contract Compatible {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when the contract receives Ether.
     * @param sender The address that sent the Ether.
     * @param amount The amount of Ether received.
     */
    event Received(address sender, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                           RECEIVE / FALLBACK
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Receive Ether and emit a `Received` event.
     * @dev This function is called when the contract is sent Ether without calldata.
     */
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    /*//////////////////////////////////////////////////////////////
                    USER-FACING READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Handle the receipt of a single ERC721 token type.
     * @dev Returns the function selector to confirm token receipt.
     * @param operator The address which called `safeTransferFrom`.
     * @param from The address which previously owned the token.
     * @param tokenId The ID of the token being transferred.
     * @param data Additional data sent with the transfer.
     * @return The selector to confirm the ERC721 token receipt.
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    )
        external
        pure
        returns (bytes4)
    {
        return this.onERC721Received.selector;
    }

    /**
     * @notice Handle the receipt of a single ERC1155 token type.
     * @dev Returns the function selector to confirm token receipt.
     * @param operator The address which called `safeTransferFrom`.
     * @param from The address which previously owned the token.
     * @param id The ID of the token being transferred.
     * @param value The amount of tokens being transferred.
     * @param data Additional data sent with the transfer.
     * @return The selector to confirm the ERC1155 token receipt.
     */
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    )
        external
        pure
        returns (bytes4)
    {
        return this.onERC1155Received.selector;
    }

    /**
     * @notice Handle the receipt of multiple ERC1155 token types in a batch.
     * @dev Returns the function selector to confirm token receipt.
     * @param operator The address which called `safeBatchTransferFrom`.
     * @param from The address which previously owned the tokens.
     * @param ids The IDs of the tokens being transferred.
     * @param values The amounts of tokens being transferred.
     * @param data Additional data sent with the transfer.
     * @return The selector to confirm the batch receipt of ERC1155 tokens.
     */
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    )
        external
        pure
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }
}
