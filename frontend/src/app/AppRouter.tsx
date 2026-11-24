import { useMemo } from 'react'
import { RouterProvider, type RouteObject } from 'react-router-dom'
import { AuthProvider } from './auth/AuthProvider'
import { createAppRouter } from './router'

export function AppRouter({ coordinatorRoutes = [] }: { coordinatorRoutes?: RouteObject[] }) {
  const router = useMemo(() => createAppRouter(coordinatorRoutes), [coordinatorRoutes])
  return (
    <AuthProvider>
      <RouterProvider router={router} />
    </AuthProvider>
  )
}
