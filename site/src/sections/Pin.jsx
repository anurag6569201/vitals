import { useMemo, useState } from 'react';
import { Section, SecHead, ProTag, FreeTag } from './common.jsx';
import { PRESETS, READINGS, SHAPES, THEMES } from '../data.js';
import { useTicker, wobble } from '../components/hooks.js';

const THEME_COLORS = {
  graphite: { bg: 'rgba(38,40,44,.82)', fg: '#f2f2f0', sub: 'rgba(242,242,240,.62)', track: 'rgba(255,255,255,.14)' },
  frost: { bg: 'rgba(250,250,252,.84)', fg: '#18191b', sub: 'rgba(24,25,27,.6)', track: 'rgba(0,0,0,.1)' },
  midnight: { bg: '#000', fg: '#fff', sub: 'rgba(255,255,255,.68)', track: 'rgba(255,255,255,.18)' },
  nord: { bg: '#2e3440', fg: '#eceff4', sub: '#a7b1c2', track: '#434c5e' },
  dracula: { bg: '#282a36', fg: '#f8f8f2', sub: '#b4b6c9', track: '#44475a' },
  mocha: { bg: '#1e1e2e', fg: '#cdd6f4', sub: '#a6adc8', track: '#313244' },
  solarized: { bg: '#fdf6e3', fg: '#586e75', sub: '#839496', track: '#eee8d5' },
};

