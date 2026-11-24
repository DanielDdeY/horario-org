import { createContext } from 'react'
import type { LoginRequest, LoginResponse } from '../../api/horarioApi'

export interface AuthContextValue {
  session: LoginResponse | null
  login: (credentials: LoginRequest) => Promise<LoginResponse>
  logout: () => void
}

export const AuthContext = createContext<AuthContextValue | null>(null)
