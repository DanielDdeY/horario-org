// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest'
import { cleanup, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Route, Routes, useLocation } from 'react-router-dom'
import type { AuthContextValue } from '../../app/auth/AuthContext'
import { AuthContext } from '../../app/auth/AuthContext'
import { LoginPage } from './LoginPage'

function CurrentPath() {
  const location = useLocation()
  return <p data-testid="current-path">{location.pathname}</p>
}

describe('pantalla de inicio de sesión', () => {
  afterEach(cleanup)

  it('envía las credenciales e ingresa a la ruta del profesor', async () => {
    const login = vi.fn<AuthContextValue['login']>().mockResolvedValue({
      version: 1,
      token: 'professor-token',
      rol: 'profesor',
      profesorId: 1,
      expiraEn: '2026-11-25T00:00:00Z',
    })

    render(
      <AuthContext.Provider value={{ session: null, login, logout: vi.fn() }}>
        <MemoryRouter initialEntries={['/login']}>
          <CurrentPath />
          <Routes>
            <Route path="/login" element={<LoginPage />} />
            <Route path="/profesor" element={<p>Portal docente</p>} />
          </Routes>
        </MemoryRouter>
      </AuthContext.Provider>,
    )

    const user = userEvent.setup()
    await user.type(screen.getByRole('textbox', { name: 'Usuario' }), 'profesor1')
    await user.type(screen.getByLabelText('Contraseña'), 'clave-demo')
    await user.click(screen.getByRole('button', { name: 'Iniciar sesión' }))

    expect(await screen.findByText('Portal docente')).toBeTruthy()
    expect(login).toHaveBeenCalledWith({ usuario: 'profesor1', contrasena: 'clave-demo' })
  })
})
