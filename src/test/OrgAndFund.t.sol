// SPDX-License-Identifier: BSD 3-Claused
pragma solidity ^0.8.12;
import "./utils/DeployTest.sol";
import "../Registry.sol";

import "../Org.sol";
import "../Fund.sol";

contract OrgTest is DeployTest {
}

contract OrgConstructor is OrgTest {
    function testFuzz_OrgConstructor(bytes32 _orgId) public {
        Org _org = new Org(globalTestRegistry, _orgId);
        assertEq(_org.entityType(), 1);
    }
}

contract FundTest is DeployTest {
}

contract FundConstructor is FundTest {
    function testFuzz_FundConstructor(address _manager) public {
        Fund _fund = new Fund(globalTestRegistry, _manager);
        assertEq(_fund.entityType(), 2);
    }
}

