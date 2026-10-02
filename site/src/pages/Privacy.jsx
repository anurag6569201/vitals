import { DocPage } from '../components/Layout.jsx';
import { SUPPORT_EMAIL } from '../config.js';

export default function Privacy() {
  return (
    <DocPage title="Privacy Policy" lede={<p className="muted">Last updated: 2 October 2026</p>}>
      <div className="card"><b>In short:</b> Vitals collects no data. Everything it reads and stores stays on your Mac.</div>
      <p>This policy covers Vitals for Mac, distributed on the Mac App Store.</p>

      <h2>What Vitals reads</h2>
      <p>CPU, GPU, memory, disk, network totals, battery and thermal state, display refresh rate and Wi‑Fi signal strength. It uses these only to show readings and alerts on your Mac.</p>

      <h2>What Vitals stores, on your Mac only</h2>
      <ul>
        <li>Your settings.</li>
        <li>A short history of readings and your recent “While you were away” reports.</li>
        <li>“Where your data went”: how much this Mac downloaded and uploaded each hour, and over which connection, kept for up to 31 days.</li>
      </ul>
      <p>None of this leaves your Mac. Deleting Vitals deletes it.</p>

      <h2>Files and Free Up Space</h2>
      <p>If you choose your home folder, Vitals scans it on your Mac to show what’s using space. It never uploads, copies or shares your files. Files are moved to the Trash only when you select them and confirm.</p>

      <h2>What Vitals sends</h2>
      <p>Only if you turn on the optional <b>Ping</b> reading: every few seconds Vitals opens (and immediately closes) a connection to Apple’s connectivity-check server, captive.apple.com, to time how long it takes. No information about you or your Mac is sent. Otherwise, nothing. Vitals has no analytics, no advertising, no tracking, no third-party code that collects data, and no account.</p>

      <h2>Purchases</h2>
      <p>The free trial and Vitals Pro are in-app purchases handled by Apple. Vitals never sees your payment details. If you choose <b>Show My License Key</b>, Vitals sends Apple’s signed record of your Pro purchase (it contains no name, email or payment details) to our license server, which returns your key. When you activate a key, Vitals sends the key and an anonymous, one-way hash of your Mac’s hardware id so the key can be limited to one Mac. See <a href="https://www.apple.com/legal/privacy/">Apple’s Privacy Policy</a>.</p>

      <h2>This website</h2>
      <p>This website uses no cookies, analytics or trackers. Fonts are loaded from Google Fonts. If you pick a light or dark theme here, that choice is saved in your browser only.</p>

      <h2>Notifications</h2>
      <p>If you allow them, notifications are created on your Mac by Vitals itself. No push service is used.</p>

      <h2>Children</h2>
      <p>Vitals collects no personal information from anyone, including children.</p>

      <h2>Changes</h2>
      <p>If this policy changes, the new version will be posted here with a new date.</p>

      <h2>Contact</h2>
      <p>Questions: <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a></p>
    </DocPage>
  );
}
