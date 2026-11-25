// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest'
import { cleanup, render, screen } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import type { AuthContextValue } from './auth/AuthContext'
import { AuthContext } from './auth/AuthContext'
import { RequireRole } from './RouteGuards'

function renderProtectedTeacherRoute(session: AuthContextValue['session']) {
  return render(
    <AuthContext.Provider value={{ session, login: vi.fn(), logout: vi.fn() }}>
      <MemoryRouter initialEntries={['/profesor']}>
        <Routes>
          <Route path="/login" element={<p>Inicio de sesión</p>} />
          <Route path="/coordinador" element={<p>Área de coordinador</p>} />
          <Route element={<RequireRole role="profesor" />}>
            <Route path="/profesor" element={<p>Mi disponibilidad</p>} />
          </Route>
        </Routes>
      </MemoryRouter>
    </AuthContext.Provider>,
  )
}

describe('protección de rutas por sesión y rol', () => {
  afterEach(cleanup)

  it('redirige al login al intentar acceder a una ruta protegida sin sesión', () => {
    renderProtectedTeacherRoute(null)
    expect(screen.getByText('Inicio de sesión')).toBeTruthy()
    expect(screen.queryByText('Mi disponibilidad')).toBeNull()
  })

  it('redirige al área correcta si la sesión pertenece a otro rol', () => {
    renderProtectedTeacherRoute({
      version: 1,
      token: 'coordinator-token',
      rol: 'coordinador',
      profesorId: null,
      expiraEn: '2026-11-25T00:00:00Z',
    })
    expect(screen.getByText('Área de coordinador')).toBeTruthy()
    expect(screen.queryByText('Mi disponibilidad')).toBeNull()
  })
})
