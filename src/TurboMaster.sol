// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {ERC4626} from "./interfaces/ERC4626.sol";
import {Comptroller} from "./interfaces/Comptroller.sol";

import {TurboGibber} from "./modules/TurboGibber.sol";
import {TurboBooster} from "./modules/TurboBooster.sol";
import {TurboAccountant} from "./modules/TurboAccountant.sol";

import {TurboSafe} from "./TurboSafe.sol";

/// @title Turbo Master
/// @author Transmissions11
/// @notice Factory for creating and managing Turbo Safes.
contract TurboMaster is Auth {
    using SafeTransferLib for ERC20;

    /*///////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice  The Turbo Fuse Pool the Master and its Safes use.
    Comptroller public immutable pool;

    /// @notice The Fei token on the network.
    ERC20 public immutable fei;

    /*///////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a new Turbo Master contract.
    /// @param _pool The Turbo Fuse Pool the Master will use.
    /// @param _fei The Fei token on the network.
    /// @param _owner The owner of the Master.
    /// @param _authority The Authority of the Master.
    constructor(
        Comptroller _pool,
        ERC20 _fei,
        address _owner,
        Authority _authority
    ) Auth(_owner, _authority) {
        pool = _pool;
        fei = _fei;
    }

    /*///////////////////////////////////////////////////////////////
                            BOOSTER STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The Booster module used by the Master and its Safes.
    TurboBooster public booster;

    /// @notice Emitted when the Booster is updated.
    /// @param user The user who triggered the update of the Booster.
    /// @param newBooster The new Booster contract used by the Master.
    event BoosterUpdated(address indexed user, TurboBooster newBooster);

    /// @notice Update the Booster used by the Master.
    /// @param newBooster The new Booster contract to be used by the Master.
    function setBooster(TurboBooster newBooster) external requiresAuth {
        booster = newBooster;

        emit BoosterUpdated(msg.sender, newBooster);
    }

    /*///////////////////////////////////////////////////////////////
                            ACCOUNTANT STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The Accountant module used by the Master and its Safes.
    TurboAccountant public accountant;

    /// @notice Emitted when the Accountant is updated.
    /// @param user The user who triggered the update of the Accountant.
    /// @param newAccountant The new Accountant contract used by the Master.
    event AccountantUpdated(address indexed user, TurboAccountant newAccountant);

    /// @notice Update the Accountant used by the Master.
    /// @param newAccountant The new Accountant contract to be used by the Master.
    function setAccountant(TurboAccountant newAccountant) external requiresAuth {
        accountant = newAccountant;

        emit AccountantUpdated(msg.sender, newAccountant);
    }

    /*///////////////////////////////////////////////////////////////
                            GIBBER STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The Gibber module used by the Master and its Safes.
    TurboGibber public gibber;

    /// @notice Emitted when the Gibber is updated.
    /// @param user The user who triggered the update of the Gibber.
    /// @param newGibber The new Gibber contract used by the Master.
    event GibberUpdated(address indexed user, TurboGibber newGibber);

    /// @notice Update the Gibber used by the Master.
    /// @param newGibber The new Gibber contract to be used by the Master.
    function setGibber(TurboGibber newGibber) external requiresAuth {
        gibber = newGibber;

        emit GibberUpdated(msg.sender, newGibber);
    }

    /*///////////////////////////////////////////////////////////////
                             SAFE STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The total Fei currently boosting vaults.
    uint256 public totalBoosted;

    /// @notice Maps Safe addresses to a boolean confirming they were creating by the Master.
    mapping(TurboSafe => bool) public isSafe;

    /// @notice Maps vault addresses to the total amount of Fei they've being boosted with.
    mapping(ERC4626 => uint256) public getTotalBoostedForVault;

    /*///////////////////////////////////////////////////////////////
                          SAFE CREATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new Safe is created.
    /// @param user The user who created the Safe.
    /// @param underlying The underlying token of the Safe.
    /// @param safe The newly deployed Safe contract.
    event TurboSafeCreated(address indexed user, ERC20 indexed underlying, TurboSafe safe);

    /// @notice Creates a new Turbo Safe which supports a specific underlying token.
    /// @param underlying The ERC20 token that the Safe should accept.
    /// @return safe The newly deployed Turbo Safe which accepts the provided underlying token.
    function createSafe(ERC20 underlying) external requiresAuth returns (TurboSafe safe) {
        // Create a new Safe using the provided underlying token.
        safe = new TurboSafe(msg.sender, underlying);

        // Confirm the Safe was created by the Master.
        isSafe[safe] = true;

        emit TurboSafeCreated(msg.sender, underlying, safe);

        // Prepare a users array to whitelist the Safe.
        address[] memory users = new address[](1);
        users[0] = msg.sender;

        // Prepare an enabled array to whitelist the Safe.
        bool[] memory enabled = new bool[](1);
        enabled[0] = true;

        // Whitelist the Safe to access the Turbo Fuse Pool, revert if an error is returned.
        require(pool._setWhitelistStatuses(users, enabled) == 0, "WHITELIST_ERROR");
    }

    /*///////////////////////////////////////////////////////////////
                          SAFE CALLBACK LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Callback triggered whenever a Safe boosts a vault.
    /// @param vault The vault that was boosted.
    /// @param feiAmount The amount of Fei used to boost the vault.
    function onSafeBoost(ERC4626 vault, uint256 feiAmount) external {
        // Ensure the Safe was created by this Master.
        require(isSafe[TurboSafe(msg.sender)], "INVALID_SAFE");

        // Check with the booster that the Safe is allowed to boost the vault using this amount of Fei.
        require(booster.canSafeBoostVault(TurboSafe(msg.sender), vault, feiAmount), "BOOSTER_REJECTED");

        // Update the total amount of Fei being using to boost the vault.
        getTotalBoostedForVault[vault] += feiAmount;

        // Update the total amount of Fei being using to boost vaults.
        totalBoosted += feiAmount;
    }

    /// @notice Callback triggered whenever a Safe withdraws from a vault.
    /// @param vault The vault that was withdrawn from.
    /// @param feiAmount The amount of Fei withdrawn from the vault.
    function onSafeLess(ERC4626 vault, uint256 feiAmount) external {
        // Ensure the Safe was created by this Master.
        require(isSafe[TurboSafe(msg.sender)], "INVALID_SAFE");

        // Update the total amount of Fei being using to boost the vault.
        getTotalBoostedForVault[vault] += feiAmount;

        // Update the total amount of Fei being using to boost vaults.
        totalBoosted += feiAmount;
    }

    /*///////////////////////////////////////////////////////////////
                         FEE RECLAMATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when fees are claimed by an authorized user.
    /// @param user The authorized user who claimed the fees.
    /// @param feiAmount The amount of Fei fees that were claimed.
    event FeesClaimed(address indexed user, uint256 feiAmount);

    /// @notice Claims the fees generated as Fei sent to the Master.
    /// @param feiAmount The amount of Fei fees that should be claimed.
    function claimFees(uint256 feiAmount) external requiresAuth {
        emit FeesClaimed(msg.sender, feiAmount);

        // Transfer the Fei fees to the authorized caller.
        fei.safeTransfer(msg.sender, feiAmount);
    }
}
