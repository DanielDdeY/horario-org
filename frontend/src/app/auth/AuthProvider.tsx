import {
  useCallback,
  useState,
  type PropsWithChildren,
} from 'react'
import {
  login as loginRequest,
  type LoginRequest,
  type LoginResponse,
} from '../../api/horarioApi'
import { readSession, removeSession, saveSession } from '../../api/session'
import { AuthContext } from './AuthContext'
import { resolveLoginSession } from './mockSession'

export function AuthProvider({ children }: PropsWithChildren) {
  const [session, setSession] = useState<LoginResponse | null>(() => readSession())

  const login = useCallback(async (credentials: LoginRequest) => {
    const response = await loginRequest(credentials)
    const nextSession = resolveLoginSession(
      response,
      credentials.usuario,
      import.meta.env.VITE_API_MOCK_MODE === 'true',
    )
    if (nextSession.rol === 'profesor' && nextSession.profesorId === null) {
      throw new Error('La sesión de profesor no incluye un identificador.')
    }
    saveSession(nextSession)
    setSession(nextSession)
    return nextSession
  }, [])

  const logout = useCallback(() => {
    removeSession()
    setSession(null)
  }, [])

  return (
    <AuthContext.Provider value={{ session, login, logout }}>
      {children}
    </AuthContext.Provider>
  )
}
