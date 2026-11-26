import { useEffect, useState } from "react";

const nowInSeconds = () => Math.floor(Date.now() / 1000);

// The current time in seconds, updated every second (for countdowns).
export function useNow(): number {
  const [now, setNow] = useState(nowInSeconds);

  useEffect(() => {
    const timer = setInterval(() => setNow(nowInSeconds()), 1000);
    return () => clearInterval(timer);
  }, []);

  return now;
}