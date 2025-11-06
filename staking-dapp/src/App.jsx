import { useState, useEffect } from 'react';
import { ethers } from 'ethers';
import { Web3Modal } from '@web3modal/ethers5';

const CONTRACT = '0x03720cc99a302c101dbd48489a6c2c8bb52d178d';
const CHAIN = 137;
const RPC = `https://polygon-mainnet.infura.io/v3/${import.meta.env.VITE_INFURA_KEY}`;

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

  // Load ABI from public/
  useEffect(() => {
    fetch('/abi.json')
      .then(r => r.json())
      .then(setAbi)
      .catch(() => setError('Failed to load contract ABI'));
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

  // Load public data
  useEffect(() => {
    if (!abi) return;
    const load = async () => {
      const p = new ethers.JsonRpcProvider(RPC);
      const c = new ethers.Contract(CONTRACT, abi, p);
      setContract(c);
      const [a, ts, rp] = await Promise.all([
        c.currentAPY(),
        c.totalStaked(),
        c.rewardPool()
      ]);
      setApy((a / 100).toFixed(2));
      setTotalStaked(ethers.formatEther(ts));
      setRewardPool(ethers.formatEther(rp));
    };
    load();
  }, [abi]);

  const connect = async () => {
    if (!modal || !abi) return;
    setLoading(true);
    try {
      const instance = await modal.connect();
      const p = new ethers.BrowserProvider(instance);
      const s = await p.getSigner();
      const addr = await s.getAddress();
      const net = await p.getNetwork();
      if (Number(net.chainId) !== CHAIN) throw new Error('Switch to Polygon');
      setSigner(s);
      setAccount(addr);
      const c = new ethers.Contract(CONTRACT, abi, s);
      setContract(c);
      await refreshUser(c, addr);
    } catch (e) {
      setError(e.message);
    }
    setLoading(false);
  };

  const refreshUser = async (c, addr) => {
    const [bal, stake, rew] = await Promise.all([
      c.balanceOf(addr),
      c.dogeStakes(addr),
      c.calculateReward(addr)
    ]);
    setBalance(ethers.formatEther(bal));
    setUserStake(ethers.formatEther(stake.amount));
    setPending(ethers.formatEther(rew));
  };

  const stake = async () => {
    setLoading(true);
    try {
      const amt = ethers.parseEther(stakeAmt);
      let tx = await contract.approve(CONTRACT, amt);
      await tx.wait();
      tx = await contract.stake(amt);
      await tx.wait();
      setStakeAmt('');
      await refreshUser(contract, account);
    } catch (e) { setError(e.message); }
    setLoading(false);
  };

  const unstake = async () => {
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
    setLoading(true);
    try {
      const tx = await contract.claimReward();
      await tx.wait();
      await refreshUser(contract, account);
    } catch (e) { setError(e.message); }
    setLoading(false);
  };

  const donate = async () => {
    setLoading(true);
    try {
      const amt = ethers.parseEther(donateAmt);
      let tx = await contract.approve(CONTRACT, amt);
      await tx.wait();
      tx = await contract.donateToPool(amt);
      await tx.wait();
      setDonateAmt('');
      const rp = await contract.rewardPool();
      setRewardPool(ethers.formatEther(rp));
    } catch (e) { setError(e.message); }
    setLoading(false);
  };

  if (!abi) return <div className="text-center py-20">Loading contract...</div>;

  return (
    <div className="min-h-screen bg-gradient-to-b from-[#0A1F3D] to-[#001233] text-white">
      {/* [Rest of UI - unchanged] */}
      {/* ... */}
    </div>
  );
}
