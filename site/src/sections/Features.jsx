import { useMemo, useState } from 'react';
import { Section, SecHead, ProTag } from './common.jsx';
import { CATEGORIES, READINGS } from '../data.js';
import { Bolt, Check, Hotspot, Keyboard, Moonzz, Trash } from '../components/Icons.jsx';
import { useReducedMotion, useTicker, wobble } from '../components/hooks.js';

/* ---------- Sixteen readings ---------- */

export function Readings() {
  const tick = useTicker(1600);
  return (
    <Section id="readings" className="tint">
      <SecHead kicker="Sixteen readings" title="Everything worth knowing, in your menu bar.">
        Show live readings right in the menu bar as icons or text, in your colors — or pin them on screen. From CPU and GPU to
        refresh rate, ping, Wi‑Fi signal and battery health.
      </SecHead>
      <div className="read-grid">
        {CATEGORIES.map(([cat, label]) => (
          <div key={cat} className="read-col">
            <h3>{label}</h3>
            {Object.entries(READINGS).filter(([, r]) => r.cat === cat).map(([k, r], i) => (
              <div key={k} className="read-row">
                <i style={{ background: r.color }} />
                <span>{r.title}</span>
                <b>{r.value(tick ? wobble(0.5, 0.5, tick, i + cat.length) : 0)}</b>
              </div>
            ))}
          </div>
        ))}
      </div>
      <p className="footnote">Live menu-bar readings, colors and icon styles are part of Vitals Pro <ProTag /></p>
    </Section>
  );
}

/* ---------- Free Up Space ---------- */

// Names and descriptions mirror Vitals/Platform/SpaceScanner.swift.
const FINDS = [
  ['dev', 'Developer junk', 'Build caches and tools that rebuild or re-download themselves.', 14.1],
  ['downloads', 'Old downloads', 'Things in Downloads you haven’t opened in over a month.', 12.4],
  ['large', 'Large files', 'Your biggest files, with when you last opened them.', 9.2],
  ['installers', 'Installers & archives', 'Disk images you’ve used and archives you’ve already unzipped.', 7.5],
  ['devices', 'iPhone & iPad', 'Old iPhone and iPad software updates and backups.', 6.3],
  ['caches', 'App caches', 'Temporary files apps rebuild on their own.', 5.8],
  ['apps', 'Apps you don’t use', 'Apps you haven’t opened in 3 months or more.', 4.4],
  ['dupes', 'Duplicates', 'Identical copies. The newest copy is kept.', 3.5],
  ['shots', 'Old screenshots', 'Screenshots and recordings older than a month.', 1.9],
];

export function FreeUpSpace() {
  const [phase, setPhase] = useState('done'); // idle | scanning | done
  const [progress, setProgress] = useState(0);
  const [picked, setPicked] = useState([]);
  const reduced = useReducedMotion();
  const total = FINDS.reduce((a, f) => a + f[3], 0);
  const max = Math.max(...FINDS.map((f) => f[3]));
  const sel = useMemo(() => FINDS.filter((f) => picked.includes(f[0])).reduce((a, f) => a + f[3], 0), [picked]);

  const scan = () => {
    setPicked([]);
    if (reduced) { setPhase('done'); return; }
    setPhase('scanning');
    setProgress(0);
    let p = 0;
    const id = setInterval(() => {
      p += 7 + Math.random() * 9;
      setProgress(Math.min(100, p));
      if (p >= 100) { clearInterval(id); setPhase('done'); }
    }, 90);
  };
  const toggle = (k) => setPicked((c) => (c.includes(k) ? c.filter((x) => x !== k) : [...c, k]));
  const shown = phase === 'done' ? FINDS : [];

  return (
    <Section id="space">
      <div className="split">
        <div>
          <SecHead kicker="Free Up Space" title="Disk full? See exactly what to clear.">
            Free Up Space scans your home folder on your Mac and sorts what it finds into plain groups, biggest first.
            Every item is explained. Nothing is pre-selected and nothing is deleted for you — what you pick goes to the
            Trash, where you can still put it back.
          </SecHead>
          <ul className="checks">
            <li><Check /><span><b>Scan free.</b> See every gigabyte you could get back before paying anything.</span></li>
            <li><Check /><span><b>Clear in one click with Pro.</b> Or clear by hand in Finder — your call.</span></li>
            <li><Check /><span><b>No scare tactics.</b> No “junk detected!” banners, no subscription.</span></li>
          </ul>
        </div>

        <div className="space-card">
          <div className="space-top">
            <div>
              <div className="cap">Free Up Space</div>
              <h3>
                {phase === 'done' ? `${total.toFixed(1)} GB you could clear` : phase === 'scanning' ? 'Scanning your home folder…' : 'Find what’s taking your space'}
              </h3>
            </div>
            <button type="button" className="btn small" onClick={scan} disabled={phase === 'scanning'}>
              {phase === 'done' ? 'Scan again' : 'Scan'}
            </button>
          </div>

          {phase === 'scanning' && (
            <div className="scanbar" role="progressbar" aria-valuenow={Math.round(progress)} aria-valuemin="0" aria-valuemax="100">
              <span style={{ width: `${progress}%` }} />
            </div>
          )}
          {phase === 'idle' && <p className="space-hint">Try it: press Scan to see an example result.</p>}

          <ul className="finds">
            {shown.map(([k, name, why, gb], i) => (
              <li key={k} style={{ '--d': `${i * 50}ms` }}>
                <label className={picked.includes(k) ? 'on' : ''}>
                  <input type="checkbox" checked={picked.includes(k)} onChange={() => toggle(k)} />
                  <span className="find-text"><b>{name}</b><small>{why}</small></span>
                  <span className="find-bar"><span style={{ width: `${(gb / max) * 100}%` }} /></span>
                  <span className="find-size">{gb.toFixed(1)} GB</span>
                </label>
              </li>
            ))}
          </ul>

          {phase === 'done' && (
            <div className="space-foot">
              <span>{picked.length ? `${sel.toFixed(1)} GB selected` : 'Pick what to clear'}</span>
              <button type="button" className="btn primary small" disabled={!picked.length}>
                <Trash size={15} /> Move to Trash <ProTag />
              </button>
            </div>
          )}
        </div>
      </div>
    </Section>
  );
}

