import { renderToString } from 'react-dom/server';
import Home from './pages/Home.jsx';
import Support from './pages/Support.jsx';
import Privacy from './pages/Privacy.jsx';

const pages = { index: Home, support: Support, privacy: Privacy };

export function render(name) {
  const Page = pages[name];
  return renderToString(<Page />);
}
