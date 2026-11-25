export class ApiError extends Error {
  readonly code: string
  readonly status?: number

  constructor(message: string, code = 'API_ERROR', status?: number) {
    super(message)
    this.name = 'ApiError'
    this.code = code
    this.status = status
  }
}

export function toApiError(error: unknown, status?: number): ApiError {
  if (typeof error === 'object' && error !== null && 'mensaje' in error) {
    const body = error as { mensaje?: unknown; codigo?: unknown }
    if (typeof body.mensaje === 'string') {
      return new ApiError(
        body.mensaje,
        typeof body.codigo === 'string' ? body.codigo : 'API_ERROR',
        status,
      )
    }
  }

  return new ApiError('No se pudo completar la solicitud.', 'API_ERROR', status)
}
