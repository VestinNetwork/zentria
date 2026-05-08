// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {AntiSniper} from "./AntiSniper.sol";
import {CreatorVesting} from "./CreatorVesting.sol";
import {FeeSplitter} from "./FeeSplitter.sol";
import {Graduator} from "./Graduator.sol";
import {ZentriaCurve} from "./ZentriaCurve.sol";
import {ZentriaToken} from "./ZentriaToken.sol";

/// @title ZentriaLaunchpad
/// @notice Factory for fair-launch tokens. createToken() deploys a Token + Curve pair and wires
///         them to the shared FeeSplitter / Graduator / CreatorVesting infrastructure.
///         No msg.value required — bonding curve handles all liquidity formation.
contract ZentriaLaunchpad is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    FeeSplitter public immutable feeSplitter;
    Graduator public immutable graduator;
    CreatorVesting public immutable creatorVesting;
    address public immutable weth;

    struct LaunchInfo {
        address token;
        address curve;
        address creator;
        uint256 createdAt;
        uint256 sniperWindow;
    }

    LaunchInfo[] private _launches;
    mapping(address token => uint256 launchIdPlusOne) private _launchByToken;

    struct CreateParams {
        string name;
        string symbol;
        /// @notice Anti-sniper window in seconds (0..1 hour). 0 disables sniper tax entirely.
        uint256 sniperWindow;
    }

    event TokenCreated(
        uint256 indexed launchId, address indexed token, address indexed creator, address curve, uint256 sniperWindow
    );

    error InvalidParams();
    error InvalidAddress();

    constructor(
        FeeSplitter feeSplitter_,
        Graduator graduator_,
        CreatorVesting creatorVesting_,
        address weth_,
        address owner_
    )
        Ownable(owner_)
    {
        if (
            address(feeSplitter_) == address(0) || address(graduator_) == address(0)
                || address(creatorVesting_) == address(0) || weth_ == address(0) || owner_ == address(0)
        ) revert InvalidAddress();
        feeSplitter = feeSplitter_;
        graduator = graduator_;
        creatorVesting = creatorVesting_;
        weth = weth_;
    }

    /// @notice Deploy a new fair-launch token + bonding curve. Caller becomes the creator and
    ///         starts earning 50% of every trade fee, claimable from FeeSplitter.
    function createToken(CreateParams calldata p) external nonReentrant returns (address token, address curve) {
        if (bytes(p.name).length == 0 || bytes(p.symbol).length == 0) revert InvalidParams();
        if (p.sniperWindow > AntiSniper.MAX_WINDOW_SECONDS) revert InvalidParams();

        address creator = msg.sender;

        // 1. Deploy token; full supply minted to the launchpad.
        ZentriaToken tk = new ZentriaToken(p.name, p.symbol, address(this));
        token = address(tk);

        // 2. Deploy curve.
        ZentriaCurve crv = new ZentriaCurve({
            token_: tk,
            weth_: weth,
            graduator_: graduator,
            feeSplitter_: feeSplitter,
            creatorVesting_: creatorVesting,
            launchpad_: address(this),
            creator_: creator,
            sniperWindow_: p.sniperWindow
        });
        curve = address(crv);

        // 3. Register curve with infra so it can accrue fees and graduate.
        feeSplitter.registerCurve(token, curve, creator);
        graduator.registerCurve(token, curve);

        // 4. Move full supply to curve and activate.
        IERC20(token).safeTransfer(curve, tk.TOTAL_SUPPLY());
        crv.activate();

        // 5. Record.
        uint256 launchId = _launches.length;
        _launches.push(
            LaunchInfo({
                token: token, curve: curve, creator: creator, createdAt: block.timestamp, sniperWindow: p.sniperWindow
            })
        );
        _launchByToken[token] = launchId + 1;

        emit TokenCreated(launchId, token, creator, curve, p.sniperWindow);
    }

    function getLaunch(uint256 launchId) external view returns (LaunchInfo memory) {
        return _launches[launchId];
    }

    function getLaunchByToken(address token) external view returns (LaunchInfo memory) {
        uint256 idPlusOne = _launchByToken[token];
        require(idPlusOne != 0, "ZentriaLaunchpad: unknown token");
        return _launches[idPlusOne - 1];
    }

    function totalLaunches() external view returns (uint256) {
        return _launches.length;
    }
}
