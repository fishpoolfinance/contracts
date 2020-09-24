pragma solidity 0.6.2;


import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract SharkToken is ERC20("SHARK", "SHARK"), Ownable {
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }

    constructor(
        uint256 supply
    ) public {
        _mint(msg.sender, supply * (10 ** uint256(decimals())));
    }
}
