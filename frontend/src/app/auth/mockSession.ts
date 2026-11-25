import type { LoginResponse } from '../../api/horarioApi'

export function resolveLoginSession(
  response: LoginResponse,
  username: string,
  mockMode: boolean,
): LoginResponse {
  if (!mockMode || username.trim().toLocaleLowerCase() === 'coordinador') {
    return response
  }

  return {
    ...response,
    rol: 'profesor',
    profesorId: response.profesorId ?? 1,
  }
}
