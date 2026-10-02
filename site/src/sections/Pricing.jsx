import { Section, SecHead, ProTag } from './common.jsx';
import { AppStoreButton } from '../components/Layout.jsx';
import { Check, Lock } from '../components/Icons.jsx';
import { PRICE, TRIAL_DAYS, MIN_MACOS } from '../config.js';

export function Compare() {
  const rows = [
    ['Vitals', 'Plain-English problems and what to do about them', 'Only when something is wrong', `Free · Pro ${PRICE} once`, true],
    ['Graph monitors', 'Dozens of live numbers and charts', 'Always — you do the interpreting', 'Free to ~$15', false],
    ['“Cleaner” apps', 'Scans, junk files, scary warnings', 'Whenever they want to sell you something', 'Yearly subscription', false],
    ['Activity Monitor', 'A raw process list', 'Never — you have to go looking', 'Built in', false],
  ];
  return (
    <Section id="compare">
      <SecHead kicker="Why Vitals" title="Answers, not graphs.">
        System monitors are great if you enjoy watching charts. Vitals is for everyone else.
      </SecHead>
      <div className="table-wrap">
        <table>
          <thead><tr><th scope="col"><span className="sr">App</span></th><th scope="col">What you get</th><th scope="col">When it talks to you</th><th scope="col">Price</th></tr></thead>
          <tbody>
            {rows.map(([a, b, c, d, us]) => (
              <tr key={a} className={us ? 'us' : ''}><th scope="row">{a}</th><td>{b}</td><td>{c}</td><td>{d}</td></tr>
            ))}
          </tbody>
        </table>
      </div>
    </Section>
  );
}

const MATRIX = [
  ['Health light and alerts as Mac notifications', true, true],
  ['Hotspot data guard', true, true],
  ['Battery “lasts until…” forecast', true, true],
  ['Shortcuts actions, Keep Awake, global shortcut', true, true],
  ['Free Up Space and Space Map', 'Scan and explore', 'Scan + one-click clear'],
  ['Remove apps with their leftover files', 'Find', 'One click'],
  ['Battery health history and charging time', true, true],
  ['Where your data went', 'Today', '7 and 30 days'],
  ['While you were away', 'Headline', 'Full report'],
  ['On Screen pin', 'One reading, Edge Dock', 'Every shape, theme & preset'],
  ['Fast-drain alerts and “Will my battery last?”', false, true],
  ['Live readings in the menu bar, colors and icons', false, true],
];

function Cell({ v }) {
  if (v === true) return <span className="yes"><Check size={16} /><span className="sr">Included</span></span>;
  if (v === false) return <span className="no"><Lock /><span className="sr">Not included</span></span>;
  return <span>{v}</span>;
}

