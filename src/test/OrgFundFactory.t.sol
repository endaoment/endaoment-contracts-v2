// SPDX-License-Identifier: BSD 3-Clause
pragma solidity 0.8.13;

import "./utils/DeployTest.sol";
import "../Registry.sol";

import {OrgFundFactory} from "../OrgFundFactory.sol";
import {Org} from "../Org.sol";
import {Fund} from "../Fund.sol";
import {MockSwapperTestHarness} from "./utils/MockSwapperTestHarness.sol";

contract OrgFundFactoryTest is MockSwapperTestHarness {
    event EntityDeployed(address indexed entity, uint8 indexed entityType, address indexed entityManager);
}

contract OrgFundFactoryConstructor is OrgFundFactoryTest {
    function test_OrgFundFactoryConstructor() public {
        OrgFundFactory _orgFundFactory = new OrgFundFactory(globalTestRegistry);
        assertEq(_orgFundFactory.registry(), globalTestRegistry);
    }
}

contract OrgFundFactoryDeployOrgTest is OrgFundFactoryTest {
    function testFuzz_DeployOrg(bytes32 _orgId) public {
        address _expectedContractAddress = orgFundFactory.computeOrgAddress(_orgId);
        vm.expectEmit(true, true, true, false);
        emit EntityDeployed(_expectedContractAddress, 1, address(0));
        Org _org = orgFundFactory.deployOrg(_orgId);
        assertEq(_org.orgId(), _orgId);
        assertEq(globalTestRegistry, _org.registry());
        assertEq(_org.entityType(), 1);
        assertEq(_org.manager(), address(0));
        assertEq(_expectedContractAddress, address(_org));
    }

    function testFuzz_DeployOrgFailDuplicate(bytes32 _orgId) public {
        orgFundFactory.deployOrg(_orgId);
        vm.expectRevert("ERC1167: create2 failed");
        orgFundFactory.deployOrg(_orgId);
    }

    function testFuzz_DeployOrgFailNonWhiteListedFactory(bytes32 _orgId) public {
        OrgFundFactory orgFundFactory2 = new OrgFundFactory(globalTestRegistry);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        orgFundFactory2.deployOrg(_orgId);
    }

    function testFuzz_DeployOrgFailAfterUnwhitelisting(bytes32 _orgId) public {
        vm.assume(_orgId != "1234");
        orgFundFactory.deployOrg(_orgId);
        vm.prank(board);
        globalTestRegistry.setFactoryApproval(address(orgFundFactory), false);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        orgFundFactory.deployOrg("1234");
    }

    function testFuzz_DeployOrgFromFactory2(bytes32 _orgId) public {
        OrgFundFactory orgFundFactory2 = new OrgFundFactory(globalTestRegistry);
        vm.prank(board);
        globalTestRegistry.setFactoryApproval(address(orgFundFactory2), true);
        address _expectedContractAddress = orgFundFactory2.computeOrgAddress(_orgId);
        vm.expectEmit(true, true, true, false);
        emit EntityDeployed(_expectedContractAddress, 1, address(0));
        Org _org = orgFundFactory2.deployOrg(_orgId);
        assertEq(_org.orgId(), _orgId);
        assertEq(globalTestRegistry, _org.registry());
        assertEq(_org.entityType(), 1);
        assertEq(_expectedContractAddress, address(_org));
    }

    function testFuzz_DeployOrgAndDonate(bytes32 _orgId, address _sender, uint256 _amount) public {
        vm.assume(_sender != address(orgFundFactory));

        // Give the sender tokens & approve the factory to spend them.
        baseToken.mint(_sender, _amount);
        vm.prank(_sender);
        baseToken.approve(address(orgFundFactory), _amount);

        // Enable Org donations with no fee.
        vm.prank(board);
        globalTestRegistry.setDefaultDonationFee(1, 0);
        address _expectedAddress = orgFundFactory.computeOrgAddress(_orgId);

        // Deploy and donate.
        vm.prank(_sender);
        Org _org = orgFundFactory.deployOrgAndDonate(_orgId, _amount);

        assertEq(_expectedAddress, address(_org));
        assertEq(baseToken.balanceOf(address(_org)), _amount);
        assertEq(_org.balance(), _amount);
    }

    function testFuzz_DeployOrgSwapAndDonate(
        bytes32 _orgId,
        address _sender,
        uint256 _donationAmount,
        uint256 _amountOut
    ) public {
        vm.assume(_sender != address(orgFundFactory));
        mockSwapWrapper.setAmountOut(_amountOut);

        // Mint and approve test tokens to donor.
        testToken1.mint(_sender, _donationAmount);
        vm.prank(_sender);
        testToken1.approve(address(orgFundFactory), _donationAmount);

        // Enable Org donations with no fee.
        vm.prank(board);
        globalTestRegistry.setDefaultDonationFee(1, 0);
        address _expectedAddress = orgFundFactory.computeOrgAddress(_orgId);

        // Deploy, swap and donate.
        vm.prank(_sender);
        Org _org =
            orgFundFactory.deployOrgSwapAndDonate(_orgId, mockSwapWrapper, address(testToken1), _donationAmount, "");

        assertEq(_expectedAddress, address(_org));
        assertEq(baseToken.balanceOf(address(_org)), mockSwapWrapper.amountOut());
        assertEq(_org.balance(), mockSwapWrapper.amountOut());
    }

    function testFuzz_DeployOrgSwapAndDonateEth(
        bytes32 _orgId,
        address _sender,
        uint256 _donationAmount,
        uint256 _amountOut
    ) public {
        vm.assume(_sender != address(orgFundFactory));
        _donationAmount = bound(1, _donationAmount, type(uint256).max);
        mockSwapWrapper.setAmountOut(_amountOut);

        // Give ETH to donor.
        vm.deal(_sender, _donationAmount);

        // Enable Org donations with no fee.
        vm.prank(board);
        globalTestRegistry.setDefaultDonationFee(1, 0);
        address _expectedAddress = orgFundFactory.computeOrgAddress(_orgId);

        // Deploy, swap and donate.
        vm.prank(_sender);
        Org _org = orgFundFactory.deployOrgSwapAndDonate{value: _donationAmount}(
            _orgId,
            mockSwapWrapper,
            0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, // ETH Placeholder address
            _donationAmount,
            ""
        );

        assertEq(_expectedAddress, address(_org));
        assertEq(baseToken.balanceOf(address(_org)), mockSwapWrapper.amountOut());
        assertEq(_org.balance(), mockSwapWrapper.amountOut());
    }
}

