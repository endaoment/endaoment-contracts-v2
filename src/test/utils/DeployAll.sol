// SPDX-License-Identifier: BSD 3-Clause
pragma solidity 0.8.13;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import "../../Registry.sol";
import "../../OrgFundFactory.sol";
import {NDAO} from "../../NDAO.sol";
import {NVT, INDAO} from "../../NVT.sol";
import {RollingMerkleDistributor} from "../../RollingMerkleDistributor.sol";
import "../../lib/Math.sol";

/**
 * @dev Deploys Endaoment contracts
 * @dev Test harness
 */
contract DeployAll {
    address immutable self;
    uint256 constant MAX_UINT = type(uint256).max;
    address constant board = address(0xb042d);
    address constant treasury = address(0xface);
    address constant user1 = address(0xabc1);
    address constant user2 = address(0xabc2);
    address constant capitalCommittee = address(0xccc);
    address constant programCommittee = address(0xddd);
    address constant investmentCommittee = address(0xeee);
    address constant tokenTrust = address(0x7ab1e);

    // used by RollingMerkleDistributor
    bytes32 initialRoot = "beef_cafe";
    uint256 initialPeriod = 60 days;

    Registry globalTestRegistry;
    OrgFundFactory orgFundFactory;
    MockERC20 baseToken;
    NDAO ndao;
    NVT nvt;
    RollingMerkleDistributor distributor;
    RollingMerkleDistributor baseDistributor;

    constructor() {
        self = address(this); // convenience
        setUp(); // support echidna
    }

    function setUp() public virtual {
        if (baseToken == MockERC20(address(0))) {
            baseToken = new MockERC20("USD Coin", "USDC", 6);
        }
        globalTestRegistry = new Registry(board, treasury, baseToken);
        orgFundFactory = new OrgFundFactory(globalTestRegistry);
        ndao = new NDAO(globalTestRegistry);
        nvt = new NVT(INDAO(address(ndao)), globalTestRegistry);
        distributor =
            new RollingMerkleDistributor(IERC20(address(ndao)), initialRoot, initialPeriod, globalTestRegistry);
        baseDistributor =
            new RollingMerkleDistributor(IERC20(address(baseToken)), initialRoot, initialPeriod, globalTestRegistry);
    }
}
