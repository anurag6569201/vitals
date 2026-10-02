import { useEffect, useState } from 'react';
import { APP_STORE_URL } from '../config.js';
import { Apple, Auto, Moon, Pulse, Sun } from './Icons.jsx';

export function Logo({ size = 26 }) {
  return (
    <a className="brand" href="/" aria-label="Vitals home">
      <span className="brand-mark"><Pulse size={size * 0.62} width={2.8} /></span>
      Vitals
    </a>
  );
}

const MODES = ['system', 'light', 'dark'];
const LABEL = { system: 'Theme: match system', light: 'Theme: light', dark: 'Theme: dark' };

export function ThemeToggle() {
  const [mode, setMode] = useState('system');
  useEffect(() => {
    const t = document.documentElement.getAttribute('data-theme');
    if (t === 'light' || t === 'dark') setMode(t);
  }, []);
  const next = () => {
    const m = MODES[(MODES.indexOf(mode) + 1) % MODES.length];
    setMode(m);
    const d = document.documentElement;
    if (m === 'system') d.removeAttribute('data-theme');
    else d.setAttribute('data-theme', m);
    try {
      if (m === 'system') localStorage.removeItem('vitals-theme');
      else localStorage.setItem('vitals-theme', m);
    } catch (e) { /* storage unavailable */ }
  };
  return (
    <button type="button" className="icon-btn" onClick={next} aria-label={LABEL[mode]} title={LABEL[mode]}>
      {mode === 'light' ? <Sun /> : mode === 'dark' ? <Moon /> : <Auto />}
    </button>
  );
}

export function AppStoreButton({ children = 'Get it on the Mac App Store', variant = 'primary', className = '' }) {
  return (
    <a className={`btn ${variant} ${className}`} href={APP_STORE_URL}>
      <Apple /> {children}
    </a>
  );
}

export function Nav({ links }) {
  const [scrolled, setScrolled] = useState(false);
  useEffect(() => {
    const on = () => setScrolled(window.scrollY > 8);
    on();
    window.addEventListener('scroll', on, { passive: true });
    return () => window.removeEventListener('scroll', on);
  }, []);
  return (
    <div className={`nav-shell${scrolled ? ' scrolled' : ''}`}>
      <nav className="wrap nav" aria-label="Main">
        <Logo />
        <div className="navlinks">
          {links.map(([href, label]) => (
            <a key={href} href={href}>{label}</a>
          ))}
        </div>
        <div className="nav-end">
          <ThemeToggle />
          <a className="btn primary small nav-cta" href={APP_STORE_URL}>Download</a>
        </div>
      </nav>
    </div>
  );
}

export function Footer() {
  return (
    <footer className="wrap footer">
      <div className="footer-brand">
        <Logo size={22} />
        <p>The check-engine light for your Mac. Made by an independent developer.</p>
      </div>
      <div className="footer-cols">
        <div>
          <h4>Product</h4>
          <a href="/#catches">Alerts</a>
          <a href="/#pin">On Screen pin</a>
          <a href="/#space">Free Up Space</a>
          <a href="/#data">Data usage</a>
          <a href="/#pricing">Pricing</a>
        </div>
        <div>
          <h4>Help</h4>
          <a href="/support">Support</a>
          <a href="/#faq">FAQ</a>
          <a href="/privacy">Privacy</a>
          <a href={APP_STORE_URL}>Mac App Store</a>
        </div>
      </div>
      <p className="footer-fine">© 2026 Vitals · Mac, macOS and Mac App Store are trademarks of Apple Inc.</p>
    </footer>
  );
}

export function DocPage({ title, lede, children }) {
  return (
    <>
      <Nav links={[['/#catches', 'Features'], ['/#pricing', 'Pricing'], ['/support', 'Support'], ['/privacy', 'Privacy']]} />
      <main className="wrap doc">
        <header className="doc-head">
          <h1>{title}</h1>
          {lede}
        </header>
        {children}
      </main>
      <Footer />
    </>
  );
}

