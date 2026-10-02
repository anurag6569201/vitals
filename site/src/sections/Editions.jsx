import { Section, SecHead, ProTag } from './common.jsx';
import { AppStoreButton, DownloadButton } from '../components/Layout.jsx';
import { Check } from '../components/Icons.jsx';
import { BUY_URL, PRICE, canBuyDirect } from '../config.js';

// What only the direct download can do. Mirrors `Edition` in Vitals/App/AppSettings.swift:
// Mac App Store apps are sandboxed, so they can't see or quit other apps or hide menu-bar icons.
const ROWS = [
  ['Alerts, battery tools, Space Map, pin, data usage', true, true],
  ['Free Up Space', 'Your home folder', 'Also Docker disk images, iPhone & iPad backups, app containers'],
  ['Runaway-app alerts (“Chrome has used 180% CPU for 12 min”)', false, true],
  ['Quit the app causing a problem, right from the alert', false, true],
  ['“Apps using your Mac” and the busiest app in the menu bar', false, true],
  ['Battery planner tells you which apps to quit', false, true],
  ['Where your data went, per app', false, true],
  ['Hide menu-bar icons you don’t need', false, true],
  ['Updates', 'Through the App Store', 'Built-in update check'],
  ['Buy Pro', 'In-app purchase', canBuyDirect ? 'License key' : 'License key (included with an App Store purchase)'],
];

function Cell({ v }) {
  if (v === true) return <span className="yes"><Check size={16} /><span className="sr">Yes</span></span>;
  if (v === false) return <span className="no">—<span className="sr">No</span></span>;
  return <span>{v}</span>;
}

export default function Editions() {
  return (
    <Section id="download" className="tint">
      <SecHead kicker="Two editions" title="Get it from the App Store, or download the full version." center>
        Same app, same price. The Mac App Store keeps apps in a sandbox, so that edition can’t look at or quit other
        apps. The direct download can — it’s signed with Apple’s Developer ID and notarized by Apple.
      </SecHead>

      <div className="editions">
        <div className="edition">
          <div className="edition-top">
            <h3>Mac App Store</h3>
            <span className="edition-tag">Simplest</span>
          </div>
          <p>Install and update through the App Store. Buy Pro with your Apple Account and it works on all your Macs.</p>
          <ul className="checks">
            <li><Check /><span>Every alert about your Mac itself: heat, memory, disk, battery, restarts</span></li>
            <li><Check /><span>Free Up Space, Space Map and complete app removal</span></li>
            <li><Check /><span>Pro {PRICE} once includes a license key for the full version</span></li>
          </ul>
          <AppStoreButton />
        </div>

        <div className="edition feature">
          <div className="edition-top">
            <h3>Full version</h3>
            <span className="edition-tag strong">Everything</span>
          </div>
          <p>Download from this site. Vitals can name the app behind a problem and quit it for you.</p>
          <ul className="checks">
            <li><Check /><span>Everything in the App Store edition</span></li>
            <li><Check /><span>Runaway-app alerts with one-click Quit, and per-app battery and data use</span></li>
            <li><Check /><span>Hide menu-bar icons you don’t need</span></li>
          </ul>
          <div className="edition-ctas">
            <DownloadButton />
            {canBuyDirect && <a className="btn ghost" href={BUY_URL}>Buy a license key · {PRICE} <ProTag /></a>}
          </div>
        </div>
      </div>

      <div className="table-wrap matrix">
        <table>
          <thead><tr><th scope="col">Compare</th><th scope="col">Mac App Store</th><th scope="col">Full version</th></tr></thead>
          <tbody>
            {ROWS.map(([f, a, b]) => (
              <tr key={f}><th scope="row">{f}</th><td><Cell v={a} /></td><td><Cell v={b} /></td></tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="footnote center">
        Already bought Pro in the App Store? Open Vitals › Settings › Pro › Show My License Key and paste it into the full
        version. One key works on one Mac at a time.
      </p>
    </Section>
  );
}
