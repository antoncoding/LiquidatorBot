pragma solidity 0.5.10;

import "./FlashLoanReceiverBase.sol";
import "./OptionsContract.sol";
import "./OptionsExchange.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./ILendingPoolAddressesProvider.sol";


contract Liquidator is FlashLoanReceiverBase {
    using SafeMath for uint256;

    constructor(ILendingPoolAddressesProvider ILendingAddress)
        public
        FlashLoanReceiverBase(ILendingAddress)
    {}

    function executeOperation(
        address _reserve,
        uint256 _amount,
        uint256 _fee,
        bytes calldata _params
    ) external {
        (address oTokenAddr, address vaultAddr) = getParams(_params);
        address payable vaultOwner = address(uint160(vaultAddr));
        OptionsContract oToken = OptionsContract(oTokenAddr);
        // 1. Get _amount from the reserve pool
        // 2. Buy oTokens on uniswap
        uint256 oTokensToBuy = oToken.maxOTokensLiquidatable(vaultOwner);
        require(oTokensToBuy > 0, "cannot liquidate a safe vault");

        OptionsExchange exchange = OptionsExchange(oToken.optionsExchange());
        exchange.buyOTokens.value(_amount)(
            address(uint160(address(this))),
            oTokenAddr,
            address(0),
            oTokensToBuy
        );
        // 3. Liquidate
        oToken.liquidate(vaultOwner, oTokensToBuy);
        // 4. pay back the $
        transferFundsBackToPoolInternal(_reserve, _amount.add(_fee));
        // 5. pay the user who liquidated
        tx.origin.transfer(address(this).balance);
    }

    function bytesToAddress(bytes memory bys)
        private
        pure
        returns (address addr)
    {
        //solium-disable-next-line
        assembly {
            addr := mload(add(bys, 20))
        }
    }

    function getParams(bytes memory source)
        public
        pure
        returns (address, address)
    {
        bytes memory half1 = new bytes(20);
        bytes memory half2 = new bytes(20);
        for (uint256 j = 0; j < 20; j++) {
            half1[j] = source[j];
            half2[j] = source[j + 20];
        }
        return (bytesToAddress(half1), bytesToAddress(half2));
    }
}
