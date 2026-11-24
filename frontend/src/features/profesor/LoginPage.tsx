import { useState, type FormEvent } from 'react'
import { Navigate, useNavigate } from 'react-router-dom'
import { useAuth } from '../../app/auth/useAuth'

export function LoginPage() {
  const { session, login } = useAuth()
  const navigate = useNavigate()
  const [usuario, setUsuario] = useState('')
  const [contrasena, setContrasena] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)

  if (session) return <Navigate to={session.rol === 'profesor' ? '/profesor' : '/coordinador'} replace />

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setError(null)
    setSubmitting(true)

    try {
      const result = await login({ usuario, contrasena })
      navigate(result.rol === 'profesor' ? '/profesor' : '/coordinador', { replace: true })
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'No se pudo iniciar sesión.')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <main className="login-page">
      <section className="login-card">
        <div className="brand-mark" aria-hidden="true">H</div>
        <p className="eyebrow">HORARIO · UNIVERSIDAD</p>
        <h1>Bienvenido</h1>
        <p className="muted">Ingresa para consultar y organizar tu disponibilidad docente.</p>
        <form className="form-stack" onSubmit={handleSubmit}>
          <label>
            Usuario
            <input
              autoComplete="username"
              name="usuario"
              required
              value={usuario}
              onChange={(event) => setUsuario(event.target.value)}
            />
          </label>
          <label>
            Contraseña
            <input
              autoComplete="current-password"
              name="contrasena"
              required
              type="password"
              value={contrasena}
              onChange={(event) => setContrasena(event.target.value)}
            />
          </label>
          {error && <p className="message message-error" role="alert">{error}</p>}
          <button className="button button-primary button-wide" disabled={submitting} type="submit">
            {submitting ? 'Ingresando…' : 'Iniciar sesión'}
          </button>
        </form>
      </section>
    </main>
  )
}
