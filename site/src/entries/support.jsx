import { hydrateRoot, createRoot } from 'react-dom/client';
import '../styles.css';
import Support from '../pages/Support.jsx';

const root = document.getElementById('root');
if (root.firstElementChild) hydrateRoot(root, <Support />);
else createRoot(root).render(<Support />);
