import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockERC20 is ERC20, Ownable {
    uint8 private _customDecimals = 6;

    // Primary constructor with custom decimals
    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) Ownable(msg.sender) {
        _customDecimals = decimals_;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function decimals() public view override returns (uint8) {
        return _customDecimals;
    }
}