export function Pricing() {
  return (
    <Section id="pricing">
      <SecHead kicker="Pricing" title={`Free to use. ${PRICE} once for everything.`} center>
        Try every Pro feature free for {TRIAL_DAYS} days. No account, no subscription, no automatic charge.
      </SecHead>

      <div className="plans">
        <div className="plan">
          <h3>Vitals</h3>
          <div className="price">Free</div>
          <p className="plan-sub">Everything you need to know when something’s wrong.</p>
          <ul>
            <li>Health light in your menu bar, with the reason when something’s wrong</li>
            <li>Heat, memory, low-disk and restart alerts as Mac notifications</li>
            <li>Battery forecast and hotspot data guard</li>
            <li>Free Up Space scan and Space Map</li>
            <li>Battery health history</li>
            <li>Today’s data usage</li>
            <li>One live reading pinned to the edge of your screen</li>
            <li>Shortcuts, Keep Awake and a global shortcut</li>
          </ul>
          <AppStoreButton variant="ghost">Download free</AppStoreButton>
        </div>

        <div className="plan feature">
          <div className="plan-flag">{TRIAL_DAYS}-day free trial</div>
          <h3>Vitals Pro <ProTag /></h3>
          <div className="price">{PRICE} <small>once · every feature, forever</small></div>
          <p className="plan-sub">For people who want to see — and fix — everything.</p>
          <ul>
            <li>Everything in Vitals</li>
            <li>Live readings in the menu bar with icons and colors</li>
            <li>Pin any readings anywhere — six shapes, nine themes, presets</li>
            <li>Refresh rate, ping, Wi‑Fi signal, disk activity, power draw, battery health</li>
            <li>Fast-drain alerts and “Will my battery last?” with Low Power Mode advice</li>
            <li>One-click clearing in Free Up Space, and complete app removal</li>
            <li>7- and 30-day data history, full “While you were away”</li>
            <li>Works on every Mac signed in to your Apple Account</li>
          </ul>
          <AppStoreButton>Start the free trial</AppStoreButton>
        </div>
      </div>

      <div className="table-wrap matrix">
        <table>
          <thead><tr><th scope="col">Feature</th><th scope="col">Free</th><th scope="col">Pro</th></tr></thead>
          <tbody>
            {MATRIX.map(([f, a, b]) => (
              <tr key={f}><th scope="row">{f}</th><td><Cell v={a} /></td><td><Cell v={b} /></td></tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="footnote center">Requires {MIN_MACOS} or later. Battery features need a MacBook. Prices in USD; your App Store shows your local price.</p>
    </Section>
  );
}

const FAQS = [
  ['Does Vitals slow my Mac down or drain the battery itself?', 'No. It checks every few seconds and typically uses well under 1% CPU. Feel free to watch it in Activity Monitor.'],
  ['Will it nag me?', 'Vitals only speaks up when a problem has lasted long enough to matter. Pick Relaxed, Balanced or Sensitive, snooze any alert, or tell it to always ignore one. And no notification ever advertises Pro.'],
  ['What does Vitals send over the internet?', 'Nothing about you. There’s no account, no analytics and no tracking. The optional Ping reading times a connection to Apple’s captive.apple.com, and showing or activating a license key talks to our license server. Purchases go through Apple.'],
  ['Why does it ask for my home folder?', 'Mac App Store apps can only look at folders you choose. Free Up Space asks once so it can find files you might want to clear. It scans on your Mac and only moves files to the Trash when you pick them.'],
  ['How does the free trial work?', `Start it in Settings › Pro. Everything is unlocked for ${TRIAL_DAYS} days, with no payment details needed. When it ends, Pro features lock again and the free features keep working. You’re never charged unless you buy Pro.`],
  ['Is it really one payment?', `Yes. ${PRICE} once unlocks every Pro feature. Use Restore Purchase on any Mac signed in to the same Apple Account.`],
  ['Can I use my purchase outside the App Store?', 'Yes. Your Pro purchase includes one license key for the direct-download edition of Vitals. Open Settings › Pro › Show My License Key. Each key works on one Mac at a time — remove it from the old Mac to move it.'],
  ['Which Macs are supported?', 'Any Mac running macOS 14 Sonoma or later, Apple silicon or Intel. Battery features need a MacBook.'],
];

export function FAQ() {
  return (
    <Section id="faq">
      <div className="split faq-split">
        <SecHead kicker="FAQ" title="Questions, answered.">
          Something else? <a href="/support">Visit support</a> and you’ll hear back from the developer.
        </SecHead>
        <div className="faq">
          {FAQS.map(([q, a]) => (
            <details key={q}>
              <summary>{q}</summary>
              <p>{a}</p>
            </details>
          ))}
        </div>
      </div>
    </Section>
  );
}

export function FinalCTA() {
  return (
    <section className="final">
      <div className="wrap final-inner">
        <div className="final-lamp" aria-hidden="true"><span /></div>
        <h2>Let your Mac tell you what’s wrong.</h2>
        <p>Free on the Mac App Store. Pro is {PRICE} once, with a {TRIAL_DAYS}-day free trial.</p>
        <AppStoreButton />
      </div>
    </section>
  );
}