contract OrgFundFactoryDeployFundTest is OrgFundFactoryTest {
    function testFuzz_DeployFund(address _manager, bytes32 _salt) public {
        address _expectedContractAddress = orgFundFactory.computeFundAddress(_manager, _salt);
        vm.expectEmit(true, true, true, false);
        emit EntityDeployed(_expectedContractAddress, 2, _manager);
        Fund _fund = orgFundFactory.deployFund(_manager, _salt);
        assertEq(globalTestRegistry, _fund.registry());
        assertEq(_fund.entityType(), 2);
        assertEq(_fund.manager(), _manager);
        assertEq(_expectedContractAddress, address(_fund));
    }

    function testFuzz_DeployFundDuplicateFail(address _manager, bytes32 _salt) public {
        orgFundFactory.deployFund(_manager, _salt);
        vm.expectRevert("ERC1167: create2 failed");
        orgFundFactory.deployFund(_manager, _salt);
    }

    function testFuzz_DeployFundFailNonWhiteListedFactory(address _manager, bytes32 _salt) public {
        OrgFundFactory orgFundFactory2 = new OrgFundFactory(globalTestRegistry);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        orgFundFactory2.deployFund(_manager, _salt);
    }

    function testFuzz_DeployFundFailAfterUnwhitelisting(address _manager, bytes32 _salt) public {
        bytes32 _salt2 = keccak256(abi.encode(_salt));
        vm.assume(_manager != address(1234));
        orgFundFactory.deployFund(_manager, _salt);
        vm.prank(board);
        globalTestRegistry.setFactoryApproval(address(orgFundFactory), false);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        orgFundFactory.deployFund(address(1234), _salt2);
    }

    function testFuzz_DeployFundFromFactory2(address _manager, bytes32 _salt) public {
        OrgFundFactory orgFundFactory2 = new OrgFundFactory(globalTestRegistry);
        vm.prank(board);
        globalTestRegistry.setFactoryApproval(address(orgFundFactory2), true);
        address _expectedContractAddress = orgFundFactory2.computeFundAddress(_manager, _salt);
        vm.expectEmit(true, true, true, false);
        emit EntityDeployed(_expectedContractAddress, 2, _manager);
        Fund _fund = orgFundFactory2.deployFund(_manager, _salt);
        assertEq(globalTestRegistry, _fund.registry());
        assertEq(_fund.entityType(), 2);
        assertEq(_expectedContractAddress, address(_fund));
    }

    function testFuzz_DeployFundAndDonate(address _manager, bytes32 _salt, address _sender, uint256 _amount) public {
        vm.assume(_sender != address(orgFundFactory));

        // Give the sender tokens & approve the factory to spend them.
        baseToken.mint(_sender, _amount);
        vm.prank(_sender);
        baseToken.approve(address(orgFundFactory), _amount);

        // Enable Fund donations with no fee.
        vm.prank(board);
        globalTestRegistry.setDefaultDonationFee(2, 0);
        address _expectedAddress = orgFundFactory.computeFundAddress(_manager, _salt);

        // Deploy and donate.
        vm.prank(_sender);
        Fund _fund = orgFundFactory.deployFundAndDonate(_manager, _salt, _amount);

        assertEq(_expectedAddress, address(_fund));
        assertEq(_fund.manager(), _manager);
        assertEq(baseToken.balanceOf(address(_fund)), _amount);
        assertEq(_fund.balance(), _amount);
    }

    function testFuzz_DeployFundSwapAndDonate(
        address _manager,
        bytes32 _salt,
        address _sender,
        uint256 _donationAmount,
        uint256 _amountOut
    ) public {
        vm.assume(_sender != address(orgFundFactory));
        mockSwapWrapper.setAmountOut(_amountOut);

        // Mint and approve test tokens to donor.
        testToken1.mint(_sender, _donationAmount);
        vm.prank(_sender);
        testToken1.approve(address(orgFundFactory), _donationAmount);

        // Enable Fund donations with no fee.
        vm.prank(board);
        globalTestRegistry.setDefaultDonationFee(2, 0);
        address _expectedAddress = orgFundFactory.computeFundAddress(_manager, _salt);

        // Deploy, swap and donate.
        vm.prank(_sender);
        Fund _fund = orgFundFactory.deployFundSwapAndDonate(
            _manager, _salt, mockSwapWrapper, address(testToken1), _donationAmount, ""
        );

        assertEq(_expectedAddress, address(_fund));
        assertEq(baseToken.balanceOf(address(_fund)), mockSwapWrapper.amountOut());
        assertEq(_fund.balance(), mockSwapWrapper.amountOut());
    }

    function testFuzz_DeployFundSwapAndDonateEth(
        address _manager,
        bytes32 _salt,
        address _sender,
        uint256 _donationAmount,
        uint256 _amountOut
    ) public {
        vm.assume(_sender != address(orgFundFactory));
        _donationAmount = bound(1, _donationAmount, type(uint256).max);
        mockSwapWrapper.setAmountOut(_amountOut);

        // Give ETH to donor.
        vm.deal(_sender, _donationAmount);

        // Enable Fund donations with no fee.
        vm.prank(board);
        globalTestRegistry.setDefaultDonationFee(2, 0);
        address _expectedAddress = orgFundFactory.computeFundAddress(_manager, _salt);

        // Deploy, swap and donate.
        vm.prank(_sender);
        Fund _fund = orgFundFactory.deployFundSwapAndDonate{value: _donationAmount}(
            _manager,
            _salt,
            mockSwapWrapper,
            0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, // ETH Placeholder address
            _donationAmount,
            ""
        );

        assertEq(_expectedAddress, address(_fund));
        assertEq(baseToken.balanceOf(address(_fund)), mockSwapWrapper.amountOut());
        assertEq(_fund.balance(), mockSwapWrapper.amountOut());
    }
}
