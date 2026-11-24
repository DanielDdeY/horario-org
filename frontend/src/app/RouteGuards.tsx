import { Navigate, Outlet } from 'react-router-dom'
import { useAuth } from './auth/useAuth'

export function HomeRedirect() {
  const { session } = useAuth()
  if (!session) return <Navigate to="/login" replace />
  return <Navigate to={session.rol === 'profesor' ? '/profesor' : '/coordinador'} replace />
}

export function RequireRole({ role }: { role: 'profesor' | 'coordinador' }) {
  const { session } = useAuth()
  if (!session) return <Navigate to="/login" replace />
  if (session.rol !== role) {
    return <Navigate to={session.rol === 'profesor' ? '/profesor' : '/coordinador'} replace />
  }
  return <Outlet />
}

export function CoordinatorPlaceholder() {
  const { logout } = useAuth()

  return (
    <>
      <header className="topbar">
        <a className="wordmark" href="/" aria-label="Horario, inicio">
          <span className="brand-mark brand-mark-small" aria-hidden="true">H</span>
          <span>horario<span className="wordmark-dot">.</span></span>
        </a>
        <button className="button button-quiet" onClick={logout} type="button">Cerrar sesión</button>
      </header>
      <main className="workspace-empty">
        <p className="eyebrow">Módulo coordinador</p>
        <h1>Espacio reservado para M4</h1>
        <p>Las rutas del coordinador se conectarán aquí sin modificar las pantallas del profesor.</p>
      </main>
    </>
  )
}
