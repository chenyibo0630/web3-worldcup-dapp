import { useMemo, useState } from "react";
import {
  useAccount,
  useConnect,
  useDisconnect,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
  useBalance,
} from "wagmi";
import { formatEther, parseEther } from "viem";
import {
  TEAMS,
  TEAM_COUNT,
  CONFEDERATIONS,
  flagUrl,
  type Confederation,
  type Team,
} from "./teams";
import { BET_DEADLINE, formatDeadline } from "./schedule";
import { GUESS_CHAMPION_ABI, GUESS_CHAMPION_ADDRESS } from "./contract";

export default function App() {
  const [selectedId, setSelectedId] = useState<number | null>(null);

  const grouped = useMemo(() => {
    const map = new Map<Confederation, Team[]>();
    for (const team of TEAMS) {
      const list = map.get(team.confederation) ?? [];
      list.push(team);
      map.set(team.confederation, list);
    }
    return map;
  }, []);

  const selected = selectedId
    ? (TEAMS.find((t) => t.id === selectedId) ?? null)
    : null;

  return (
    <div className="container">
      <header>
        <div className="header-row">
          <div>
            <h1>World Cup 2026 — Guess the Champion</h1>
            <p>
              {TEAM_COUNT} qualified nations. Pick the team you think will lift
              the trophy in New York on July 19, 2026.
            </p>
          </div>
          <ConnectButton />
        </div>

        <ul className="deadlines">
          <li>
            <span className="deadline-label">Betting closes</span>
            <strong>{formatDeadline(BET_DEADLINE)}</strong>
          </li>
        </ul>
      </header>

      <PoolStats />
      <UserStats />

      <BetPanel selected={selected} />

      {(Object.keys(CONFEDERATIONS) as Confederation[]).map((conf) => {
        const list = grouped.get(conf) ?? [];
        if (list.length === 0) return null;
        return (
          <section key={conf} className="confederation">
            <h2>
              {CONFEDERATIONS[conf]} — {list.length}
            </h2>
            <div className="team-grid">
              {list.map((team) => (
                <TeamCard
                  key={team.id}
                  team={team}
                  selected={team.id === selectedId}
                  onSelect={setSelectedId}
                />
              ))}
            </div>
          </section>
        );
      })}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 钱包连接
// ─────────────────────────────────────────────────────────────

function ConnectButton() {
  const { address, isConnected, chain } = useAccount();
  const { connect, connectors, status } = useConnect();
  const { disconnect } = useDisconnect();
  const { data: balance } = useBalance({ address });

  if (isConnected && address) {
    return (
      <div className="wallet">
        <div className="wallet-info">
          <span className="wallet-addr">
            {address.slice(0, 6)}…{address.slice(-4)}
          </span>
          <span className="wallet-chain">
            {chain?.name ?? "Unknown"} ·{" "}
            {balance
              ? `${parseFloat(formatEther(balance.value)).toFixed(3)} ETH`
              : "—"}
          </span>
        </div>
        <button className="btn-secondary" onClick={() => disconnect()}>
          Disconnect
        </button>
      </div>
    );
  }

  const injected = connectors[0];

  return (
    <button
      className="btn-primary"
      onClick={() => connect({ connector: injected })}
      disabled={status === "pending"}
    >
      {status === "pending" ? "Connecting…" : "Connect Wallet"}
    </button>
  );
}

// ─────────────────────────────────────────────────────────────
// 奖池信息
// ─────────────────────────────────────────────────────────────

function PoolStats() {
  const { data: totalPool } = useReadContract({
    address: GUESS_CHAMPION_ADDRESS,
    abi: GUESS_CHAMPION_ABI,
    functionName: "totalPool",
  });
  const { data: cancelled } = useReadContract({
    address: GUESS_CHAMPION_ADDRESS,
    abi: GUESS_CHAMPION_ABI,
    functionName: "cancelled",
  });
  const { data: champion } = useReadContract({
    address: GUESS_CHAMPION_ADDRESS,
    abi: GUESS_CHAMPION_ABI,
    functionName: "champion",
  });

  let status = "Open for bets";
  if (cancelled) status = "Cancelled — refunds open";
  else if (champion && champion > 0) status = `Champion declared: #${champion}`;

  return (
    <div className="pool-stats">
      <div className="stat">
        <span className="stat-label">Total pool</span>
        <strong className="stat-value">
          {totalPool !== undefined ? formatEther(totalPool) : "—"} ETH
        </strong>
      </div>
      <div className="stat">
        <span className="stat-label">Status</span>
        <strong className="stat-value">{status}</strong>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 用户当前持仓
// ─────────────────────────────────────────────────────────────

function UserStats() {
  const { address } = useAccount();

  const { data: betAmount } = useReadContract({
    address: GUESS_CHAMPION_ADDRESS,
    abi: GUESS_CHAMPION_ABI,
    functionName: "betAmounts",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });
  const { data: teamId } = useReadContract({
    address: GUESS_CHAMPION_ADDRESS,
    abi: GUESS_CHAMPION_ABI,
    functionName: "teamOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  if (!address) return null;
  if (!betAmount || betAmount === 0n) {
    return (
      <div className="user-stats">
        You haven't placed a bet yet — pick a team below.
      </div>
    );
  }

  const team = TEAMS.find((t) => t.id === Number(teamId));

  return (
    <div className="user-stats user-stats-active">
      <span>
        Your bet:{" "}
        <strong>{formatEther(betAmount)} ETH</strong>{" "}
        on{" "}
        <strong>
          {team ? `${team.name} (#${team.id})` : `team #${teamId}`}
        </strong>
      </span>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 下注表单
// ─────────────────────────────────────────────────────────────

interface BetPanelProps {
  selected: Team | null;
}

function BetPanel({ selected }: BetPanelProps) {
  const { address, isConnected } = useAccount();
  const [amount, setAmount] = useState("0.1");

  const { writeContract, data: hash, isPending, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  });

  const { data: minBet } = useReadContract({
    address: GUESS_CHAMPION_ADDRESS,
    abi: GUESS_CHAMPION_ABI,
    functionName: "MIN_BET",
  });
  const { data: maxBet } = useReadContract({
    address: GUESS_CHAMPION_ADDRESS,
    abi: GUESS_CHAMPION_ABI,
    functionName: "MAX_BET",
  });

  const handleBet = () => {
    if (!selected) return;
    let value: bigint;
    try {
      value = parseEther(amount);
    } catch {
      return;
    }
    writeContract({
      address: GUESS_CHAMPION_ADDRESS,
      abi: GUESS_CHAMPION_ABI,
      functionName: "bet",
      args: [selected.id],
      value,
    });
  };

  if (!selected) {
    return (
      <div className="summary">
        No team selected. Click a team card below to choose your champion.
      </div>
    );
  }

  return (
    <div className="bet-panel">
      <div className="bet-row">
        <div className="bet-team">
          <img src={flagUrl(selected.code, 80)} alt={selected.name} />
          <div>
            <div className="team-name">{selected.name}</div>
            <div className="team-id">
              #{selected.id} · {selected.confederation}
            </div>
          </div>
        </div>

        <div className="bet-input">
          <input
            type="number"
            step="0.01"
            min="0"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="ETH"
          />
          <span className="bet-range">
            {minBet !== undefined && maxBet !== undefined
              ? `${formatEther(minBet)} – ${formatEther(maxBet)} ETH`
              : ""}
          </span>
        </div>

        <button
          className="btn-primary"
          onClick={handleBet}
          disabled={!isConnected || isPending || isConfirming}
        >
          {!isConnected
            ? "Connect wallet first"
            : isPending
              ? "Confirm in wallet…"
              : isConfirming
                ? "Waiting for tx…"
                : `Bet on ${selected.name}`}
        </button>
      </div>

      {error && (
        <div className="bet-error">
          {(error as Error & { shortMessage?: string }).shortMessage ??
            error.message}
        </div>
      )}
      {isSuccess && (
        <div className="bet-success">Bet confirmed in block ✓</div>
      )}
      {!address && (
        <div className="bet-hint">
          Connect a wallet to place your bet on-chain.
        </div>
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 队伍卡片
// ─────────────────────────────────────────────────────────────

interface TeamCardProps {
  team: Team;
  selected: boolean;
  onSelect: (id: number) => void;
}

function TeamCard({ team, selected, onSelect }: TeamCardProps) {
  return (
    <button
      type="button"
      className={`team-card${selected ? " selected" : ""}`}
      onClick={() => onSelect(team.id)}
    >
      <img
        className="team-flag"
        src={flagUrl(team.code, 80)}
        alt={`${team.name} flag`}
        loading="lazy"
      />
      <div className="team-info">
        <span className="team-name">{team.name}</span>
        <span className="team-id">#{team.id}</span>
      </div>
    </button>
  );
}
