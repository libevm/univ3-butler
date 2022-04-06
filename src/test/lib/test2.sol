// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "ds-test/test.sol";

contract DSTest2 is DSTest {
    function assertApproxEq(
        uint256 a,
        uint256 b,
        uint256 delta
    ) internal {
        uint256 larger = a > b ? a : b;
        uint256 smaller = a < b ? a : b;

        if (larger - smaller > delta) {
            emit log("Error: a ~ b not satisfied");
            emit log_named_uint("  Value a", a);
            emit log_named_uint("  Value b", b);
            emit log_named_uint("  Value delta", delta);
            fail();
        }
    }
}