function hexLum(hex) {
  const n = parseInt(hex.slice(1), 16);
  const c = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((v) => {
    v /= 255;
    return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}

function themeColors(theme, custom) {
  if (theme === 'custom') {
    const dark = hexLum(custom) < 0.36;
    return {
      bg: custom,
      fg: dark ? '#ffffff' : '#111111',
      sub: dark ? 'rgba(255,255,255,.75)' : 'rgba(0,0,0,.66)',
      track: dark ? 'rgba(255,255,255,.22)' : 'rgba(0,0,0,.14)',
    };
  }
  if (theme === 'auto') return null; // CSS variables decide (follows light/dark)
  return THEME_COLORS[theme];
}

function Ring({ pct, color }) {
  const r = 15, c = 2 * Math.PI * r;
  return (
    <svg width="40" height="40" viewBox="0 0 40 40" aria-hidden="true">
      <circle cx="20" cy="20" r={r} fill="none" stroke="var(--pin-track)" strokeWidth="4" />
      <circle cx="20" cy="20" r={r} fill="none" stroke={color} strokeWidth="4" strokeLinecap="round"
        strokeDasharray={c} strokeDashoffset={c * (1 - pct)} transform="rotate(-90 20 20)" />
    </svg>
  );
}

function PinWidget({ shape, theme, custom, readings, tick }) {
  const colors = themeColors(theme, custom);
  const style = colors
    ? { '--pin-bg': colors.bg, '--pin-fg': colors.fg, '--pin-sub': colors.sub, '--pin-track': colors.track }
    : undefined;
  const items = readings.map((k, i) => {
    const r = READINGS[k];
    const w = (wobble(0.5, 0.5, tick, i + 2));
    return { k, ...r, v: r.value(tick ? w : 0), p: Math.min(1, Math.max(0.04, r.pct + (tick ? (w - 0.5) * 0.12 : 0))) };
  });

  return (
    <div className={`pin pin-${shape}${theme === 'auto' ? ' pin-auto' : ''}`} style={style} aria-label="Pin preview">
      {items.map((it) => (
        <div className="pin-item" key={it.k}>
          {shape === 'rings' && (
            <div className="pin-ring"><Ring pct={it.p} color={it.color} /><span>{it.v.replace(/ (GB|MB\/s|ms|W|Hz|dBm)$/, '')}</span></div>
          )}
          {shape !== 'pill' && shape !== 'rings' && <span className="pin-label">{it.short}</span>}
          {shape !== 'rings' && <b className="pin-val" style={shape === 'text' ? { color: it.color } : undefined}>{it.v}</b>}
          {shape === 'rings' && <span className="pin-label">{it.short}</span>}
          {(shape === 'card' || shape === 'bars') && (
            <span className="pin-meter"><span style={{ width: `${it.p * 100}%`, background: it.color }} /></span>
          )}
        </div>
      ))}
    </div>
  );
}

export default function Pin() {
  const [preset, setPreset] = useState('network');
  const [shape, setShape] = useState('card');
  const [theme, setTheme] = useState('auto');
  const [custom, setCustom] = useState('#d97a06');
  const [readings, setReadings] = useState(PRESETS.find((p) => p[0] === 'network')[4]);
  const tick = useTicker(1500);

  const isFree = shape === 'dock' && theme === 'auto' && readings.length === 1;

  const applyPreset = (p) => {
    setPreset(p[0]);
    setShape(p[3]);
    setReadings(p[4]);
  };
  const toggleReading = (k) => {
    setPreset(null);
    setReadings((cur) => (cur.includes(k) ? (cur.length > 1 ? cur.filter((x) => x !== k) : cur) : [...cur, k].slice(-6)));
  };
  const themeInfo = useMemo(() => THEMES.find((t) => t[0] === theme), [theme]);
  const shapeInfo = SHAPES.find((s) => s[0] === shape);

  return (
    <Section id="pin">
      <SecHead kicker="On Screen pin" title="Keep the numbers you care about in sight.">
        Pin live readings anywhere on your screen — over a game, a render, a video call. Six shapes, nine readable
        themes and one-click presets. It stays out of the way, and the Edge Dock can tuck away until you hover.
      </SecHead>

      <div className="pin-lab">
        <div className={`wallpaper shape-${shape}`}>
          <div className="wp-window" aria-hidden="true">
            <div className="wp-dots"><span /><span /><span /></div>
            <div className="wp-lines"><span /><span /><span /><span /></div>
          </div>
          <PinWidget shape={shape} theme={theme} custom={custom} readings={readings} tick={tick} />
          <div className={`pin-plan ${isFree ? 'is-free' : ''}`}>
            {isFree ? <><FreeTag /> Included free</> : <><ProTag /> With Vitals Pro</>}
          </div>
        </div>

        <div className="pin-controls">
          <fieldset>
            <legend>Presets</legend>
            <div className="opt-grid">
              {PRESETS.map((p) => (
                <button key={p[0]} type="button" className={`opt${preset === p[0] ? ' on' : ''}`} onClick={() => applyPreset(p)} aria-pressed={preset === p[0]}>
                  <b>{p[1]}</b><span>{p[2]}</span>
                </button>
              ))}
            </div>
          </fieldset>

          <fieldset>
            <legend>Shape <span className="legend-note">{shapeInfo[2]}</span></legend>
            <div className="pills">
              {SHAPES.map(([k, t]) => (
                <button key={k} type="button" className={`pillbtn${shape === k ? ' on' : ''}`} onClick={() => setShape(k)} aria-pressed={shape === k}>{t}</button>
              ))}
            </div>
          </fieldset>

          <fieldset>
            <legend>Theme <span className="legend-note">{themeInfo[2]}</span></legend>
            <div className="swatches">
              {THEMES.map(([k, t]) => {
                const c = k === 'custom' ? { bg: custom } : k === 'auto' ? null : THEME_COLORS[k];
                return (
                  <button key={k} type="button" className={`swatch${theme === k ? ' on' : ''}${k === 'auto' ? ' auto' : ''}`}
                    style={c ? { background: c.bg } : undefined} onClick={() => setTheme(k)} aria-pressed={theme === k} title={t}>
                    <span className="sr">{t}</span>
                  </button>
                );
              })}
              {theme === 'custom' && (
                <label className="color-pick">
                  <input type="color" value={custom} onChange={(e) => setCustom(e.target.value)} aria-label="Pick your color" />
                </label>
              )}
            </div>
          </fieldset>

          <fieldset>
            <legend>Readings <span className="legend-note">up to six</span></legend>
            <div className="pills small">
              {['cpu', 'gpu', 'memory', 'battery', 'power', 'network', 'dataToday', 'ping', 'display', 'disk'].map((k) => (
                <button key={k} type="button" className={`pillbtn${readings.includes(k) ? ' on' : ''}`} onClick={() => toggleReading(k)} aria-pressed={readings.includes(k)}>
                  <i style={{ background: READINGS[k].color }} />{READINGS[k].title}
                </button>
              ))}
            </div>
          </fieldset>
        </div>
      </div>
      <p className="footnote">Free includes one reading in the Edge Dock with the Auto theme, so you can try it before you buy.</p>
    </Section>
  );
}
