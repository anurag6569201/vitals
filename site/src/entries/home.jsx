import { hydrateRoot, createRoot } from 'react-dom/client';
import '../styles.css';
import Home from '../pages/Home.jsx';

const root = document.getElementById('root');
if (root.firstElementChild) hydrateRoot(root, <Home />);
else createRoot(root).render(<Home />);
