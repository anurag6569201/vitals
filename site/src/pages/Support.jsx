import { DocPage } from '../components/Layout.jsx';
import { SUPPORT_EMAIL, PRICE, TRIAL_DAYS } from '../config.js';

const QA = [
  ['I can’t see the Vitals icon in the menu bar', <>
    <p>On MacBooks with a notch, icons that don’t fit are hidden behind the notch or in the overflow menu. Try:</p>
    <ul>
      <li>Hold <kbd>⌘</kbd> and drag Vitals’ icon further right in the menu bar.</li>
      <li>Remove icons you don’t need in System Settings › Menu Bar.</li>
      <li>Open Vitals from Launchpad or Applications: its Settings window opens, and you can set a keyboard shortcut there.</li>
    </ul>
  </>],
  ['I’m not getting notifications', <p>Open System Settings › Notifications › Vitals and turn on Allow Notifications. Also check that “Notify me when something needs attention” is on in Vitals › Settings › General. While notifications are off, Vitals shows its alerts inside its menu instead, so you never miss one.</p>],
  ['How do I set up the On Screen pin?', <p>Click the pin button at the bottom of the Vitals menu, or open Settings › On Screen. Pick a preset or choose a shape, theme and readings yourself, then drag the pin wherever you like. The free version pins one reading in the Edge Dock; Pro unlocks every shape, theme and reading.</p>],
  ['How does the hotspot data guard work?', <p>Turn it on in Settings › Alerts › Hotspot data guard and choose a limit. macOS marks iPhone Personal Hotspot, tethering and Low Data Mode networks as metered; Vitals counts from the moment you join one and warns you at 80% and 100% of your limit.</p>],
  ['How do I make Vitals open when I log in?', <p>Turn on “Open Vitals when you log in” in Settings › General. It’s off until you choose it. If macOS asks for approval, go to System Settings › General › Login Items.</p>],
  ['Why does Free Up Space ask for my home folder?', <p>Mac App Store apps can only read folders you pick. Vitals asks once and remembers the choice. It scans on your Mac, uploads nothing, and moves files to the Trash only when you select them. If it asks again, choose your home folder (the one with your name) and click Allow.</p>],
  ['I cleared something by mistake', <p>Vitals only moves files to the Trash. Open the Trash in the Dock, right-click the item and choose Put Back.</p>],
  ['How does the free trial work?', <p>Start it in Settings › Pro. Every Pro feature is unlocked for {TRIAL_DAYS} days, and no payment details are needed. When it ends, Pro features lock again and the free features keep working. You’re never charged unless you buy Vitals Pro ({PRICE}, once).</p>],
  ['I bought Pro but it’s locked on another Mac', <p>Sign in to the Mac App Store with the same Apple Account, then open Vitals › Settings › Pro and click <b>Restore Purchase</b>.</p>],
  ['Can I use my App Store purchase outside the App Store?', <p>Yes. Your Vitals Pro purchase includes one license key. Open Vitals › Settings › Pro and choose <b>Show My License Key</b>, then paste it into Settings › Pro in the direct-download edition of Vitals. Each key works on one Mac at a time — to move it, choose “Remove License From This Mac” on the old Mac first.</p>],
  ['Can I use Vitals with Shortcuts?', <p>Yes. Open the Shortcuts app and search for Vitals. Actions include How Is My Mac Doing, How Much Data Did I Use Today, Keep My Mac Awake and Show or Hide the Vitals Pin.</p>],
  ['How do I uninstall Vitals?', <p>Click the power button at the bottom of the Vitals menu to quit, then drag Vitals from Applications to the Trash. Its settings and history are removed with it.</p>],
  ['Does Vitals collect any data?', <p>No. See the <a href="/privacy">privacy policy</a>.</p>],
];

export default function Support() {
  return (
    <DocPage
      title="Vitals Support"
      lede={<p className="muted">Something not working, or an idea? Email and you’ll hear back from the developer, usually within two days.</p>}
    >
      <div className="card contact">
        <div>
          <b>Email</b>
          <a href={`mailto:${SUPPORT_EMAIL}?subject=Vitals%20support`}>{SUPPORT_EMAIL}</a>
          <span className="muted">It helps to include your macOS version and Vitals version (Settings › About).</span>
        </div>
        <a className="btn primary small" href={`mailto:${SUPPORT_EMAIL}?subject=Vitals%20support`}>Write to us</a>
      </div>

      <h2>Common questions</h2>
      <div className="faq">
        {QA.map(([q, a]) => (
          <details key={q}><summary>{q}</summary>{a}</details>
        ))}
      </div>

      <h2>Requirements</h2>
      <p>macOS 14 Sonoma or later, on Apple silicon or Intel. Battery features need a MacBook.</p>
    </DocPage>
  );
}
