import {
  createBrowserRouter,
  type RouteObject,
} from 'react-router-dom'
import { CoordinatorPlaceholder, HomeRedirect, RequireRole } from './RouteGuards'
import { LoginPage } from '../features/profesor/LoginPage'
import { TeacherDashboard } from '../features/profesor/TeacherDashboard'

export function createAppRouter(coordinatorRoutes: RouteObject[] = []) {
  return createBrowserRouter([
    { path: '/', element: <HomeRedirect /> },
    { path: '/login', element: <LoginPage /> },
    {
      element: <RequireRole role="profesor" />,
      children: [{ path: '/profesor', element: <TeacherDashboard /> }],
    },
    {
      path: '/coordinador',
      element: <RequireRole role="coordinador" />,
      children: [
        { index: true, element: <CoordinatorPlaceholder /> },
        ...coordinatorRoutes,
      ],
    },
    { path: '*', element: <HomeRedirect /> },
  ])
}
