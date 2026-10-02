import { useEffect, useState } from 'react';
import { Section, SecHead, ProTag } from './common.jsx';
import { Check, Chip, Feather, Person, Pulse, Shield } from '../components/Icons.jsx';
import { useReducedMotion, useReveal } from '../components/hooks.js';

export function TrustStrip() {
  const items = [
    [<Shield key="i" />, 'Nothing leaves your Mac', 'No analytics, no tracking'],
    [<Person key="i" />, 'No account', 'Download and go'],
    [<Feather key="i" />, 'Featherweight', 'Typically well under 1% CPU'],
    [<Chip key="i" />, 'Every modern Mac', 'macOS 14+, Apple silicon & Intel'],
  ];
  return (
    <div className="wrap trust">
      {items.map(([icon, a, b]) => (
        <div key={a} className="trust-item">
          <span className="trust-icon">{icon}</span>
          <div><b>{a}</b><span>{b}</span></div>
        </div>
      ))}
    </div>
  );
}

const NOTES = [
  { tone: 'crit', title: 'Your Mac is running hot', body: 'macOS is slowing things down to cool off. Close what you’re not using.', actions: ['Activity Monitor', 'Snooze'] },
  { tone: 'warn', title: 'Your Mac is out of memory', body: 'It’s using the disk as overflow, so everything feels slower.', actions: ['Activity Monitor', 'Snooze'] },
  { tone: 'note', title: 'Hotspot: 1.6 of 2 GB used', body: 'You’re on your iPhone’s hotspot. Big downloads will eat the rest fast.', actions: ['See data', 'Snooze'] },
  { tone: 'note', title: 'Disk space is running low', body: '4.1 GB left. Free Up Space shows exactly what to clear.', actions: ['Free up space', 'Snooze'] },
];

function NotificationStack() {
  const [ref, shown] = useReveal();
  const reduced = useReducedMotion();
  const [count, setCount] = useState(NOTES.length);
  useEffect(() => {
    if (!shown || reduced) return;
    setCount(0);
    let n = 0;
    const id = setInterval(() => {
      n += 1;
      setCount(n);
      if (n >= NOTES.length) clearInterval(id);
    }, 650);
    return () => clearInterval(id);
  }, [shown, reduced]);

  return (
    <div className="desk" ref={ref} aria-label="Example Vitals notifications">
      <div className="desk-bar" aria-hidden="true"><span /><span className="desk-clock">10:42</span></div>
      <div className="notes">
        {NOTES.map((n, i) => (
          <div key={n.title} className={`note tone-${n.tone}${i < count ? ' show' : ''}`}>
            <div className="note-icon"><Pulse size={15} width={2.8} /></div>
            <div className="note-body">
              <div className="note-top"><b>Vitals</b><span>{i === 0 ? 'now' : `${i * 4}m ago`}</span></div>
              <h4>{n.title}</h4>
              <p>{n.body}</p>
              <div className="note-actions">{n.actions.map((a) => <span key={a}>{a}</span>)}</div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

const CATALOG = [
  ['Heat', 'crit', 'Act now', 'Your Mac is running hot', 'macOS is slowing things down to cool off. Vitals tells you before the fans and the lag make it obvious.', 'Activity Monitor · Snooze'],
  ['Memory', 'warn', 'Needs attention', 'Your Mac is out of memory', 'It’s swapping to disk, so everything feels slower. Closing a few apps or tabs gets it back.', 'Activity Monitor · Snooze'],
  ['Disk', 'note', 'Heads up', 'Disk space is running low', 'Below about 5 GB free, apps can crash and macOS updates fail. Free Up Space shows exactly what to clear.', 'Free up space · Manage Storage'],
  ['Restart', 'note', 'Heads up', 'Time for a restart', 'After about two weeks without one, a restart clears slowdowns and finishes pending updates. Whenever it suits you.', 'Snooze · Always ignore'],
  ['Battery drain', 'warn', 'pro', 'Battery is draining fast', 'You’re losing about 28% an hour, well above your usual. At this rate it lasts 2h 30m instead of 7h.', 'Plan with “Will my battery last?”'],
  ['Hotspot', 'note', 'Heads up', 'Close to your hotspot limit', 'Set a limit for your iPhone’s hotspot and Vitals warns you before a big download blows your mobile data.', 'See where your data went'],
];

export default function Alerts() {
  return (
    <Section id="catches">
      <div className="split">
        <div>
          <SecHead kicker="Alerts" title="Silent until there’s something worth saying.">
            Vitals waits until a problem has lasted long enough to matter, then sends a normal Mac notification:
            what’s happening, why it matters, and what to do about it.
          </SecHead>
          <ul className="checks">
            <li><Check /><span><b>No false alarms.</b> Pick Relaxed, Balanced or Sensitive. Short spikes are ignored.</span></li>
            <li><Check /><span><b>Fix it from the notification.</b> Snooze or Always ignore, right where the alert appears.</span></li>
            <li><Check /><span><b>Never an ad.</b> No notification ever tries to sell you Pro.</span></li>
          </ul>
        </div>
        <NotificationStack />
      </div>

      <div className="catalog">
        {CATALOG.map(([kind, tone, sev, title, body, fix]) => (
          <article key={title} className="alert-card">
            <div className="ac-kind">
              {kind}
              {sev === 'pro' ? <ProTag /> : <span className={`sev s-${tone}`}>{sev}</span>}
            </div>
            <h3>{title}</h3>
            <p>{body}</p>
            <div className="ac-fix">{fix}</div>
          </article>
        ))}
      </div>
    </Section>
  );
}
