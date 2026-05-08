import { useMemo, useState } from "react";
import {
  TEAMS,
  TEAM_COUNT,
  CONFEDERATIONS,
  flagUrl,
  type Confederation,
  type Team,
} from "./teams";
import { BET_DEADLINE, formatDeadline } from "./schedule";

export default function App() {
  const [selectedId, setSelectedId] = useState<number | null>(null);

  // 按大洲分组，避免每次渲染都重算
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
        <h1>World Cup 2026 — Guess the Champion</h1>
        <p>
          {TEAM_COUNT} qualified nations. Pick the team you think will lift the
          trophy in New York on July 19, 2026.
        </p>
        <ul className="deadlines">
          <li>
            <span className="deadline-label">Betting closes</span>
            <strong>{formatDeadline(BET_DEADLINE)}</strong>
          </li>
        </ul>
      </header>

      <div className="summary">
        {selected ? (
          <>
            Currently selected: <strong>#{selected.id} {selected.name}</strong>{" "}
            ({selected.confederation})
          </>
        ) : (
          <>No team selected. Click a team card below to choose your champion.</>
        )}
      </div>

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
