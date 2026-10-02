import { Nav, Footer } from '../components/Layout.jsx';
import Hero from '../sections/Hero.jsx';
import Alerts, { TrustStrip } from '../sections/Alerts.jsx';
import Pin from '../sections/Pin.jsx';
import { BatterySection, DataUsage, FreeUpSpace, Readings, Shortcuts } from '../sections/Features.jsx';
import { Compare, FAQ, FinalCTA, Pricing } from '../sections/Pricing.jsx';
import Editions from '../sections/Editions.jsx';

const LINKS = [
  ['#catches', 'Alerts'],
  ['#pin', 'Pin'],
  ['#space', 'Free Up Space'],
  ['#data', 'Data'],
  ['#pricing', 'Pricing'],
  ['#download', 'Download'],
  ['#faq', 'FAQ'],
];

export default function Home() {
  return (
    <>
      <a className="skip" href="#main">Skip to content</a>
      <Nav links={LINKS} />
      <main id="main">
        <Hero />
        <TrustStrip />
        <Alerts />
        <Pin />
        <Readings />
        <FreeUpSpace />
        <DataUsage />
        <BatterySection />
        <Shortcuts />
        <Compare />
        <Pricing />
        <Editions />
        <FAQ />
        <FinalCTA />
      </main>
      <Footer />
    </>
  );
}
