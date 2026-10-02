import { useEffect, useState } from 'react';
import { AppStoreButton } from '../components/Layout.jsx';
import { Battery, Pulse, Wifi } from '../components/Icons.jsx';
import { useReducedMotion, useTicker, wobble } from '../components/hooks.js';
import { PRICE, TRIAL_DAYS } from '../config.js';

const SCENES = {
  calm: {
    tab: 'All good',
    tone: 'calm',
    label: null,
    title: 'Your Mac is healthy',
    sub: 'Watching quietly · Battery lasts until 7:50 PM',
    cpu: 9, cpuNote: 'Cool', mem: 48, memNote: 'Pressure: Normal', watts: '5.2 W', disk: '142 GB',
  },
  hot: {
    tab: 'Running hot',
    tone: 'warn',
    label: 'Hot',
    title: 'One thing needs your attention',
    sub: 'Watching quietly · Battery lasts until 2:20 PM',
    issue: {
      title: 'Your Mac is running hot',
      body: "macOS is slowing things down to cool off, so apps feel sluggish and the battery drains faster. Close what you're not using, or check the busiest app.",
      actions: ['Activity Monitor', 'Snooze 1 hour', 'Always ignore'],
    },
    cpu: 64, cpuNote: 'Hot', mem: 58, memNote: 'Pressure: Normal', watts: '18 W', disk: '142 GB',
  },
  disk: {
    tab: 'Disk almost full',
    tone: 'note',
    label: 'Disk',
    title: 'One thing needs your attention',
    sub: 'Watching quietly · Battery lasts until 6:10 PM',
    issue: {
      title: 'Disk space is running low',
      body: 'Only 4.1 GB left. Below about 5 GB, apps can crash and macOS updates fail. Free Up Space shows exactly what to clear.',
      actions: ['Free up space', 'Manage Storage', 'Snooze 1 hour'],
    },
    cpu: 14, cpuNote: 'Cool', mem: 71, memNote: 'Pressure: Tight', watts: '7.8 W', disk: '4.1 GB',
  },
};
const ORDER = ['hot', 'disk', 'calm'];

export default function Hero() {
  const [scene, setScene] = useState('hot');
  const [auto, setAuto] = useState(true);
  const reduced = useReducedMotion();
  const tick = useTicker(1400);

  useEffect(() => {
    if (!auto || reduced) return;
    const id = setTimeout(() => setScene((s) => ORDER[(ORDER.indexOf(s) + 1) % ORDER.length]), 6000);
    return () => clearTimeout(id);
  }, [scene, auto, reduced]);

  const sc = SCENES[scene];
  const cpu = Math.max(1, Math.round(wobble(sc.cpu, sc.cpu > 30 ? 6 : 3, tick, 1)));
  const net = wobble(1.2, 0.6, tick, 3).toFixed(1);

  return (
    <header className="hero wrap" id="top">
      <div className="hero-copy">
        <div className="eyebrow"><span className="lamp" />The check-engine light for your Mac</div>
        <h1>Your Mac, without the guesswork.</h1>
        <p className="lede">
          Vitals sits quietly in your menu bar. When your Mac runs hot, runs short on memory or disk, or drains its
          battery faster than normal, it tells you in plain English what's wrong and what to do — then gets out of the way.
        </p>
        <div className="ctas">
          <AppStoreButton />
          <a className="btn ghost" href="#download">Or download the full version</a>
        </div>
        <ul className="fine-list">
          <li>Free download</li>
          <li>Pro {PRICE} once</li>
          <li>{TRIAL_DAYS}-day free trial</li>
          <li>No account</li>
          <li>Nothing leaves your Mac</li>
        </ul>
      </div>

      <div className="demo" aria-label="Interactive preview of the Vitals menu">
        <div className="seg" role="tablist" aria-label="Preview state">
          {ORDER.map((k) => (
            <button
              key={k}
              type="button"
              role="tab"
              aria-selected={scene === k}
              className={scene === k ? `on tone-${SCENES[k].tone}` : ''}
              onClick={() => { setAuto(false); setScene(k); }}
            >
              {SCENES[k].tab}
            </button>
          ))}
        </div>

        <div className="screen">
          <div className="menubar" aria-hidden="true">
            <span className="mb-dim"><Wifi /></span>
            <span className="mb-dim"><Battery level={0.71} /></span>
            <span className={`mb-pulse tone-${sc.tone}`}>
              <Pulse size={17} width={2.6} />
              {sc.label && <span className="mb-dot" />}
              {sc.label && <span className="mb-label">{sc.label}</span>}
            </span>
            <span className="mb-clock">Fri 2 Oct 10:42</span>
          </div>

          <div className="popover" key={scene}>
            <div className="pv-head">
              <div className={`pv-badge tone-${sc.tone}`}><Pulse size={18} width={2.8} /></div>
              <div>
                <h3>{sc.title}</h3>
                <p>{sc.sub}</p>
              </div>
            </div>

            {sc.issue ? (
              <div className={`issue tone-${sc.tone}`}>
                <div className="issue-icon">!</div>
                <div>
                  <h4>{sc.issue.title}</h4>
                  <p>{sc.issue.body}</p>
                  <div className="chips">
                    {sc.issue.actions.map((a, i) => (
                      <span key={a} className={`chip${i === 0 ? ' go' : ''}`}>{a}</span>
                    ))}
                  </div>
                </div>
              </div>
            ) : (
              <div className="calm-msg">No heat, plenty of memory and disk. Vitals will speak up if that changes.</div>
            )}

            <div className="tiles">
              <Tile label="CPU" value={`${cpu}%`} pct={cpu} note={sc.cpuNote} hot={sc.cpu > 50} />
              <Tile label="Memory" value={`${sc.mem}%`} pct={sc.mem} note={sc.memNote} />
              <Tile label="Battery" value="71%" pct={71} note={`Using ${sc.watts}`} />
              <Tile label="Disk" value={sc.disk} note="free" low={scene === 'disk'} />
              <Tile label="Network" value={`${net} MB/s`} note="↑ 84 KB/s" />
              <Tile label="Uptime" value="6d 3h" note="since restart" />
            </div>
          </div>
        </div>
      </div>
    </header>
  );
}

function Tile({ label, value, pct, note, hot, low }) {
  return (
    <div className={`tile${hot ? ' hot' : ''}${low ? ' low' : ''}`}>
      <small>{label}</small>
      <b>{value}</b>
      {pct != null && <div className="meter"><span style={{ width: `${Math.min(100, pct)}%` }} /></div>}
      <i>{note}</i>
    </div>
  );
}
