import type { components } from './schema'
import { apiClient } from './client'
import { toApiError } from './errors'

export type LoginRequest = components['schemas']['LoginSolicitud']
export type LoginResponse = components['schemas']['LoginRespuesta']
export type TeacherProfile = components['schemas']['ProfesorDetalle']
export type AvailabilitySlot = components['schemas']['Franja']
export type Course = components['schemas']['Curso']
export type Proposal = components['schemas']['Propuesta']
export type Notice = components['schemas']['Aviso']

export async function login(credentials: LoginRequest): Promise<LoginResponse> {
  const { data, error, response } = await apiClient.POST('/auth/login', {
    body: credentials,
  })

  if (error) throw toApiError(error, response.status)
  if (!data) throw new Error('La API no devolvió los datos de inicio de sesión.')
  return data
}

export async function getTeacherProfile(
  id: number,
  periodoId?: number,
): Promise<TeacherProfile> {
  const { data, error, response } = await apiClient.GET('/profesores/{id}', {
    params: {
      path: { id },
      query: periodoId ? { periodoId } : undefined,
    },
  })

  if (error) throw toApiError(error, response.status)
  if (!data) throw new Error('La API no devolvió el perfil del profesor.')
  return data
}

export async function updateAvailability(
  id: number,
  periodoId: number,
  disponibilidad: AvailabilitySlot[],
): Promise<TeacherProfile> {
  const { data, error, response } = await apiClient.PUT('/profesores/{id}', {
    params: { path: { id } },
    body: { periodoId, disponibilidad },
  })

  if (error) throw toApiError(error, response.status)
  if (!data) throw new Error('La API no devolvió el perfil actualizado.')
  return data
}

export async function getCourses(): Promise<Course[]> {
  const { data, error, response } = await apiClient.GET('/cursos')

  if (error) throw toApiError(error, response.status)
  if (!data) throw new Error('La API no devolvió la lista de cursos.')
  return data.cursos
}

export async function proposeCourseSchedule(
  id: number,
  proposal: components['schemas']['PropuestaEntrada'],
): Promise<components['schemas']['PropuestaRespuesta']> {
  const { data, error, response } = await apiClient.POST(
    '/profesores/{id}/propuestas',
    {
      params: { path: { id } },
      body: proposal,
    },
  )

  if (error) throw toApiError(error, response.status)
  if (!data) throw new Error('La API no devolvió la propuesta registrada.')
  return data
}

export async function getNotices(periodoId?: number): Promise<Notice[]> {
  const { data, error, response } = await apiClient.GET('/avisos', {
    params: { query: periodoId ? { periodoId } : undefined },
  })

  if (error) throw toApiError(error, response.status)
  if (!data) throw new Error('La API no devolvió los avisos.')
  return data.avisos
}
