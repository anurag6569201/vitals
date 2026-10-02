import { useReveal } from '../components/hooks.js';

export function Section({ id, className = '', children }) {
  const [ref, shown] = useReveal();
  return (
    <section id={id} ref={ref} className={`section reveal${shown ? ' in' : ''} ${className}`}>
      <div className="wrap">{children}</div>
    </section>
  );
}

export function SecHead({ kicker, title, children, center = false }) {
  return (
    <div className={`sec-head${center ? ' center' : ''}`}>
      {kicker && <div className="kicker">{kicker}</div>}
      <h2>{title}</h2>
      {children && <p>{children}</p>}
    </div>
  );
}

export const ProTag = () => <span className="pro">PRO</span>;
export const FreeTag = () => <span className="free">FREE</span>;
