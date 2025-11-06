import { useState, useEffect } from 'react';
import { ethers } from 'ethers';
import { Web3Modal } from '@web3modal/ethers5';

const CONTRACT_ADDRESS = '0x03720cc99a302c101dbd48489a6c2c8bb52d178d';
const CHAIN_ID = 137;
const RPC_URL = `https://polygon-mainnet.infura.io/v3/${import.meta.env.VITE_INFURA_KEY}`;

export default function App() {
  const [abi, setAbi] = useState(null);
  const [modal, setModal] = useState(null);
  const [account, setAccount] = useState('');
  const [signer, setSigner] = useState(null);
  const [contract, setContract] = useState(null);
  const [balance, setBalance] = useState('0');
  const [apy, setApy] = useState('0');
  const [totalStaked, setTotalStaked] = useState('0');
  const [rewardPool, setRewardPool] = useState('0');
  const [userStake, setUserStake] = useState('0');
  const [pending, setPending] = useState('0');
  const [stakeAmt, setStakeAmt] = useState('');
  const [unstakeAmt, setUnstakeAmt] = useState('');
  const [donateAmt, setDonateAmt] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [menuOpen, setMenuOpen] = useState(false);

  // Load ABI from public
  useEffect(() => {
    fetch('/abi.json')
      .then(r => r.json())
      .then(setAbi)
      .catch(() => setError('Failed to load ABI'));
  }, []);

  // Init Web3Modal
  useEffect(() => {
    const init = async () => {
      const m = new Web3Modal({
        projectId: import.meta.env.VITE_WALLET_CONNECT_PROJECT_ID,
        themeMode: 'dark'
      });
      setModal(m);
    };
    init();
  }, []);

  // Load public data ONLY after ABI
  useEffect(() => {
    if (!abi) return;

    const load = async () => {
      const provider = new ethers.JsonRpcProvider(RPC_URL);
      const c = new ethers.Contract(CONTRACT_ADDRESS, abi, provider);
      setContract(c);

      try {
        const [a, ts, rp] = await Promise.all([
          c.currentAPY(),
          c.totalStaked(),
          c.rewardPool()
        ]);
        setApy((Number(a) / 100).toFixed(2));
        setTotalStaked(ethers.formatEther(ts));
        setRewardPool(ethers.formatEther(rp));
      } catch (e) {
        setError('Failed to load stats');
      }
    };

    load();
  }, [abi]); // ← Only runs when abi is loaded

  const connect = async () => {
    if (!modal || !abi) return;
    setLoading(true);
    try {
      const instance = await modal.connect();
      const provider = new ethers.BrowserProvider(instance);
      const s = await provider.getSigner();
      const addr = await s.getAddress();
      const net = await provider.getNetwork();
      if (Number(net.chainId) !== CHAIN_ID) throw new Error('Switch to Polygon');
      setSigner(s);
      setAccount(addr);
      const c = new ethers.Contract(CONTRACT_ADDRESS, abi, s);
      setContract(c);
      await refreshUser(c, addr);
    } catch (e) {
      setError(e.message);
    }
    setLoading(false);
  };

  const refreshUser = async (c, addr) => {
    try {
      const [bal, stake, rew] = await Promise.all([
        c.balanceOf(addr),
        c.dogeStakes(addr),
        c.calculateReward(addr)
      ]);
      setBalance(ethers.formatEther(bal));
      setUserStake(ethers.formatEther(stake.amount));
      setPending(ethers.formatEther(rew));
    } catch (e) {
      setError('Failed to refresh');
    }
  };

  const stake = async () => {
    if (!contract || !stakeAmt) return;
    setLoading(true);
    try {
      const amt = ethers.parseEther(stakeAmt);
      let tx = await contract.approve(CONTRACT_ADDRESS, amt);
      await tx.wait();
      tx = await contract.stake(amt);
      await tx.wait();
      setStakeAmt('');
      await refreshUser(contract, account);
    } catch (e) { setError(e.message); }
    setLoading(false);
  };

  const unstake = async () => {
    if (!contract || !unstakeAmt) return;
    setLoading(true);
    try {
      const amt = ethers.parseEther(unstakeAmt);
      const tx = await contract.unstake(amt);
      await tx.wait();
      setUnstakeAmt('');
      await refreshUser(contract, account);
    } catch (e) { setError(e.message); }
    setLoading(false);
  };

  const claim = async () => {
    if (!contract) return;
    setLoading(true);
    try {
      const tx = await contract.claimReward();
      await tx.wait();
      await refreshUser(contract, account);
    } catch (e) { setError(e.message); }
    setLoading(false);
  };

  const donate = async () => {
    if (!contract || !donateAmt) return;
    setLoading(true);
    try {
      const amt = ethers.parseEther(donateAmt);
      let tx = await contract.approve(CONTRACT_ADDRESS, amt);
      await tx.wait();
      tx = await contract.donateToPool(amt);
      await tx.wait();
      setDonateAmt('');
      const rp = await contract.rewardPool();
      setRewardPool(ethers.formatEther(rp));
    } catch (e) { setError(e.message); }
    setLoading(false);
  };

  if (!abi) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gradient-to-b from-[#0A1F3D] to-[#001233] text-white">
        <p className="text-xl">Loading contract...</p>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gradient-to-b from-[#0A1F3D] to-[#001233] text-white">
      {/* [Full UI - unchanged, mobile-responsive] */}
      {/* Header, Hero, Stats, Dashboard, Footer */}
      {/* ... */}
    </div>
  );
}
