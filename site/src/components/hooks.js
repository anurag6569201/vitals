import { useEffect, useRef, useState } from 'react';

export function useReducedMotion() {
  const [reduced, setReduced] = useState(false);
  useEffect(() => {
    const mq = window.matchMedia('(prefers-reduced-motion: reduce)');
    const update = () => setReduced(mq.matches);
    update();
    mq.addEventListener('change', update);
    return () => mq.removeEventListener('change', update);
  }, []);
  return reduced;
}

/** Calls back every `ms` while the element is on screen (and motion is allowed). Returns a tick counter. */
export function useTicker(ms, enabled = true) {
  const [tick, setTick] = useState(0);
  const reduced = useReducedMotion();
  useEffect(() => {
    if (!enabled || reduced) return;
    const id = setInterval(() => {
      if (document.visibilityState === 'visible') setTick((t) => t + 1);
    }, ms);
    return () => clearInterval(id);
  }, [ms, enabled, reduced]);
  return tick;
}

/** Adds `.in` to the element the first time it scrolls into view. */
export function useReveal() {
  const ref = useRef(null);
  const [shown, setShown] = useState(false);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    if (!('IntersectionObserver' in window)) return setShown(true);
    const io = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) {
          setShown(true);
          io.disconnect();
        }
      },
      { rootMargin: '0px 0px -12% 0px' }
    );
    io.observe(el);
    return () => io.disconnect();
  }, []);
  return [ref, shown];
}

/** Small deterministic wobble so live numbers move without hydration mismatches. */
export function wobble(base, amount, tick, seed = 1) {
  if (!tick) return base;
  const x = Math.sin(tick * 1.7 + seed * 12.9898) * 43758.5453;
  return base + (x - Math.floor(x) - 0.5) * 2 * amount;
}
