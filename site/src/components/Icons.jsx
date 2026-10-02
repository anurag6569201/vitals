// Small hand-drawn icon set (stroke icons, 24×24, currentColor).
const base = { width: 20, height: 20, viewBox: '0 0 24 24', fill: 'none', 'aria-hidden': true };
const s = { stroke: 'currentColor', strokeWidth: 2, strokeLinecap: 'round', strokeLinejoin: 'round' };

export const Pulse = ({ size = 20, width = 2.4 }) => (
  <svg {...base} width={size} height={size}>
    <path d="M2 12h4l2.5-6 4 12 3-9 2 3H22" {...s} strokeWidth={width} />
  </svg>
);
export const Check = ({ size = 18 }) => (
  <svg {...base} width={size} height={size}><path d="m5 12 5 5 9-10" {...s} strokeWidth="2.6" /></svg>
);
export const Download = ({ size = 16 }) => (
  <svg {...base} width={size} height={size}><path d="M12 3v12m0 0-5-5m5 5 5-5M4 21h16" {...s} strokeWidth="2.2" /></svg>
);
export const Apple = ({ size = 16 }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true" fill="currentColor">
    <path d="M16.37 12.6c-.02-2.2 1.8-3.26 1.88-3.31-1.03-1.5-2.62-1.7-3.18-1.73-1.35-.14-2.64.8-3.33.8-.69 0-1.74-.78-2.86-.76-1.47.02-2.83.86-3.59 2.17-1.53 2.66-.39 6.59 1.1 8.74.73 1.05 1.6 2.24 2.73 2.2 1.1-.04 1.51-.71 2.84-.71 1.32 0 1.7.71 2.86.69 1.18-.02 1.93-1.07 2.65-2.13.84-1.22 1.18-2.4 1.2-2.46-.03-.01-2.3-.88-2.3-3.5ZM14.2 6.13c.6-.73 1.01-1.75.9-2.76-.87.04-1.92.58-2.54 1.31-.56.65-1.05 1.68-.92 2.68.97.07 1.96-.5 2.56-1.23Z" />
  </svg>
);
export const Sun = () => (
  <svg {...base} width="18" height="18"><circle cx="12" cy="12" r="4" {...s} /><path d="M12 2v2m0 16v2M4.9 4.9l1.4 1.4m11.4 11.4 1.4 1.4M2 12h2m16 0h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" {...s} /></svg>
);
export const Moon = () => (
  <svg {...base} width="18" height="18"><path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5Z" {...s} /></svg>
);
export const Auto = () => (
  <svg {...base} width="18" height="18"><circle cx="12" cy="12" r="8.5" {...s} /><path d="M12 3.5v17a8.5 8.5 0 0 0 0-17Z" fill="currentColor" /></svg>
);
export const Wifi = ({ size = 16 }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 18.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Zm-4.2-4.3a6 6 0 0 1 8.4 0l1.4-1.4a8 8 0 0 0-11.2 0l1.4 1.4Zm-2.8-2.8a10 10 0 0 1 14 0l1.4-1.4a12 12 0 0 0-16.8 0L5 11.4Z" /></svg>
);
export const Battery = ({ level = 0.7 }) => (
  <svg width="24" height="13" viewBox="0 0 26 14" fill="none" aria-hidden="true">
    <rect x="1" y="1" width="21" height="12" rx="3" stroke="currentColor" strokeWidth="1.5" />
    <rect x="3" y="3" width={Math.max(1, 17 * level)} height="8" rx="1.5" fill="currentColor" />
    <path d="M24 5v4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
  </svg>
);
export const Bell = () => (
  <svg {...base}><path d="M6 9a6 6 0 1 1 12 0c0 6 2.5 7.5 2.5 7.5h-17S6 15 6 9Zm4 11a2 2 0 0 0 4 0" {...s} /></svg>
);
export const Lock = ({ size = 14 }) => (
  <svg {...base} width={size} height={size}><rect x="5" y="11" width="14" height="10" rx="2" {...s} /><path d="M8 11V8a4 4 0 0 1 8 0v3" {...s} /></svg>
);
export const Shield = () => (
  <svg {...base}><path d="M12 3 4.5 6v6c0 4.5 3.2 7.7 7.5 9 4.3-1.3 7.5-4.5 7.5-9V6L12 3Z" {...s} /><path d="m8.5 12 2.5 2.5 4.5-5" {...s} /></svg>
);
export const Feather = () => (
  <svg {...base}><path d="M20 4C11 4 6 9 6 18m0 0 4-4m-4 4H4M20 4c0 7-4 11-10 11H8M20 4c-2 4-5 6-9 7" {...s} /></svg>
);
export const Person = () => (
  <svg {...base}><circle cx="12" cy="8" r="3.5" {...s} /><path d="M5 20c.8-3.6 3.6-5.5 7-5.5s6.2 1.9 7 5.5" {...s} /></svg>
);
export const Chip = () => (
  <svg {...base}><rect x="6" y="6" width="12" height="12" rx="2" {...s} /><path d="M9 2v4m6-4v4M9 18v4m6-4v4M2 9h4m-4 6h4m12-6h4m-4 6h4" {...s} /></svg>
);
export const Trash = ({ size = 16 }) => (
  <svg {...base} width={size} height={size}><path d="M4 7h16M10 11v6m4-6v6M6 7l1 13h10l1-13M9 7V4h6v3" {...s} /></svg>
);
export const Hotspot = () => (
  <svg {...base} width="18" height="18"><circle cx="12" cy="12" r="2" fill="currentColor" /><path d="M8.5 15.5a5 5 0 0 1 0-7m7 0a5 5 0 0 1 0 7M5.6 18.4a9 9 0 0 1 0-12.8m12.8 0a9 9 0 0 1 0 12.8" {...s} /></svg>
);
export const Bolt = () => (
  <svg {...base}><path d="M13 2 4 14h7l-1 8 9-12h-7l1-8Z" {...s} /></svg>
);
export const Moonzz = () => (
  <svg {...base}><path d="M19 14.5A7.5 7.5 0 0 1 9.5 5 7.5 7.5 0 1 0 19 14.5Z" {...s} /><path d="M15 3h4l-4 4h4" {...s} strokeWidth="1.6" /></svg>
);
export const Keyboard = () => (
  <svg {...base}><rect x="2.5" y="6" width="19" height="12" rx="2" {...s} /><path d="M6 10h.01M10 10h.01M14 10h.01M18 10h.01M8 14h8" {...s} /></svg>
);
export const Plus = () => (
  <svg {...base} width="16" height="16"><path d="M12 5v14M5 12h14" {...s} /></svg>
);
