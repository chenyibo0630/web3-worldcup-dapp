// 与 src/GuessChampion.sol 中的常量保持一致
// 时间戳为 Unix seconds（UTC 绝对时刻），渲染时按浏览器时区显示
export const BET_DEADLINE = 1781136000; // 2026-06-11 00:00:00 UTC, 世界杯开赛

const FORMATTER = new Intl.DateTimeFormat(undefined, {
  year: "numeric",
  month: "short",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  timeZoneName: "short",
});

export function formatDeadline(unixSeconds: number): string {
  return FORMATTER.format(new Date(unixSeconds * 1000));
}