/* ---------- Where your data went + hotspot guard ---------- */

function seeded(i) {
  const x = Math.sin(i * 91.17 + 7.3) * 10000;
  return x - Math.floor(x);
}
const DAYS = Array.from({ length: 30 }, (_, i) => {
  const weekend = i % 7 === 5 || i % 7 === 6;
  const wifi = 0.8 + seeded(i) * 2.4 + (weekend ? 1.4 : 0);
  const hotspot = seeded(i + 40) > 0.72 ? 0.2 + seeded(i + 80) * 0.9 : 0;
  return { wifi, hotspot };
});

export function DataUsage() {
  const [range, setRange] = useState(7);
  const days = range === 1 ? [] : DAYS.slice(-range);
  const max = Math.max(...days.map((d) => d.wifi + d.hotspot), 1);
  const sum = days.reduce((a, d) => a + d.wifi + d.hotspot, 0);
  const hs = days.reduce((a, d) => a + d.hotspot, 0);

  return (
    <Section id="data" className="tint">
      <div className="split rev">
        <div className="data-card">
          <div className="data-top">
            <div>
              <div className="cap">Where your data went</div>
              <h3>{range === 1 ? '1.8 GB today' : `${sum.toFixed(1)} GB in ${range} days`}</h3>
            </div>
            <div className="seg tiny" role="tablist" aria-label="Range">
              {[[1, 'Today'], [7, '7 days'], [30, '30 days']].map(([v, l]) => (
                <button key={v} type="button" role="tab" aria-selected={range === v} className={range === v ? 'on' : ''} onClick={() => setRange(v)}>
                  {l}{v > 1 && <ProTag />}
                </button>
              ))}
            </div>
          </div>

          {range === 1 ? (
            <div className="today">
              <div className="today-row"><span className="dot wifi" />Wi‑Fi “Home”<b>1.42 GB</b></div>
              <div className="today-row"><span className="dot hs" />iPhone hotspot<b>0.31 GB</b></div>
              <div className="today-row"><span className="dot eth" />Ethernet<b>0.07 GB</b></div>
              <div className="stack"><span className="wifi" style={{ width: '79%' }} /><span className="hs" style={{ width: '17%' }} /><span className="eth" style={{ width: '4%' }} /></div>
            </div>
          ) : (
            <div className={`chart r${range}`} aria-label={`Daily data use over ${range} days`}>
              {days.map((d, i) => (
                <div key={i} className="col" title={`${(d.wifi + d.hotspot).toFixed(1)} GB`}>
                  <span className="hs" style={{ height: `${(d.hotspot / max) * 100}%` }} />
                  <span className="wifi" style={{ height: `${(d.wifi / max) * 100}%` }} />
                </div>
              ))}
            </div>
          )}
          <div className="legend">
            <span><i className="wifi" />Wi‑Fi & Ethernet</span>
            <span><i className="hs" />Hotspot{range > 1 ? ` · ${hs.toFixed(1)} GB` : ''}</span>
          </div>
        </div>

        <div>
          <SecHead kicker="Network" title="Know where your data went — and don’t blow your hotspot.">
            Vitals keeps a private, on-device log of how much your Mac downloaded and uploaded each hour, and over which
            connection, for up to 31 days.
          </SecHead>
          <div className="hotspot">
            <div className="hs-head"><Hotspot /> <b>On a hotspot</b><span>1.6 of 2 GB</span></div>
            <div className="hs-meter"><span style={{ width: '80%' }} /></div>
            <p>
              <b>Hotspot data guard</b> counts from the moment you join an iPhone hotspot or other metered network, and
              warns you at 80% and 100% of the limit you set. Free.
            </p>
          </div>
        </div>
      </div>
    </Section>
  );
}

