pragma solidity 0.6.2;


import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract PreFishToken is ERC20("Pre FISH", "PFISH") {
    constructor(
        uint256 supply
    ) public {
        _mint(msg.sender, supply * (10 ** uint256(decimals())));
    }
}
