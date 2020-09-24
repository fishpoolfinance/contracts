pragma solidity 0.6.2;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./SharkToken.sol";



// Fishpool is the master of SHARK. He can make SHARK and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once SHARK is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract SharkTank is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of FISHs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accRewardPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accRewardPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;             // Address of LP token contract.
        uint256 allocPoint;         // How many allocation points assigned to this pool. FISHs to distribute per block.
        uint256 lastRewardBlock;    // Last block number that FISHs distribution occurs.
        uint256 accRewardPerShare;   // Accumulated FISHs per share, times 1e18. See below.
    }

    // The SHARK TOKEN!
    SharkToken public SHARK;
    // Dev address.
    address public devaddr;
    // Block number when bonus SHARK period ends.
    uint256 public bonusEndBlock;
    // SHARK tokens created per block.
    uint256 public rewardPerBlock;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when SHARK mining starts.
    uint256 public startBlock;
    // Reduction
    uint256 public reductionBlockCount;
    uint256 public nextReductionBlock = 0;
    uint256 public reductionPercent = 1;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        SharkToken _SHARK,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _reductionCount,
        uint256 _reductionBlockCount
    ) public {
        SHARK = _SHARK;
        rewardPerBlock = _rewardPerBlock;
        startBlock = _startBlock;
        bonusEndBlock = _reductionBlockCount * _reductionCount + _startBlock;
        reductionBlockCount = _reductionBlockCount;
        nextReductionBlock  = _startBlock + _reductionBlockCount;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accRewardPerShare: 0
        }));
    }

    // Update the given pool's SHARK allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Return reward multiplier over the given _from to _to block.
    function getBlocksReward(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_from >= bonusEndBlock) {
            return 0;
        }
        uint256 prevReductionBlock = nextReductionBlock - reductionBlockCount;
        _to = (_to > bonusEndBlock ? bonusEndBlock : _to);

        if (_from >= prevReductionBlock && _to <= nextReductionBlock)
        {
            return (_to - _from) * rewardPerBlock / reductionPercent;
        }
        else if (_from < prevReductionBlock && _to < nextReductionBlock)
        {
            uint256 part1 = (_to - prevReductionBlock) * rewardPerBlock / reductionPercent;
            uint256 part2 = (prevReductionBlock - _from) * rewardPerBlock / reductionPercent * 2;
            return part1 + part2;
        }
        else
        {
            uint256 part1 = (_to - nextReductionBlock) * rewardPerBlock / reductionPercent / 2;
            uint256 part2 = (nextReductionBlock - _from) * rewardPerBlock / reductionPercent;
            return part1 + part2;
        }
        // return 0;
    }

    // View function to see pending FISHs on frontend.
    function pendingReward(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 blockReward = getBlocksReward(pool.lastRewardBlock, block.number);
            uint256 poolReward = blockReward.mul(pool.allocPoint).div(totalAllocPoint);
            accRewardPerShare = accRewardPerShare.add(poolReward.mul(1e18).div(lpSupply));
        }
        return user.amount.mul(accRewardPerShare).div(1e18).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        if (block.number > nextReductionBlock && nextReductionBlock < bonusEndBlock){
            nextReductionBlock += reductionBlockCount;
            reductionPercent *= 2;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 blockReward = getBlocksReward(pool.lastRewardBlock, block.number);
        uint256 poolReward = blockReward.mul(pool.allocPoint).div(totalAllocPoint);
        SHARK.mint(address(this), poolReward);
        pool.accRewardPerShare = pool.accRewardPerShare.add(poolReward.mul(1e18).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to Fishpool for SHARK allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accRewardPerShare).div(1e18).sub(user.rewardDebt);
            if(pending > 0) {
                safeTokenTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e18);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from Fishpool.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accRewardPerShare).div(1e18).sub(user.rewardDebt);
        if(pending > 0) {
            safeTokenTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e18);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe SHARK transfer function, just in case if rounding error causes pool to not have enough FISHs.
    function safeTokenTransfer(address _to, uint256 _amount) internal {
        uint256 bal = SHARK.balanceOf(address(this));
        if (_amount > bal) {
            SHARK.transfer(_to, bal);
        } else {
            SHARK.transfer(_to, _amount);
        }
    }
}