/* ---------- Battery: forecast, planner, while you were away ---------- */

function fmtTime(h) {
  const hh = Math.floor(h) % 24;
  const mm = Math.round((h - Math.floor(h)) * 60);
  const ap = hh >= 12 ? 'PM' : 'AM';
  const h12 = hh % 12 === 0 ? 12 : hh % 12;
  return `${h12}:${String(mm).padStart(2, '0')} ${ap}`;
}

export function BatterySection() {
  const now = 13; // 1:00 PM
  const rate = 10.6; // % per hour
  const empty = now + 71 / rate; // ≈ 7:42 PM
  const [target, setTarget] = useState(18);
  const spare = empty - target;
  const spareText = `${Math.floor(spare)}h ${Math.round((spare % 1) * 60)}m`;

  return (
    <Section id="battery">
      <SecHead kicker="Battery" title="Will my battery last? Ask before you leave.">
        Vitals learns how your MacBook usually drains, forecasts when it will run out, and tells you when something is
        draining it faster than normal.
      </SecHead>
      <div className="bat-grid">
        <div className="bat-card">
          <div className="cap">Battery forecast <span className="free">FREE</span></div>
          <h3>Lasts until {fmtTime(empty)}</h3>
          <p className="muted">About {Math.floor(71 / rate)}h {Math.round(((71 / rate) % 1) * 60)}m at {Math.round(rate)}% an hour</p>
          <div className="bat-line"><span style={{ width: '71%' }} /></div>
        </div>

        <div className="bat-card">
          <div className="cap">Will my battery last? <span className="pro">PRO</span></div>
          <label className="planner">
            <span>I need it until</span>
            <b>{fmtTime(target)}</b>
          </label>
          <input type="range" min="14" max="23" step="0.5" value={target} onChange={(e) => setTarget(Number(e.target.value))} aria-label="I need it until" />
          {spare >= 0 ? (
            <p className="verdict ok"><Check size={16} /> You’ll make it, with about {spareText} to spare.</p>
          ) : (
            <p className="verdict bad"><Bolt /> Not at this rate. Plug in by {fmtTime(empty)}.</p>
          )}
        </div>

        <div className="bat-card away">
          <div className="cap">While you were away</div>
          <h3>Away for 7h 12m · lost 23%</h3>
          <div className="away-rows">
            <div><span>Asleep</span><span className="bar"><span style={{ width: '82%' }} /></span><b>5h 54m</b></div>
            <div><span>Awake</span><span className="bar"><span style={{ width: '18%' }} /></span><b>1h 18m</b></div>
          </div>
          <p className="muted small">See how long your Mac actually slept and whether the drop was normal. Free shows the headline; Pro shows the full report. Quiet when nothing was off.</p>
        </div>
      </div>
    </Section>
  );
}

/* ---------- Shortcuts, Keep Awake, hotkey ---------- */

const SHORTCUTS = [
  ['How Is My Mac Doing', 'Ask for a plain-English health check.', '#1f9d57'],
  ['How Much Data Did I Use Today', 'Today’s total, by connection.', '#5e5ce6'],
  ['Keep My Mac Awake', 'For 5 minutes up to 24 hours.', '#f5a524'],
  ['Show or Hide the Vitals Pin', 'Toggle the pin from anywhere.', '#0a84ff'],
];

export function Shortcuts() {
  return (
    <Section id="shortcuts" className="tint">
      <div className="split">
        <div>
          <SecHead kicker="Little helpers" title="Works with Shortcuts. Stays awake on command.">
            Vitals adds actions to the Shortcuts app, so you can build automations or run them with a key. Keep Awake stops your Mac
            sleeping through a long download, and a global keyboard shortcut opens Vitals from anywhere. All free.
          </SecHead>
          <ul className="checks">
            <li><Moonzz /><span><b>Keep Awake</b> for 30 minutes, 1 or 3 hours, or until you turn it off.</span></li>
            <li><Keyboard /><span><b>Global shortcut</b> to open Vitals without reaching for the menu bar.</span></li>
          </ul>
        </div>
        <div className="sc-grid">
          {SHORTCUTS.map(([t, d, c]) => (
            <div key={t} className="sc-tile" style={{ '--c': c }}>
              <span className="sc-glyph" aria-hidden="true">⌘</span>
              <b>{t}</b>
              <span>{d}</span>
            </div>
          ))}
        </div>
      </div>
    </Section>
  );
}
