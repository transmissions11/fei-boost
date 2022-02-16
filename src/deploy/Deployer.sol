// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";
import {MultiRolesAuthority} from "solmate/auth/authorities/MultiRolesAuthority.sol";

import {Comptroller} from "../interfaces/Comptroller.sol";

import {TurboClerk} from "../modules/TurboClerk.sol";
import {TurboGibber} from "../modules/TurboGibber.sol";
import {TurboBooster} from "../modules/TurboBooster.sol";
import {TurboSavior} from "../modules/TurboSavior.sol";

import {TurboMaster, TurboSafe, ERC4626} from "../TurboMaster.sol";

import {TimelockController} from "@openzeppelin/governance/TimelockController.sol";

/// @title Turbo Deployer
contract Deployer {
    Comptroller pool = Comptroller(0xc62ceB397a65edD6A68715b2d3922dEE0D63F45c);
    ERC20 fei = ERC20(0x956F47F50A910163D8BF957Cf5846D573E7f87CA);

    address constant feiDAOTimelock = 0xd51dbA7a94e1adEa403553A8235C302cEbF41a3c;

    uint256 public timelockDelay = 30 days;

    uint8 public constant GIBBER_ROLE = 1;
    uint8 public constant ROUTER_ROLE = 2;
    uint8 public constant SAVIOR_ROLE = 3;
    uint8 public constant TURBO_POD_ROLE = 4;

    TurboMaster master;
    TurboGibber gibber;
    TurboSavior savior;

    constructor() {
        deploy();
    }

    function deploy() public {
        TimelockController turboTimelock = new TimelockController(timelockDelay, new address[](0), new address[](0));
        MultiRolesAuthority turboAuthority = new MultiRolesAuthority(address(this), Authority(address(0)));
        turboAuthority.setRoleCapability(GIBBER_ROLE, TurboSafe.gib.selector, true);
        turboAuthority.setRoleCapability(TURBO_POD_ROLE, TurboSafe.slurp.selector, true);
        turboAuthority.setRoleCapability(TURBO_POD_ROLE, TurboSafe.less.selector, true);

        master = new TurboMaster(
            pool,
            fei,
            address(this),
            turboAuthority
        );

        TurboClerk clerk = new TurboClerk(feiDAOTimelock, Authority(address(0)));

        master.setClerk(clerk);

        TurboBooster booster = new TurboBooster(
           feiDAOTimelock, Authority(address(0)) 
        );

        master.setBooster(booster);
        
        gibber = new TurboGibber(master, address(turboTimelock), Authority(address(0)));

        turboAuthority.setUserRole(address(gibber), GIBBER_ROLE, true);

        savior = new TurboSavior(
            master, feiDAOTimelock, Authority(address(0))
        );

        master.setDefaultSafeAuthority(
            configureDefaultAuthority(
                address(turboTimelock),
                address(this),
                address(savior)
            )
        );

        // TODO Deploy router. Gibber has minter. Grant TURBO_POD_ROLE to Turbo pod.
    
        master.setOwner(address(turboTimelock));
    }

    function configureDefaultAuthority(address owner, address router, address savior) internal returns (MultiRolesAuthority) {
        MultiRolesAuthority defaultAuthority = new MultiRolesAuthority(address(this), Authority(address(0)));
        defaultAuthority.setRoleCapability(ROUTER_ROLE, TurboSafe.boost.selector, true);
        defaultAuthority.setRoleCapability(ROUTER_ROLE, TurboSafe.less.selector, true);
        defaultAuthority.setRoleCapability(ROUTER_ROLE, TurboSafe.slurp.selector, true);
        defaultAuthority.setRoleCapability(ROUTER_ROLE, TurboSafe.sweep.selector, true);
        defaultAuthority.setRoleCapability(ROUTER_ROLE, ERC4626.deposit.selector, true);
        defaultAuthority.setRoleCapability(ROUTER_ROLE, ERC4626.mint.selector, true);
        defaultAuthority.setRoleCapability(ROUTER_ROLE, ERC4626.withdraw.selector, true);
        defaultAuthority.setRoleCapability(ROUTER_ROLE, ERC4626.redeem.selector, true);

        defaultAuthority.setUserRole(router, ROUTER_ROLE, true);

        defaultAuthority.setRoleCapability(SAVIOR_ROLE, TurboSafe.less.selector, true);

        defaultAuthority.setUserRole(savior, SAVIOR_ROLE, true);

        defaultAuthority.setOwner(owner);
        return defaultAuthority;
    }
}