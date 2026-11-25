import createClient from 'openapi-fetch'
import type { paths } from './schema'
import { readSession } from './session'

export const apiClient = createClient<paths>({
  baseUrl: import.meta.env.VITE_API_BASE_URL || '/api',
})

apiClient.use({
  onRequest({ request }) {
    const session = readSession()
    if (session) {
      request.headers.set('Authorization', `Bearer ${session.token}`)
    }
    return request
  },
})
