import { describe, expect, it } from 'vitest'
import type { LoginResponse } from '../../api/horarioApi'
import { resolveLoginSession } from './mockSession'

const prismResponse: LoginResponse = {
  version: 1,
  token: 'mock-token',
  rol: 'coordinador',
  profesorId: null,
  expiraEn: '2026-11-24T23:00:00Z',
}

describe('sesión de autenticación con Prism', () => {
  it('asigna rol profesor e ID válido a usuarios distintos del coordinador', () => {
    const session = resolveLoginSession(prismResponse, 'profesor1', true)
    expect(session.rol).toBe('profesor')
    expect(session.profesorId).toBe(1)
  })

  it('conserva el ejemplo de coordinador', () => {
    const session = resolveLoginSession(prismResponse, 'coordinador', true)
    expect(session).toEqual(prismResponse)
  })

  it('no transforma respuestas cuando se usa la API real', () => {
    const session = resolveLoginSession(prismResponse, 'profesor1', false)
    expect(session).toEqual(prismResponse)
  })
})
