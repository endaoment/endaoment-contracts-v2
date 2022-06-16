// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;

import { RolesAndCapabilitiesControl } from "../../RolesAndCapabilitiesControl.sol";
import "./DeployAll.sol";
import "./DSTestPlus.sol";
import { ISwapWrapper } from "../../interfaces/ISwapWrapper.sol";
import { UniV3Wrapper } from "../../swapWrappers/UniV3Wrapper.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";

/**
 * @dev Adds additional config after deployment to facilitate testing
 */
contract DeployTest is DeployAll, DSTestPlus, RolesAndCapabilitiesControl {
  using stdStorage for StdStorage;

  // Entity Types
  uint8 public constant OrgType = 1;
  uint8 public constant FundType = 2;

  uint256 public constant MIN_ENTITY_TRANSACTION_AMOUNT = 5; // 0.0005 cents USDC
  uint256 public constant MAX_ENTITY_TRANSACTION_AMOUNT = 1_000_000_000_000_000; // $1 Billion USDC

  // Uni v3 swap wrapper
  address public uniV3SwapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
  ISwapWrapper uniV3SwapWrapper;

  // Curve swap wrapper
  address public curveExchange = 0x81C46fECa27B31F3ADC2b91eE4be9717d1cd3DD7;
  ISwapWrapper curveSwapWrapper;

  // multiswap wrapper
  ISwapWrapper multiSwapWrapper;

  function setUp() public virtual override {
    super.setUp();

    vm.label(board, "board");
    vm.label(user1, "user1");
    vm.label(user2, "user2");
    vm.label(treasury, "treasury");
    vm.label(capitalCommittee, "capital committee");
    vm.label(tokenTrust, "token trust");
    vm.label(uniV3SwapRouter, "uniV3 swap router");
    vm.label(address(ndao), "NDAO");
    vm.label(address(nvt), "NVT");
    vm.label(address(distributor), "distributor");
    vm.label(address(baseDistributor), "base distributor");

    vm.startPrank(board);

    globalTestRegistry.setFactoryApproval(address(orgFundFactory), true);

    setRolesAndCapabilities(globalTestRegistry, capitalCommittee, programCommittee, investmentCommittee, tokenTrust,
                            ndao, nvt, distributor, baseDistributor);

    vm.stopPrank();
  }

  // local helper function to set an entity's contract balance and token balance
  function _setEntityBalance(Entity _entity, uint256 _newBalance) internal {
      stdstore
          .target(address(_entity))
          .sig(_entity.balance.selector)
          .checked_write(_newBalance);
      ERC20 _baseToken = globalTestRegistry.baseToken();
      deal(address(_baseToken), address(_entity), _newBalance);
  }

  // local helper function to set an entity's contract balance
  function _setEntityContractBalance(Entity _entity, uint256 _newBalance) internal {
      stdstore
          .target(address(_entity))
          .sig(_entity.balance.selector)
          .checked_write(_newBalance);
  }
}
