// 2026 FIFA World Cup 全部 48 支参赛队伍
// id: 1..48 与链上合约 GuessChampion.sol 的 teamId 一一对应（0 为哨兵值）
// code: ISO 3166-1 alpha-2 小写，用于拼接 https://flagcdn.com/w80/{code}.png
//       英格兰、苏格兰使用 ISO 3166-2 子区代码 gb-eng / gb-sct
export type Confederation =
  | "CAF"
  | "CONMEBOL"
  | "CONCACAF"
  | "AFC"
  | "UEFA"
  | "OFC";

export interface Team {
  id: number;
  name: string;
  code: string;
  confederation: Confederation;
}

export const TEAMS: readonly Team[] = [
  // 非洲足联 CAF (10)
  { id: 1, name: "Algeria", code: "dz", confederation: "CAF" },
  { id: 2, name: "Cabo Verde", code: "cv", confederation: "CAF" },
  { id: 3, name: "Côte d'Ivoire", code: "ci", confederation: "CAF" },
  { id: 4, name: "Egypt", code: "eg", confederation: "CAF" },
  { id: 5, name: "Ghana", code: "gh", confederation: "CAF" },
  { id: 6, name: "Morocco", code: "ma", confederation: "CAF" },
  { id: 7, name: "Senegal", code: "sn", confederation: "CAF" },
  { id: 8, name: "South Africa", code: "za", confederation: "CAF" },
  { id: 9, name: "Tunisia", code: "tn", confederation: "CAF" },
  { id: 10, name: "DR Congo", code: "cd", confederation: "CAF" },

  // 南美足联 CONMEBOL (6)
  { id: 11, name: "Argentina", code: "ar", confederation: "CONMEBOL" },
  { id: 12, name: "Brazil", code: "br", confederation: "CONMEBOL" },
  { id: 13, name: "Ecuador", code: "ec", confederation: "CONMEBOL" },
  { id: 14, name: "Uruguay", code: "uy", confederation: "CONMEBOL" },
  { id: 15, name: "Colombia", code: "co", confederation: "CONMEBOL" },
  { id: 16, name: "Paraguay", code: "py", confederation: "CONMEBOL" },

  // 中北美及加勒比足联 CONCACAF (6) - 含三东道主
  { id: 17, name: "United States", code: "us", confederation: "CONCACAF" },
  { id: 18, name: "Canada", code: "ca", confederation: "CONCACAF" },
  { id: 19, name: "Mexico", code: "mx", confederation: "CONCACAF" },
  { id: 20, name: "Curaçao", code: "cw", confederation: "CONCACAF" },
  { id: 21, name: "Haiti", code: "ht", confederation: "CONCACAF" },
  { id: 22, name: "Panama", code: "pa", confederation: "CONCACAF" },

  // 亚足联 AFC (9)
  { id: 23, name: "Australia", code: "au", confederation: "AFC" },
  { id: 24, name: "Iran", code: "ir", confederation: "AFC" },
  { id: 25, name: "Japan", code: "jp", confederation: "AFC" },
  { id: 26, name: "Jordan", code: "jo", confederation: "AFC" },
  { id: 27, name: "South Korea", code: "kr", confederation: "AFC" },
  { id: 28, name: "Qatar", code: "qa", confederation: "AFC" },
  { id: 29, name: "Saudi Arabia", code: "sa", confederation: "AFC" },
  { id: 30, name: "Uzbekistan", code: "uz", confederation: "AFC" },
  { id: 31, name: "Iraq", code: "iq", confederation: "AFC" },

  // 欧足联 UEFA (16)
  { id: 32, name: "England", code: "gb-eng", confederation: "UEFA" },
  { id: 33, name: "France", code: "fr", confederation: "UEFA" },
  { id: 34, name: "Croatia", code: "hr", confederation: "UEFA" },
  { id: 35, name: "Norway", code: "no", confederation: "UEFA" },
  { id: 36, name: "Portugal", code: "pt", confederation: "UEFA" },
  { id: 37, name: "Germany", code: "de", confederation: "UEFA" },
  { id: 38, name: "Netherlands", code: "nl", confederation: "UEFA" },
  { id: 39, name: "Switzerland", code: "ch", confederation: "UEFA" },
  { id: 40, name: "Scotland", code: "gb-sct", confederation: "UEFA" },
  { id: 41, name: "Spain", code: "es", confederation: "UEFA" },
  { id: 42, name: "Austria", code: "at", confederation: "UEFA" },
  { id: 43, name: "Belgium", code: "be", confederation: "UEFA" },
  {
    id: 44,
    name: "Bosnia and Herzegovina",
    code: "ba",
    confederation: "UEFA",
  },
  { id: 45, name: "Sweden", code: "se", confederation: "UEFA" },
  { id: 46, name: "Türkiye", code: "tr", confederation: "UEFA" },
  { id: 47, name: "Czechia", code: "cz", confederation: "UEFA" },

  // 大洋洲足联 OFC (1)
  { id: 48, name: "New Zealand", code: "nz", confederation: "OFC" },
] as const;

export const TEAM_COUNT = TEAMS.length; // 必须等于合约里的 TEAM_COUNT = 48

export const CONFEDERATIONS: Record<Confederation, string> = {
  CAF: "Africa (CAF)",
  CONMEBOL: "South America (CONMEBOL)",
  CONCACAF: "North & Central America (CONCACAF)",
  AFC: "Asia (AFC)",
  UEFA: "Europe (UEFA)",
  OFC: "Oceania (OFC)",
};

export function flagUrl(code: string, size: 40 | 80 | 160 = 80): string {
  return `https://flagcdn.com/w${size}/${code}.png`;
}
