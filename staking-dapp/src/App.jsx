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

  // Load ABI
  useEffect(() => {
    fetch('/abi.json')
      .then(r => r.json())
      .then(setAbi)
      .catch(() => setError('Failed to load ABI'));
  }, []);

  // Init Web3Modal
  useEffect(() => {
    const init = async () => {
      try {
        const m = new Web3Modal({
          projectId: import.meta.env.VITE_WALLET_CONNECT_PROJECT_ID,
          themeMode: 'dark'
        });
        setModal(m);
      } catch (e) {
        setError('Failed to init wallet');
      }
    };
    init();
  }, []);

  // Load public stats ONLY after ABI
  useEffect(() => {
    if (!abi) return;

    const load = async () => {
      try {
        const provider = new ethers.JsonRpcProvider(RPC_URL);
        const c = new ethers.Contract(CONTRACT_ADDRESS, abi, provider);
        setContract(c);

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
  }, [abi]);

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

  // Loading state
  if (!abi) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gradient-to-b from-[#0A1F3D] to-[#001233] text-white">
        <p className="text-xl">Loading contract...</p>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gradient-to-b from-[#0A1F3D] to-[#001233] text-white">
      {/* Header */}
      <header className="fixed top-0 left-0 right-0 z-50 bg-[#001233]/90 backdrop-blur-md border-b border-cyan-800">
        <div className="container mx-auto px-4 py-4 flex justify-between items-center">
          <a href="/" className="text-2xl font-bold text-cyan-400">DogeRocket</a>
          <nav className="hidden md:flex space-x-6">
            <a href="#stats" className="hover:text-cyan-300">Stats</a>
            <a href="#staking" className="hover:text-cyan-300">Stake</a>
            <a href="https://polygonscan.com/token/0x03720cc99a302c101dbd48489a6c2c8bb52d178d" className="hover:text-cyan-300">Contract</a>
          </nav>
          <button
            onClick={connect}
            disabled={loading}
            className="bg-gradient-to-r from-cyan-500 to-blue-600 hover:from-cyan-400 hover:to-blue-500 px-5 py-2 rounded-full font-bold text-sm"
          >
            {loading ? '...' : account ? `${account.slice(0, 6)}...${account.slice(-4)}` : 'Connect'}
          </button>
          <button onClick={() => setMenuOpen(!menuOpen)} className="md:hidden">
            <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d={menuOpen ? "M6 18L18 6M6 6l12 12" : "M4 6h16M4 12h16M4 18h16"} />
            </svg>
          </button>
        </div>
        {menuOpen && (
          <nav className="md:hidden bg-[#001233]/95 px-4 py-6 space-y-4">
            <a href="#stats" className="block hover:text-cyan-300">Stats</a>
            <a href="#staking" className="block hover:text-cyan-300">Stake</a>
            <a href="https://polygonscan.com/token/0x03720cc99a302c101dbd48489a6c2c8bb52d178d" className="block hover:text-cyan-300">Contract</a>
          </nav>
        )}
      </header>

      {/* Hero */}
      <section className="pt-24 pb-12 px-4 text-center">
        <img src="https://gray-past-falcon-384.mypinata.cloud/ipfs/bafkreign7g276yq7ss6cqo7gtnrbvwrh5qbxmhgboamwdoiy5sv5lo6j4i" alt="DRKT" className="mx-auto w-24 h-24 rounded-full border-4 border-cyan-400" />
        <h1 className="mt-6 text-4xl sm:text-5xl md:text-6xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-cyan-400 to-blue-500">
          300% Rocket Booster
        </h1>
        <p className="mt-4 text-lg sm:text-xl text-cyan-200">Stake DRKT • Earn Up To 300% APY</p>
        <div className="mt-8 flex flex-col sm:flex-row gap-4 justify-center">
          <a href="#staking" className="bg-cyan-500 hover:bg-cyan-400 text-black font-bold py-4 px-8 rounded-full text-xl">
            Stake Now
          </a>
          <a href="https://quickswap.exchange/swap?outputCurrency=0x03720cc99a302c101dbd48489a6c2c8bb52d178d" className="bg-purple-600 hover:bg-purple-500 font-bold py-4 px-8 rounded-full text-xl">
            Buy DRKT
          </a>
        </div>
      </section>

      {/* Stats */}
      <section id="stats" className="container mx-auto px-4 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6 my-12">
        {[
          { label: 'Current APY', value: `${apy}%` },
          { label: 'Total Staked', value: `${Number(totalStaked).toLocaleString()} DRKT` },
          { label: 'Reward Pool', value: `${Number(rewardPool).toLocaleString()} DRKT` },
          { label: 'Holders', value: '10K+' }
        ].map((s, i) => (
          <div key={i} className="bg-white/10 backdrop-blur rounded-2xl p-6 text-center border border-cyan-500/30">
            <p className="text-cyan-300 text-sm">{s.label}</p>
            <p className="text-3xl font-bold mt-2">{s.value}</p>
          </div>
        ))}
      </section>

      {/* Dashboard */}
      {account ? (
        <section id="staking" className="container mx-auto px-4 py-12">
          <h2 className="text-3xl font-bold text-center mb-8">Your Dashboard</h2>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-6 mb-10">
            {[
              { label: 'Wallet', value: `${Number(balance).toFixed(2)} DRKT` },
              { label: 'Staked', value: `${Number(userStake).toFixed(2)} DRKT` },
              { label: 'Rewards', value: `${Number(pending).toFixed(2)} DRKT` }
            ].map((c, i) => (
              <div key={i} className="bg-gradient-to-br from-cyan-600/20 to-blue-600/20 rounded-2xl p-6 border border-cyan-400/50 text-center">
                <p className="text-cyan-300">{c.label}</p>
                <p className="text-2xl font-bold">{c.value}</p>
              </div>
            ))}
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
            <div className="bg-white/10 rounded-2xl p-6 border border-cyan-500/30">
              <label className="block text-cyan-300 mb-2">Stake</label>
              <input value={stakeAmt} onChange={e => setStakeAmt(e.target.value)} placeholder="100" className="w-full p-3 rounded bg-white/20 text-white placeholder-gray-400 mb-3" />
              <button onClick={stake} disabled={loading} className="w-full bg-cyan-500 hover:bg-cyan-400 text-black font-bold py-3 rounded">
                {loading ? '...' : 'Stake'}
              </button>
            </div>
            <div className="bg-white/10 rounded-2xl p-6 border border-cyan-500/30">
              <label className="block text-cyan-300 mb-2">Unstake</label>
              <input value={unstakeAmt} onChange={e => setUnstakeAmt(e.target.value)} placeholder="100" className="w-full p-3 rounded bg-white/20 text-white placeholder-gray-400 mb-3" />
              <button onClick={unstake} disabled={loading} className="w-full bg-red-600 hover:bg-red-500 font-bold py-3 rounded">
                {loading ? '...' : 'Unstake (2% fee)'}
              </button>
            </div>
            <div className="bg-white/10 rounded-2xl p-6 border border-cyan-500/30">
              <label className="block text-cyan-300 mb-2">Donate</label>
              <input value={donateAmt} onChange={e => setDonateAmt(e.target.value)} placeholder="100" className="w-full p-3 rounded bg-white/20 text-white placeholder-gray-400 mb-3" />
              <button onClick={donate} disabled={loading} className="w-full bg-purple-600 hover:bg-purple-500 font-bold py-3 rounded">
                {loading ? '...' : 'Donate'}
              </button>
            </div>
            <div className="bg-white/10 rounded-2xl p-6 border border-cyan-500/30">
              <p className="text-cyan-300 mb-4">Claim Rewards</p>
              <button onClick={claim} disabled={loading} className="w-full bg-gradient-to-r from-green-500 to-teal-600 hover:from-green-400 hover:to-teal-500 font-bold py-8 rounded text-xl">
                {loading ? 'Claiming...' : `Claim ${Number(pending).toFixed(2)} DRKT`}
              </button>
            </div>
          </div>
          {error && <p className="text-red-400 text-center mt-6">{error}</p>}
        </section>
      ) : (
        <section className="text-center py-20">
          <p className="text-2xl mb-8">Connect wallet to start staking</p>
          <button onClick={connect} className="bg-gradient-to-r from-cyan-500 to-blue-600 hover:from-cyan-400 hover:to-blue-500 px-12 py-6 rounded-full text-2xl font-bold">
            Connect Wallet
          </button>
        </section>
      )}

      <footer className="text-center py-12 text-gray-400 text-sm">
        <p>© 2025 DogeRocket – All Rights Reserved</p>
        <div className="flex justify-center gap-6 mt-4">
          <a href="https://x.com/DRKTDogeRocket" className="hover:text-cyan-300">Twitter</a>
          <a href="https://discord.gg/9QQ8FmY6nq" className="hover:text-cyan-300">Discord</a>
        </div>
      </footer>
    </div>
  );
}
