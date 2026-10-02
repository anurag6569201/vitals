import { hydrateRoot, createRoot } from 'react-dom/client';
import '../styles.css';
import Privacy from '../pages/Privacy.jsx';

const root = document.getElementById('root');
if (root.firstElementChild) hydrateRoot(root, <Privacy />);
else createRoot(root).render(<Privacy />);
