// Mirrors the app: Vitals/App/PinSettings.swift (readings, shapes, themes, presets).

export const CATEGORIES = [
  ['performance', 'Performance'],
  ['power', 'Battery & power'],
  ['storage', 'Storage'],
  ['network', 'Network'],
  ['display', 'Display & time'],
];

// value(t) gets a 0..1 wobble so readings move a little while on screen.
export const READINGS = {
  cpu:           { title: 'CPU',            short: 'CPU',     cat: 'performance', color: '#0A84FF', pct: 0.23, value: (w) => `${Math.round(23 + w * 9)}%` },
  gpu:           { title: 'GPU',            short: 'GPU',     cat: 'performance', color: '#FF375F', pct: 0.41, value: (w) => `${Math.round(41 + w * 12)}%` },
  memory:        { title: 'Memory',         short: 'Memory',  cat: 'performance', color: '#BF5AF2', pct: 0.62, value: (w) => `${Math.round(62 + w * 2)}%` },
  swap:          { title: 'Swap used',      short: 'Swap',    cat: 'performance', color: '#BF5AF2', pct: 0.12, value: () => '1.2 GB' },
  battery:       { title: 'Battery',        short: 'Battery', cat: 'power',       color: '#30D158', pct: 0.71, value: () => '71%' },
  power:         { title: 'Power draw',     short: 'Power',   cat: 'power',       color: '#30D158', pct: 0.3,  value: (w) => `${(9.4 + w * 2).toFixed(1)} W` },
  batteryHealth: { title: 'Battery health', short: 'Health',  cat: 'power',       color: '#30D158', pct: 0.94, value: () => '94%' },
  disk:          { title: 'Disk free',      short: 'Free',    cat: 'storage',     color: '#00C7BE', pct: 0.29, value: () => '142 GB' },
  diskIO:        { title: 'Disk activity',  short: 'Disk',    cat: 'storage',     color: '#00C7BE', pct: 0.2,  value: (w) => `${Math.round(38 + w * 30)} MB/s` },
  network:       { title: 'Network speed',  short: 'Network', cat: 'network',     color: '#5E5CE6', pct: 0.35, value: (w) => `↓${(2.1 + w * 1.4).toFixed(1)} MB/s` },
  dataToday:     { title: 'Data today',     short: 'Today',   cat: 'network',     color: '#5E5CE6', pct: 0.45, value: () => '1.8 GB' },
  wifi:          { title: 'Wi‑Fi signal',   short: 'Wi‑Fi',   cat: 'network',     color: '#64D2FF', pct: 0.75, value: (w) => `${Math.round(-54 + w * 3)} dBm` },
  ping:          { title: 'Ping',           short: 'Ping',    cat: 'network',     color: '#64D2FF', pct: 0.18, value: (w) => `${Math.round(18 + w * 6)} ms` },
  display:       { title: 'Refresh rate',   short: 'Display', cat: 'display',     color: '#FF9F0A', pct: 1,    value: () => '120 Hz' },
  uptime:        { title: 'Uptime',         short: 'Uptime',  cat: 'display',     color: '#8E8E93', pct: 0.4,  value: () => '6d 3h' },
  worldClock:    { title: 'World clock',    short: 'Clock',   cat: 'display',     color: '#8E8E93', pct: 0.5,  value: () => 'NYC 01:12' },
};

export const SHAPES = [
  ['dock', 'Edge Dock', 'Flush to the screen edge, no gap. Can tuck away until you hover.'],
  ['pill', 'Pill', 'One slim capsule, values only. The smallest box.'],
  ['card', 'Card', 'Readings with labels and gauges. The roomiest.'],
  ['rings', 'Rings', 'Just gauge rings with the number inside.'],
  ['bars', 'Meters', 'Tiny meter bars, like a dashboard.'],
  ['text', 'Text Only', 'No background at all — text with a soft shadow, like a game overlay.'],
];

export const THEMES = [
  ['auto', 'Auto', 'Graphite in dark mode, Frost in light mode'],
  ['graphite', 'Graphite', 'Frosted dark gray — the calmest'],
  ['frost', 'Frost', 'Frosted light, for bright desktops'],
  ['midnight', 'Midnight', 'Solid black, highest contrast'],
  ['nord', 'Nord', 'Cool arctic blue-gray'],
  ['dracula', 'Dracula', 'Dark violet, from the coding theme'],
  ['mocha', 'Mocha', 'Soft pastel dark (Catppuccin)'],
  ['solarized', 'Solarized', 'Warm paper, easy on the eyes'],
  ['custom', 'Your Color', 'Any color, kept readable automatically'],
];

export const PRESETS = [
  ['minimal', 'Minimal', 'CPU in a slim edge dock', 'dock', ['cpu']],
  ['gamer', 'Gamer', 'Refresh rate, ping, CPU, GPU — overlay text', 'text', ['display', 'ping', 'cpu', 'gpu']],
  ['laptop', 'On the go', 'Battery, power draw, time left', 'pill', ['battery', 'power', 'batteryHealth']],
  ['network', 'Network', 'Speed, data today, Wi‑Fi, ping', 'card', ['network', 'dataToday', 'wifi', 'ping']],
  ['creator', 'Creator', 'Memory, swap, disk activity, GPU', 'rings', ['memory', 'swap', 'diskIO', 'gpu']],
  ['dashboard', 'Dashboard', 'Everything important, as meters', 'bars', ['cpu', 'gpu', 'memory', 'battery', 'disk', 'network']],
];
