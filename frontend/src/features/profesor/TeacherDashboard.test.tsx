// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { TeacherDashboard } from './TeacherDashboard'
import { AuthContext } from '../../app/auth/AuthContext'
import type { TeacherProfile } from '../../api/horarioApi'
import {
  getCourses,
  getNotices,
  getTeacherProfile,
  proposeCourseSchedule,
  updateAvailability,
} from '../../api/horarioApi'

vi.mock('../../api/horarioApi', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../../api/horarioApi')>()
  return {
    ...actual,
    getCourses: vi.fn(),
    getNotices: vi.fn(),
    getTeacherProfile: vi.fn(),
    proposeCourseSchedule: vi.fn(),
    updateAvailability: vi.fn(),
  }
})

const profile: TeacherProfile = {
  version: 1,
  id: 1,
  nombre: 'Ana Torres',
  categoriaId: 2,
  cursosAptos: [10],
  usuario: 'profesor1',
  periodoId: 20261,
  disponibilidad: [{ dia: 1, inicioMin: 480, finMin: 720 }],
  propuestas: [],
  avisosGenerados: [],
}

function renderDashboard() {
  return render(
    <AuthContext.Provider
      value={{
        session: {
          version: 1,
          token: 'test-token',
          rol: 'profesor',
          profesorId: 1,
          expiraEn: '2026-11-25T00:00:00Z',
        },
        login: vi.fn(),
        logout: vi.fn(),
      }}
    >
      <TeacherDashboard />
    </AuthContext.Provider>,
  )
}

describe('pantalla de profesor', () => {
  afterEach(cleanup)

  beforeEach(() => {
    vi.clearAllMocks()
    vi.mocked(getTeacherProfile).mockResolvedValue(profile)
    vi.mocked(getCourses).mockResolvedValue([
      { id: 10, codigo: 'string', nombre: 'string', categoriaId: 2 },
    ])
    vi.mocked(getNotices).mockResolvedValue([])
    vi.mocked(updateAvailability).mockImplementation(async (_id, _period, disponibilidad) => ({
      ...profile,
      disponibilidad,
    }))
    vi.mocked(proposeCourseSchedule).mockResolvedValue({
      version: 1,
      id: 31,
      profesorId: 1,
      cursoId: 10,
      periodoId: 20261,
      estado: 'propuesto',
      franjas: [{ dia: 2, inicioMin: 510, finMin: 660 }],
    })
  })

  it('muestra etiqueta legible para el ejemplo string de Prism sin alterar el ID seleccionado', async () => {
    renderDashboard()

    const courseSelect = await screen.findByRole('combobox', { name: 'Curso de mi categoría' })
    expect(within(courseSelect).getByRole('option', { name: 'Curso #10 (Mock)' })).toBeTruthy()
    expect(courseSelect.querySelector('option[value="10"]')?.textContent).toBe('Curso #10 (Mock)')
    expect(screen.getByRole('heading', { name: 'Mis cursos aptos' })).toBeTruthy()
    expect(screen.getByRole('heading', { name: 'Avisos' })).toBeTruthy()
    expect(screen.getByRole('button', { name: 'Cerrar sesión' })).toBeTruthy()
    expect(getCourses).toHaveBeenCalledOnce()
  })

  it('envía disponibilidad válida como minutos enteros y acepta fin 24:00', async () => {
    renderDashboard()
    const user = userEvent.setup()

    await screen.findByRole('heading', { name: 'Mi disponibilidad' })
    await user.clear(screen.getByRole('textbox', { name: 'Hora de inicio del intervalo 1' }))
    await user.type(screen.getByRole('textbox', { name: 'Hora de inicio del intervalo 1' }), '23:00')
    await user.clear(screen.getByRole('textbox', { name: 'Hora de fin del intervalo 1' }))
    await user.type(screen.getByRole('textbox', { name: 'Hora de fin del intervalo 1' }), '24:00')
    await user.click(screen.getByRole('button', { name: 'Guardar disponibilidad' }))

    await waitFor(() => {
      expect(updateAvailability).toHaveBeenCalledWith(
        1,
        20261,
        [{ dia: 1, inicioMin: 1380, finMin: 1440 }],
      )
    })
    expect((await screen.findByRole('status')).textContent).toContain('Tu disponibilidad se guardó correctamente.')
  })

  it('bloquea un rango vacío y no llama a la API', async () => {
    renderDashboard()
    const user = userEvent.setup()

    await screen.findByRole('heading', { name: 'Mi disponibilidad' })
    await user.clear(screen.getByRole('textbox', { name: 'Hora de inicio del intervalo 1' }))
    await user.type(screen.getByRole('textbox', { name: 'Hora de inicio del intervalo 1' }), '10:00')
    await user.clear(screen.getByRole('textbox', { name: 'Hora de fin del intervalo 1' }))
    await user.type(screen.getByRole('textbox', { name: 'Hora de fin del intervalo 1' }), '10:00')
    fireEvent.submit(screen.getByRole('button', { name: 'Guardar disponibilidad' }).closest('form')!)

    expect((await screen.findByRole('alert')).textContent).toContain('La hora de fin debe ser posterior')
    expect(updateAvailability).not.toHaveBeenCalled()
  })

  it('envía una propuesta con curso y horas convertidas, y recarga las propuestas', async () => {
    renderDashboard()
    const user = userEvent.setup()

    await screen.findByRole('heading', { name: 'Mis propuestas' })
    await user.selectOptions(
      screen.getByRole('combobox', { name: 'Curso de mi categoría' }),
      '10',
    )
    await user.selectOptions(screen.getByRole('combobox', { name: 'Día' }), '2')
    await user.type(screen.getByRole('textbox', { name: 'Desde' }), '08:30')
    await user.type(screen.getByRole('textbox', { name: 'Hasta' }), '11:00')
    await user.click(screen.getByRole('button', { name: 'Enviar propuesta' }))

    await waitFor(() => {
      expect(proposeCourseSchedule).toHaveBeenCalledWith(1, {
        cursoId: 10,
        periodoId: 20261,
        franjas: [{ dia: 2, inicioMin: 510, finMin: 660 }],
      })
    })
    expect(getTeacherProfile).toHaveBeenCalledTimes(2)
    expect((await screen.findByRole('status')).textContent).toContain('Tu propuesta se envió al coordinador')
  })
})
