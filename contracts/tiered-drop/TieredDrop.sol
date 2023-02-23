// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../plugin/BaseRouter.sol";
import "../extension/Initializable.sol";
import "../extension/Multicall.sol";
import "../extension/Permissions.sol";

import "../extension/init/ContractMetadataInit.sol";
import "../extension/init/ERC721AInit.sol";
import "../extension/init/ERC2771ContextInit.sol";
import "../extension/init/OwnableInit.sol";
import "../extension/init/PermissionsInit.sol";
import "../extension/init/PrimarySaleInit.sol";
import "../extension/init/RoyaltyInit.sol";
import "../extension/init/SignatureActionInit.sol";

/**
 *  Defualt extensions to add:
 *      - TieredDropLogic
 *      - PermissionsEnumerable
 */

contract TieredDrop is
    Initializable,
    Multicall,
    BaseRouter,
    PrimarySaleInit,
    ContractMetadataInit,
    ERC721AInit,
    ERC2771ContextInit,
    OwnableInit,
    PermissionsInit,
    RoyaltyInit,
    SignatureActionInit
{
    /*///////////////////////////////////////////////////////////////
                    Constructor and Initializer logic
    //////////////////////////////////////////////////////////////*/

    constructor(Plugin[] memory _plugins) BaseRouter(_plugins) {}

    /// @dev Initiliazes the contract, like a constructor.
    function initialize(
        address _defaultAdmin,
        string memory _name,
        string memory _symbol,
        string memory _contractURI,
        address[] memory _trustedForwarders,
        address _saleRecipient,
        address _royaltyRecipient,
        uint16 _royaltyBps
    ) external initializer {
        // Initialize inherited contracts, most base-like -> most derived.
        __ERC2771Context_init(_trustedForwarders);
        __ERC721A_init(_name, _symbol);
        __SignatureAction_init();

        _setupContractURI(_contractURI);
        _setupOwner(_defaultAdmin);

        _setupRoles(_defaultAdmin);

        _setupDefaultRoyaltyInfo(_royaltyRecipient, _royaltyBps);
        _setupPrimarySaleRecipient(_saleRecipient);
    }

    function _setupRoles(address _defaultAdmin) internal onlyInitializing {
        bytes32 _operatorRole = keccak256("OPERATOR_ROLE");
        bytes32 _transferRole = keccak256("TRANSFER_ROLE");
        bytes32 _minterRole = keccak256("MINTER_ROLE");
        bytes32 _defaultAdminRole = 0x00;

        _setupRole(_defaultAdminRole, _defaultAdmin);
        _setupRole(_minterRole, _defaultAdmin);
        _setupRole(_transferRole, _defaultAdmin);
        _setupRole(_transferRole, address(0));
        _setupRole(_operatorRole, _defaultAdmin);
        _setupRole(_operatorRole, address(0));
    }

    /*///////////////////////////////////////////////////////////////
                        Internal functions
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns whether a plugin can be set in the given execution context.
    function _canSetPlugin() internal view virtual override returns (bool) {
        bytes32 defaultAdminRole = 0x00;
        return IPermissions(address(this)).hasRole(defaultAdminRole, msg.sender);
    }
}
