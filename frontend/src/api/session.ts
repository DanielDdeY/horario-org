import type { components } from './schema'

export type AuthSession = components['schemas']['LoginRespuesta']
export type Role = AuthSession['rol']

const SESSION_KEY = 'horario-org-session'

export function readSession(): AuthSession | null {
  const value = window.sessionStorage.getItem(SESSION_KEY)
  if (!value) return null

  try {
    const parsed: unknown = JSON.parse(value)
    if (
      typeof parsed === 'object' &&
      parsed !== null &&
      'version' in parsed &&
      parsed.version === 1 &&
      'token' in parsed &&
      typeof parsed.token === 'string' &&
      'rol' in parsed &&
      (parsed.rol === 'profesor' || parsed.rol === 'coordinador') &&
      'profesorId' in parsed &&
      (typeof parsed.profesorId === 'number' || parsed.profesorId === null) &&
      'expiraEn' in parsed &&
      typeof parsed.expiraEn === 'string'
    ) {
      return parsed as AuthSession
    }
  } catch {
    window.sessionStorage.removeItem(SESSION_KEY)
    return null
  }

  window.sessionStorage.removeItem(SESSION_KEY)
  return null
}

export function saveSession(session: AuthSession): void {
  window.sessionStorage.setItem(SESSION_KEY, JSON.stringify(session))
}

export function removeSession(): void {
  window.sessionStorage.removeItem(SESSION_KEY)
}
